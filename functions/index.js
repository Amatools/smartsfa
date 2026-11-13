const { onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const crypto = require('node:crypto');
const Stripe = require('stripe');

const SANKHYA_PRODUCTION_URL = 'https://api.sankhya.com.br/authenticate';
const SANKHYA_SANDBOX_URL =
  'https://api.sandbox.sankhya.com.br/authenticate';
const SANKHYA_PRODUCTS_PATH = '/v1/produtos?page=0';
const SANKHYA_DBEXPLORER_ENDPOINT_PATHS = [
  '/gateway/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/gateway/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
];
const TEMPORARY_IMPORT_LIMIT = 5;
const SANKHYA_IMAGE_CHUNK_BYTES = 1800;
const DEFAULT_PRODUCT_MEDIA_SCOPE_KEY = 'tenant_default';
const DEFAULT_STORAGE_BUCKET = 'smart-sfa.firebasestorage.app';
const IMPERSONATION_DEFAULT_DURATION_MINUTES = 15;
const IMPERSONATION_MIN_DURATION_MINUTES = 5;
const IMPERSONATION_MAX_DURATION_MINUTES = 30;
const STRIPE_DEFAULT_WEBHOOK_EVENTS = [
  'checkout.session.completed',
  'customer.subscription.created',
  'customer.subscription.updated',
  'customer.subscription.deleted',
  'invoice.finalized',
  'invoice.paid',
  'invoice.payment_failed',
];
const STRIPE_SYNC_BATCH_LIMIT = 120;
const STRIPE_CLIENT_CACHE = new Map();
const STRIPE_RUNTIME_SECRETS = [
  'STRIPE_SK_TEST',
  'STRIPE_SK_LIVE',
  'STRIPE_WHSEC_TEST',
  'STRIPE_WHSEC_LIVE',
  'STRIPE_ACTIVE_ENVIRONMENT',
];

if (!admin.apps.length) {
  admin.initializeApp();
}

exports.testSankhyaAuthentication = onRequest(
  { cors: true, region: 'us-central1', timeoutSeconds: 30 },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const environment = String(request.body?.environment ?? '')
      .trim()
      .toLowerCase();
    const clientId = String(request.body?.clientId ?? '').trim();
    const clientSecret = String(request.body?.clientSecret ?? '').trim();
    const xToken = String(request.body?.xToken ?? '').trim();

    if (!['homolog', 'prod'].includes(environment)) {
      response.status(400).json({
        error: 'invalid_environment',
        error_description: 'Use homolog ou prod.',
      });
      return;
    }
    if (!clientId || !clientSecret || !xToken) {
      response.status(400).json({
        error: 'missing_credentials',
        error_description: 'Client Id, Client Secret e X-Token sao obrigatorios.',
      });
      return;
    }

    const targetUrl =
      environment === 'prod'
        ? SANKHYA_PRODUCTION_URL
        : SANKHYA_SANDBOX_URL;
    const formBody = new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: 'client_credentials',
    });

    try {
      const sankhyaResponse = await fetch(targetUrl, {
        method: 'POST',
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
          'x-token': xToken,
        },
        body: formBody,
        signal: AbortSignal.timeout(15000),
      });
      const bodyText = await sankhyaResponse.text();
      let payload = {};
      try {
        payload = JSON.parse(bodyText);
      } catch (_) {
        payload = Object.fromEntries(new URLSearchParams(bodyText));
      }

      response.status(sankhyaResponse.status).json(payload);
    } catch (error) {
      response.status(502).json({
        error: 'sankhya_unavailable',
        error_description: error instanceof Error ? error.message : String(error),
      });
    }
  },
);

exports.syncSankhyaCatalogModule = onRequest(
  { cors: true, region: 'us-central1', timeoutSeconds: 300 },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const tenantId = String(request.body?.tenantId ?? '').trim();
    const moduleId = String(request.body?.module ?? '').trim().toLowerCase();
    const environment = String(request.body?.environment ?? '')
      .trim()
      .toLowerCase();
    const clientId = String(request.body?.clientId ?? '').trim();
    const clientSecret = String(request.body?.clientSecret ?? '').trim();
    const xToken = String(request.body?.xToken ?? '').trim();
    // Filtro temporario de validacao: quando presente, restringe o sync de
    // 'clientes' a uma lista explicita de CODPARC (ex.: ['191']), evitando
    // puxar a base inteira de parceiros enquanto o mapeamento de campos ainda
    // esta em teste. Vazio/ausente = sem filtro (sync completo).
    const codigosFiltroRaw = request.body?.codigosFiltro;
    const codigosFiltro = Array.isArray(codigosFiltroRaw)
      ? codigosFiltroRaw
      : [];

    if (!tenantId) {
      response.status(400).json({
        error: 'missing_tenant',
        message: 'tenantId e obrigatorio.',
      });
      return;
    }

    if (!['homolog', 'prod'].includes(environment)) {
      response.status(400).json({
        error: 'invalid_environment',
        message: 'Use homolog ou prod.',
      });
      return;
    }

    if (!clientId || !clientSecret || !xToken) {
      response.status(400).json({
        error: 'missing_credentials',
        message: 'Client Id, Client Secret e X-Token sao obrigatorios.',
      });
      return;
    }

    if (!['produtos', 'tabelas_preco', 'tax_rules', 'clientes', 'product_images'].includes(moduleId)) {
      response.status(400).json({
        error: 'module_not_enabled',
        message:
          'Modulo ainda nao habilitado para ingestao. Valide endpoint/permissao e ative o modulo.',
        module: moduleId,
      });
      return;
    }

    const firestore = admin.firestore();
    const accessValidation = await validateEnterpriseOwnerAccess({
      firestore,
      request,
      tenantId,
    });
    if (!accessValidation.allowed) {
      response.status(accessValidation.status).json({
        error: accessValidation.error,
        message: accessValidation.message,
      });
      return;
    }

    const baseUrl =
      environment === 'prod'
        ? 'https://api.sankhya.com.br'
        : 'https://api.sandbox.sankhya.com.br';

    try {
      const authPayload = await authenticateInSankhya({
        baseUrl,
        clientId,
        clientSecret,
        xToken,
      });

      const bearerToken = readBearerToken(authPayload);
      if (!bearerToken) {
        response.status(502).json({
          error: 'missing_bearer',
          message:
            'Autenticacao retornou sem access_token. Verifique credenciais e permissao do app Sankhya.',
        });
        return;
      }
      let result;
      if (moduleId === 'produtos') {
        result = await syncSankhyaProductsModule({
          firestore,
          tenantId,
          baseUrl,
          bearerToken,
          xToken,
        });
      } else if (moduleId === 'tax_rules') {
        result = await syncSankhyaTaxRulesModule({
          firestore,
          tenantId,
          baseUrl,
          bearerToken,
          xToken,
        });
      } else if (moduleId === 'clientes') {
        result = await syncSankhyaClientesModule({
          firestore,
          tenantId,
          baseUrl,
          bearerToken,
          xToken,
          codigosFiltro,
        });
      } else if (moduleId === 'product_images') {
        result = await syncSankhyaProductImagesModule({
          firestore,
          tenantId,
          baseUrl,
          bearerToken,
          xToken,
        });
      } else {
        result = await syncSankhyaPriceTablesModule({
          firestore,
          tenantId,
          baseUrl,
          bearerToken,
          xToken,
        });
      }

      response.status(200).json({
        success: true,
        module: moduleId,
        environment,
        ...result,
      });
    } catch (error) {
      response.status(502).json({
        error: 'sankhya_sync_failed',
        message: error instanceof Error ? error.message : String(error),
      });
    }
  },
);

exports.createImpersonationSession = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 60,
    serviceAccount: 'smart-sfa@appspot.gserviceaccount.com',
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const targetUid = String(request.body?.targetUid ?? '').trim();
    const targetTenantId = String(request.body?.targetTenantId ?? '').trim();
    const targetMembershipId = String(request.body?.targetMembershipId ?? '').trim();
    const reason = String(request.body?.reason ?? '').trim();
    const launchOrigin = String(request.body?.launchOrigin ?? '').trim();

    const durationInput = Number(
      request.body?.durationMinutes ?? IMPERSONATION_DEFAULT_DURATION_MINUTES,
    );
    const durationMinutes = Number.isFinite(durationInput)
      ? Math.max(
          IMPERSONATION_MIN_DURATION_MINUTES,
          Math.min(IMPERSONATION_MAX_DURATION_MINUTES, Math.floor(durationInput)),
        )
      : IMPERSONATION_DEFAULT_DURATION_MINUTES;

    if (!targetUid || !targetTenantId || !targetMembershipId) {
      response.status(400).json({
        error: 'missing_target',
        message: 'targetUid, targetTenantId e targetMembershipId sao obrigatorios.',
      });
      return;
    }

    if (reason.length < 8) {
      response.status(400).json({
        error: 'missing_reason',
        message: 'Informe motivo com ao menos 8 caracteres.',
      });
      return;
    }

    const firestore = admin.firestore();
    const authContext = await verifyFirebaseAuthFromRequest(request);
    if (!authContext.ok) {
      response.status(authContext.status).json({
        error: authContext.error,
        message: authContext.message,
      });
      return;
    }

    const actorUid = authContext.uid;
    const actorUserDoc = await firestore.collection('usuarios').doc(actorUid).get();
    const actorUserData = actorUserDoc.data() || {};
    const actorPlatformRole = String(actorUserData.platformRole ?? '').trim().toLowerCase();
    const actorActiveGlobal = actorUserData.ativoGlobal !== false;
    const actorConsoleEnabled = actorUserData.maintainerConsoleEnabled !== false;

    if (actorPlatformRole !== 'platform_admin' || !actorActiveGlobal || !actorConsoleEnabled) {
      response.status(403).json({
        error: 'forbidden',
        message: 'Apenas platform_admin com console habilitado pode iniciar acesso assistido.',
      });
      return;
    }

    if (actorUid === targetUid) {
      response.status(400).json({
        error: 'self_impersonation_not_allowed',
        message: 'Nao e permitido criar acesso assistido para a propria conta.',
      });
      return;
    }

    const targetUserDoc = await firestore.collection('usuarios').doc(targetUid).get();
    if (!targetUserDoc.exists) {
      response.status(404).json({
        error: 'target_not_found',
        message: 'Usuario alvo nao encontrado.',
      });
      return;
    }

    const targetUserData = targetUserDoc.data() || {};
    const targetActiveGlobal = targetUserData.ativoGlobal !== false;
    if (!targetActiveGlobal) {
      response.status(400).json({
        error: 'target_inactive',
        message: 'Nao e permitido acesso assistido para conta alvo inativa.',
      });
      return;
    }

    const targetMembershipDoc = await firestore
      .collection('tenant_memberships')
      .doc(targetMembershipId)
      .get();

    if (!targetMembershipDoc.exists) {
      response.status(404).json({
        error: 'membership_not_found',
        message: 'Membership alvo nao encontrado.',
      });
      return;
    }

    const targetMembershipData = targetMembershipDoc.data() || {};
    const membershipUid = String(targetMembershipData.uid ?? '').trim();
    const membershipTenantId = String(targetMembershipData.tenantId ?? '').trim();
    const membershipActive = targetMembershipData.ativo === true;
    const membershipState = String(targetMembershipData.state ?? 'active')
      .trim()
      .toLowerCase();

    if (
      membershipUid !== targetUid ||
      membershipTenantId !== targetTenantId ||
      !membershipActive ||
      membershipState !== 'active'
    ) {
      response.status(400).json({
        error: 'invalid_membership_target',
        message: 'Membership alvo invalido para o usuario/tenant informado.',
      });
      return;
    }

    const sessionRef = firestore.collection('platform_impersonation_sessions').doc();
    const sessionId = sessionRef.id;
    const sessionKey = crypto.randomBytes(24).toString('hex');
    const sessionKeyHash = sha256Hex(sessionKey);
    const nowDate = new Date();
    const expiresAtDate = new Date(
      nowDate.getTime() + durationMinutes * 60 * 1000,
    );

    const actorEmail = String(
      actorUserData.email ?? authContext.email ?? '',
    ).trim();
    const actorLabel = resolveUserDisplayLabel(actorUserData, actorEmail, actorUid);
    const targetEmail = String(targetUserData.email ?? '').trim();
    const targetLabel = resolveUserDisplayLabel(targetUserData, targetEmail, targetUid);

    await sessionRef.set({
      sessionId,
      status: 'issued',
      actorUid,
      actorEmail,
      actorLabel,
      targetUid,
      targetTenantId,
      targetMembershipId,
      targetEmail,
      targetDisplayName: targetLabel,
      reason,
      durationMinutes,
      sessionKeyHash,
      createdAt: admin.firestore.Timestamp.fromDate(nowDate),
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAtDate),
      consumedAt: null,
      consumedByIp: '',
      consumedUserAgent: '',
      revokedAt: null,
      revokedByUid: '',
      revokedReason: '',
    });

    await firestore.collection('platform_admin_audit').add({
      action: 'impersonation_session_started',
      actorUid,
      actorEmail,
      actorLabel,
      targetUid,
      targetEmail,
      targetDisplayName: targetLabel,
      details: {
        targetTenantId,
        targetMembershipId,
        reason,
        durationMinutes,
        sessionId,
      },
      createdAt: admin.firestore.Timestamp.fromDate(nowDate),
    });

    const normalizedOrigin = normalizeLaunchOrigin(launchOrigin, request);
    const launchQuery =
      `impersonationSession=${encodeURIComponent(sessionId)}` +
      `&impersonationKey=${encodeURIComponent(sessionKey)}` +
      `&impersonationTenantId=${encodeURIComponent(targetTenantId)}` +
      `&impersonationMembershipId=${encodeURIComponent(targetMembershipId)}` +
      `&mode=web`;
    const launchUrl = normalizedOrigin
      ? `${normalizedOrigin}/?${launchQuery}`
      : `/?${launchQuery}`;

    let adminRestoreCustomToken = '';
    try {
      adminRestoreCustomToken = await admin.auth().createCustomToken(actorUid, {
        maintainerRestore: true,
        impersonationSessionId: sessionId,
      });
    } catch (error) {
      console.error(
        'createImpersonationSession admin restore token failed',
        error,
      );
    }

    response.status(200).json({
      success: true,
      sessionId,
      sessionKey,
      adminRestoreCustomToken,
      launchUrl,
      targetUid,
      targetTenantId,
      targetMembershipId,
      expiresAt: expiresAtDate.toISOString(),
    });
  },
);

exports.createStripeCheckoutSession = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 60,
    secrets: STRIPE_RUNTIME_SECRETS,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const tenantId = String(request.body?.tenantId ?? '').trim();
    const billingPlanKey = normalizeBillingPlanKey(request.body?.billingPlanKey);
    const successUrl = String(request.body?.successUrl ?? '').trim();
    const cancelUrl = String(request.body?.cancelUrl ?? '').trim();

    if (!tenantId || !billingPlanKey || !successUrl || !cancelUrl) {
      response.status(400).json({
        error: 'invalid_payload',
        message:
          'tenantId, billingPlanKey, successUrl e cancelUrl sao obrigatorios.',
      });
      return;
    }

    if (!isValidHttpAbsoluteUrl(successUrl) || !isValidHttpAbsoluteUrl(cancelUrl)) {
      response.status(400).json({
        error: 'invalid_redirect_url',
        message: 'successUrl e cancelUrl devem ser URLs HTTP(S) absolutas.',
      });
      return;
    }

    const firestore = admin.firestore();
    const authContext = await verifyFirebaseAuthFromRequest(request);
    if (!authContext.ok) {
      response.status(authContext.status).json({
        error: authContext.error,
        message: authContext.message,
      });
      return;
    }

    const actorPermission = await assertTenantBillingActorPermission({
      firestore,
      uid: authContext.uid,
      tenantId,
    });
    if (!actorPermission.allowed) {
      response.status(actorPermission.status).json({
        error: actorPermission.error,
        message: actorPermission.message,
      });
      return;
    }

    const integrationReady = await loadStripeIntegrationRuntime({
      firestore,
      requireWebhookSecret: false,
    });
    if (!integrationReady.ok) {
      response.status(integrationReady.status).json({
        error: integrationReady.error,
        message: integrationReady.message,
      });
      return;
    }

    const tenantRef = firestore.collection('tenants').doc(tenantId);
    const tenantDoc = await tenantRef.get();
    if (!tenantDoc.exists) {
      response.status(404).json({
        error: 'tenant_not_found',
        message: 'Tenant nao encontrado.',
      });
      return;
    }

    const mapping = await loadStripePlanMapping({
      firestore,
      billingPlanKey,
    });
    if (!mapping) {
      response.status(404).json({
        error: 'plan_mapping_not_found',
        message: 'Nao existe mapeamento ativo para billingPlanKey informado.',
      });
      return;
    }

    const tenantData = tenantDoc.data() || {};
    const existingCustomerId = String(tenantData.stripeCustomerId ?? '').trim();
    const stripeClient = integrationReady.stripeClient;
    let stripeCustomerId = existingCustomerId;
    if (!stripeCustomerId) {
      const ownerEmail = String(authContext.email ?? '').trim();
      const customer = await stripeClient.customers.create({
        email: ownerEmail || undefined,
        name: String(
          tenantData.razaoSocial ?? tenantData.nomeFantasia ?? tenantId,
        ).trim(),
        metadata: {
          tenantId,
          billingPlanKey,
          source: 'smartsfa',
        },
      });
      stripeCustomerId = String(customer.id ?? '').trim();
    }

    const session = await stripeClient.checkout.sessions.create({
      mode: 'subscription',
      customer: stripeCustomerId,
      client_reference_id: tenantId,
      success_url: successUrl,
      cancel_url: cancelUrl,
      line_items: [
        {
          price: mapping.stripePriceId,
          quantity: 1,
        },
      ],
      metadata: {
        tenantId,
        billingPlanKey,
        initiatedByUid: authContext.uid,
        source: 'smartsfa_web_portal',
      },
      subscription_data: {
        metadata: {
          tenantId,
          billingPlanKey,
          initiatedByUid: authContext.uid,
        },
      },
      allow_promotion_codes: true,
    });

    await tenantRef.set(
      {
        stripeCustomerId,
        stripeCheckoutSessionId: String(session.id ?? '').trim(),
        billingPlanKey,
        billingUpdatedAt: new Date().toISOString(),
      },
      { merge: true },
    );

    response.status(200).json({
      checkoutUrl: String(session.url ?? '').trim(),
      checkoutSessionId: String(session.id ?? '').trim(),
      stripeCustomerId,
      activeEnvironment: integrationReady.environment,
    });
  },
);

exports.createStripePortalSession = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 45,
    secrets: STRIPE_RUNTIME_SECRETS,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const tenantId = String(request.body?.tenantId ?? '').trim();
    const returnUrl = String(request.body?.returnUrl ?? '').trim();

    if (!tenantId || !returnUrl) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'tenantId e returnUrl sao obrigatorios.',
      });
      return;
    }

    if (!isValidHttpAbsoluteUrl(returnUrl)) {
      response.status(400).json({
        error: 'invalid_return_url',
        message: 'returnUrl deve ser URL HTTP(S) absoluta.',
      });
      return;
    }

    const firestore = admin.firestore();
    const authContext = await verifyFirebaseAuthFromRequest(request);
    if (!authContext.ok) {
      response.status(authContext.status).json({
        error: authContext.error,
        message: authContext.message,
      });
      return;
    }

    const actorPermission = await assertTenantBillingActorPermission({
      firestore,
      uid: authContext.uid,
      tenantId,
    });
    if (!actorPermission.allowed) {
      response.status(actorPermission.status).json({
        error: actorPermission.error,
        message: actorPermission.message,
      });
      return;
    }

    const integrationReady = await loadStripeIntegrationRuntime({
      firestore,
      requireWebhookSecret: false,
    });
    if (!integrationReady.ok) {
      response.status(integrationReady.status).json({
        error: integrationReady.error,
        message: integrationReady.message,
      });
      return;
    }

    const tenantDoc = await firestore.collection('tenants').doc(tenantId).get();
    if (!tenantDoc.exists) {
      response.status(404).json({
        error: 'tenant_not_found',
        message: 'Tenant nao encontrado.',
      });
      return;
    }

    const tenantData = tenantDoc.data() || {};
    const stripeCustomerId = String(tenantData.stripeCustomerId ?? '').trim();
    if (!stripeCustomerId) {
      response.status(404).json({
        error: 'stripe_customer_missing',
        message: 'Tenant ainda nao possui stripeCustomerId.',
      });
      return;
    }

    const portalSession = await integrationReady.stripeClient.billingPortal.sessions.create({
      customer: stripeCustomerId,
      return_url: returnUrl,
    });

    response.status(200).json({
      portalUrl: String(portalSession.url ?? '').trim(),
      activeEnvironment: integrationReady.environment,
    });
  },
);

exports.handleStripeWebhook = onRequest(
  {
    cors: false,
    region: 'us-central1',
    timeoutSeconds: 120,
    secrets: STRIPE_RUNTIME_SECRETS,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const firestore = admin.firestore();
    const integrationReady = await loadStripeIntegrationRuntime({
      firestore,
      requireWebhookSecret: true,
    });
    if (!integrationReady.ok) {
      response.status(integrationReady.status).json({
        error: integrationReady.error,
        message: integrationReady.message,
      });
      return;
    }

    const signatureHeader = String(
      request.headers['stripe-signature'] ?? '',
    ).trim();
    if (!signatureHeader) {
      response.status(400).json({
        error: 'missing_signature',
        message: 'Header stripe-signature ausente.',
      });
      return;
    }

    let event;
    try {
      const rawBody =
        request.rawBody ?? Buffer.from(JSON.stringify(request.body ?? {}));
      event = integrationReady.stripeClient.webhooks.constructEvent(
        rawBody,
        signatureHeader,
        integrationReady.webhookSecret,
      );
    } catch (error) {
      response.status(400).json({
        error: 'invalid_webhook_signature',
        message: error instanceof Error ? error.message : String(error),
      });
      return;
    }

    try {
      const processing = await processStripeWebhookEvent({
        firestore,
        event,
        enabledEvents: integrationReady.enabledEvents,
      });

      response.status(200).json({
        received: true,
        ignored: processing.ignored,
        duplicate: processing.duplicate,
        tenantId: processing.tenantId,
      });
    } catch (error) {
      response.status(500).json({
        error: 'webhook_processing_failed',
        message: error instanceof Error ? error.message : String(error),
      });
    }
  },
);

exports.reconcileStripeTenant = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 90,
    secrets: STRIPE_RUNTIME_SECRETS,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const tenantId = String(request.body?.tenantId ?? '').trim();
    const reason = String(request.body?.reason ?? '').trim();
    if (!tenantId) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'tenantId e obrigatorio.',
      });
      return;
    }

    const firestore = admin.firestore();
    const authContext = await verifyFirebaseAuthFromRequest(request);
    if (!authContext.ok) {
      response.status(authContext.status).json({
        error: authContext.error,
        message: authContext.message,
      });
      return;
    }

    const platformAccess = await assertPlatformAdminActor({
      firestore,
      uid: authContext.uid,
    });
    if (!platformAccess.allowed) {
      response.status(platformAccess.status).json({
        error: platformAccess.error,
        message: platformAccess.message,
      });
      return;
    }

    const integrationReady = await loadStripeIntegrationRuntime({
      firestore,
      requireWebhookSecret: false,
    });
    if (!integrationReady.ok) {
      response.status(integrationReady.status).json({
        error: integrationReady.error,
        message: integrationReady.message,
      });
      return;
    }

    try {
      const result = await reconcileTenantStripeState({
        firestore,
        stripeClient: integrationReady.stripeClient,
        tenantId,
      });

      await firestore.collection('platform_admin_audit').add({
        action: 'billing_state_updated',
        actorUid: authContext.uid,
        actorEmail: authContext.email,
        actorLabel: authContext.email || authContext.uid,
        targetUid: authContext.uid,
        targetEmail: authContext.email,
        targetDisplayName: authContext.email || authContext.uid,
        details: {
          tenantId,
          reason,
          previousBillingStatus: result.previousBillingStatus,
          currentBillingStatus: result.currentBillingStatus,
          source: 'stripe_reconcile_tenant',
        },
        createdAt: admin.firestore.Timestamp.fromDate(new Date()),
      });

      response.status(200).json({
        tenantId,
        stripeSubscriptionId: result.stripeSubscriptionId,
        previousBillingStatus: result.previousBillingStatus,
        currentBillingStatus: result.currentBillingStatus,
        updatedAt: result.updatedAt,
      });
    } catch (error) {
      response.status(500).json({
        error: 'reconcile_tenant_failed',
        message: error instanceof Error ? error.message : String(error),
      });
    }
  },
);

exports.reconcileAllStripeTenants = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 540,
    secrets: STRIPE_RUNTIME_SECRETS,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const dryRun = request.body?.dryRun === true;
    const limitInput = Number(request.body?.limit ?? STRIPE_SYNC_BATCH_LIMIT);
    const limit = Number.isFinite(limitInput)
      ? Math.max(1, Math.min(500, Math.floor(limitInput)))
      : STRIPE_SYNC_BATCH_LIMIT;

    const firestore = admin.firestore();
    const authContext = await verifyFirebaseAuthFromRequest(request);
    if (!authContext.ok) {
      response.status(authContext.status).json({
        error: authContext.error,
        message: authContext.message,
      });
      return;
    }

    const platformAccess = await assertPlatformAdminActor({
      firestore,
      uid: authContext.uid,
    });
    if (!platformAccess.allowed) {
      response.status(platformAccess.status).json({
        error: platformAccess.error,
        message: platformAccess.message,
      });
      return;
    }

    const integrationReady = await loadStripeIntegrationRuntime({
      firestore,
      requireWebhookSecret: false,
    });
    if (!integrationReady.ok) {
      response.status(integrationReady.status).json({
        error: integrationReady.error,
        message: integrationReady.message,
      });
      return;
    }

    const tenantDocs = await firestore.collection('tenants').limit(limit).get();
    const candidates = tenantDocs.docs.filter((doc) => {
      const data = doc.data() || {};
      return (
        String(data.stripeCustomerId ?? '').trim() ||
        String(data.stripeSubscriptionId ?? '').trim()
      );
    });

    let totalUpdated = 0;
    let totalFailed = 0;
    const failures = [];
    for (const doc of candidates) {
      const tenantId = doc.id;
      try {
        if (!dryRun) {
          await reconcileTenantStripeState({
            firestore,
            stripeClient: integrationReady.stripeClient,
            tenantId,
          });
        }
        totalUpdated += 1;
      } catch (error) {
        totalFailed += 1;
        failures.push({
          tenantId,
          message: error instanceof Error ? error.message : String(error),
        });
      }
    }

    response.status(200).json({
      totalProcessed: candidates.length,
      totalUpdated,
      totalFailed,
      dryRun,
      failures,
    });
  },
);

exports.manageTenantBillingState = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 90,
    secrets: STRIPE_RUNTIME_SECRETS,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const tenantId = String(request.body?.tenantId ?? '').trim();
    const action = String(request.body?.action ?? '').trim().toLowerCase();
    const reason = String(request.body?.reason ?? '').trim().slice(0, 240);

    if (!tenantId) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'tenantId e obrigatorio.',
      });
      return;
    }

    const supportedActions = new Set([
      'grant_7_days',
      'grant_30_days',
      'normalize_billing',
      'suspend_billing',
    ]);
    if (!supportedActions.has(action)) {
      response.status(400).json({
        error: 'invalid_action',
        message:
          'Acao invalida. Use grant_7_days, grant_30_days, normalize_billing ou suspend_billing.',
      });
      return;
    }

    const firestore = admin.firestore();
    const authContext = await verifyFirebaseAuthFromRequest(request);
    if (!authContext.ok) {
      response.status(authContext.status).json({
        error: authContext.error,
        message: authContext.message,
      });
      return;
    }

    const platformAccess = await assertPlatformAdminActor({
      firestore,
      uid: authContext.uid,
    });
    if (!platformAccess.allowed) {
      response.status(platformAccess.status).json({
        error: platformAccess.error,
        message: platformAccess.message,
      });
      return;
    }

    const tenantRef = firestore.collection('tenants').doc(tenantId);
    const tenantDoc = await tenantRef.get();
    if (!tenantDoc.exists) {
      response.status(404).json({
        error: 'tenant_not_found',
        message: 'Tenant nao encontrado.',
      });
      return;
    }

    const tenantData = tenantDoc.data() || {};
    const nowDate = new Date();
    const nowIso = nowDate.toISOString();
    const previousBillingStatus = String(tenantData.billingStatus ?? '').trim();

    const patch = {
      billingUpdatedAt: nowIso,
      billingAccountState: '',
      billingStatus: '',
      billingGraceUntilAt: '',
      billingSuspendedAt: '',
      billingPastDueSinceAt: '',
      billingLastManualAction: action,
      billingLastManualReason: reason,
      billingLastManualActorUid: authContext.uid,
      billingLastManualActorEmail: authContext.email,
      billingLastManualAt: nowIso,
    };

    let auditAction = 'billing_state_updated';
    if (action === 'grant_7_days' || action === 'grant_30_days') {
      const graceDays = action === 'grant_30_days' ? 30 : 7;
      const graceUntil = new Date(
        nowDate.getTime() + graceDays * 24 * 60 * 60 * 1000,
      ).toISOString();
      patch.billingStatus = 'grace';
      patch.billingAccountState = 'grace';
      patch.billingGraceUntilAt = graceUntil;
      auditAction = 'billing_grace_set';
    } else if (action === 'normalize_billing') {
      patch.billingStatus = 'active';
      patch.billingAccountState = 'active';
      auditAction = 'billing_normalized';
    } else if (action === 'suspend_billing') {
      patch.billingStatus = 'suspended';
      patch.billingAccountState = 'suspended';
      patch.billingSuspendedAt = nowIso;
      auditAction = 'billing_suspended';
    }

    let stripeApplied = false;
    let stripeAction = 'not_attempted';
    let stripeMessage = '';

    const integrationReady = await loadStripeIntegrationRuntime({
      firestore,
      requireWebhookSecret: false,
    });
    if (integrationReady.ok) {
      try {
        const reflection = await applyTenantBillingActionToStripe({
          stripeClient: integrationReady.stripeClient,
          tenantId,
          tenantData,
          action,
          reason,
          actorUid: authContext.uid,
        });
        stripeApplied = reflection.applied;
        stripeAction = reflection.action;
        stripeMessage = reflection.message;
      } catch (error) {
        response.status(502).json({
          error: 'stripe_action_failed',
          message: error instanceof Error ? error.message : String(error),
        });
        return;
      }
    } else {
      stripeAction = 'integration_not_ready';
      stripeMessage = integrationReady.message;
    }

    await tenantRef.set(patch, { merge: true });

    await firestore.collection('platform_admin_audit').add({
      action: auditAction,
      actorUid: authContext.uid,
      actorEmail: authContext.email,
      actorLabel: authContext.email || authContext.uid,
      targetUid: authContext.uid,
      targetEmail: authContext.email,
      targetDisplayName: authContext.email || authContext.uid,
      details: {
        tenantId,
        requestedAction: action,
        reason,
        previousBillingStatus,
        currentBillingStatus: patch.billingStatus,
        currentBillingAccountState: patch.billingAccountState,
        billingGraceUntilAt: patch.billingGraceUntilAt,
        billingSuspendedAt: patch.billingSuspendedAt,
        stripeApplied,
        stripeAction,
        stripeMessage,
      },
      createdAt: admin.firestore.Timestamp.fromDate(nowDate),
    });

    response.status(200).json({
      tenantId,
      previousBillingStatus,
      currentBillingStatus: patch.billingStatus,
      billingStatus: patch.billingStatus,
      billingGraceUntilAt: patch.billingGraceUntilAt,
      billingSuspendedAt: patch.billingSuspendedAt,
      updatedAt: patch.billingUpdatedAt,
      stripeApplied,
      stripeAction,
      stripeMessage,
    });
  },
);

exports.listStripeCatalog = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 90,
    secrets: STRIPE_RUNTIME_SECRETS,
  },
  async (request, response) => {
    if (request.method !== 'POST' && request.method !== 'GET') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const payload = request.method === 'GET' ? request.query : request.body;
    const limitProductsInput = Number(payload?.limitProducts ?? 30);
    const limitPricesInput = Number(payload?.limitPricesPerProduct ?? 20);
    const activeOnly = payload?.activeOnly !== false;

    const limitProducts = Number.isFinite(limitProductsInput)
      ? Math.max(1, Math.min(100, Math.floor(limitProductsInput)))
      : 30;
    const limitPricesPerProduct = Number.isFinite(limitPricesInput)
      ? Math.max(1, Math.min(100, Math.floor(limitPricesInput)))
      : 20;

    const firestore = admin.firestore();
    const authContext = await verifyFirebaseAuthFromRequest(request);
    if (!authContext.ok) {
      response.status(authContext.status).json({
        error: authContext.error,
        message: authContext.message,
      });
      return;
    }

    const platformAccess = await assertPlatformAdminActor({
      firestore,
      uid: authContext.uid,
    });
    if (!platformAccess.allowed) {
      response.status(platformAccess.status).json({
        error: platformAccess.error,
        message: platformAccess.message,
      });
      return;
    }

    const integrationReady = await loadStripeIntegrationRuntime({
      firestore,
      requireWebhookSecret: false,
    });
    if (!integrationReady.ok) {
      response.status(integrationReady.status).json({
        error: integrationReady.error,
        message: integrationReady.message,
      });
      return;
    }

    try {
      const stripeClient = integrationReady.stripeClient;
      const stripeAccount = await stripeClient.accounts.retrieve();

      const products = await stripeClient.products.list({
        active: activeOnly ? true : undefined,
        limit: limitProducts,
      });

      const items = [];
      for (const product of products.data) {
        const prices = await stripeClient.prices.list({
          product: product.id,
          active: activeOnly ? true : undefined,
          limit: limitPricesPerProduct,
        });

        items.push({
          productId: String(product.id ?? '').trim(),
          productName: String(product.name ?? '').trim(),
          productDescription: String(product.description ?? '').trim(),
          active: product.active === true,
          defaultPriceId:
            typeof product.default_price === 'string'
              ? String(product.default_price).trim()
              : String(product.default_price?.id ?? '').trim(),
          prices: prices.data.map((price) => ({
            priceId: String(price.id ?? '').trim(),
            lookupKey: String(price.lookup_key ?? '').trim(),
            nickname: String(price.nickname ?? '').trim(),
            active: price.active === true,
            currency: String(price.currency ?? '').trim(),
            type: String(price.type ?? '').trim(),
            recurringInterval: String(price.recurring?.interval ?? '').trim(),
            recurringIntervalCount: Number(price.recurring?.interval_count ?? 0),
            unitAmount: Number(price.unit_amount ?? 0),
            unitAmountDecimal: String(price.unit_amount_decimal ?? '').trim(),
            taxBehavior: String(price.tax_behavior ?? '').trim(),
          })),
        });
      }

      response.status(200).json({
        activeEnvironment: integrationReady.environment,
        stripeAccountId: String(stripeAccount.id ?? '').trim(),
        totalProducts: items.length,
        hasMoreProducts: products.has_more === true,
        products: items,
      });
    } catch (error) {
      response.status(500).json({
        error: 'stripe_catalog_list_failed',
        message: error instanceof Error ? error.message : String(error),
      });
    }
  },
);

exports.createStripeCatalogPlan = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 90,
    secrets: STRIPE_RUNTIME_SECRETS,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const payload = request.body || {};
    const productName = String(payload.productName ?? '').trim();
    const productDescription = String(payload.productDescription ?? '').trim();
    const billingPlanKey = normalizeBillingPlanKey(payload.billingPlanKey);
    const currency = String(payload.currency ?? 'brl').trim().toLowerCase();
    const recurringInterval = String(payload.recurringInterval ?? 'month')
      .trim()
      .toLowerCase();
    const recurringIntervalCountInput = Number(payload.recurringIntervalCount ?? 1);
    const amountMinorUnitsInput = Number(payload.amountMinorUnits ?? 0);
    const priceNickname = String(payload.priceNickname ?? '').trim();
    const lookupKey = String(payload.lookupKey ?? '').trim();
    const taxBehavior = String(payload.taxBehavior ?? '').trim().toLowerCase();
    const active = payload.active !== false;

    const amountMinorUnits = Number.isFinite(amountMinorUnitsInput)
      ? Math.floor(amountMinorUnitsInput)
      : 0;
    const recurringIntervalCount = Number.isFinite(recurringIntervalCountInput)
      ? Math.max(1, Math.min(36, Math.floor(recurringIntervalCountInput)))
      : 1;
    const recommendedLookupKey = buildStripeRecommendedLookupKey({
      billingPlanKey,
      currency,
      recurringInterval,
      recurringIntervalCount,
    });
    const effectiveLookupKey = lookupKey || recommendedLookupKey;

    if (!productName) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'productName e obrigatorio.',
      });
      return;
    }

    if (!billingPlanKey) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'billingPlanKey e obrigatorio.',
      });
      return;
    }

    if (!Number.isInteger(amountMinorUnits) || amountMinorUnits <= 0) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'amountMinorUnits deve ser inteiro positivo.',
      });
      return;
    }

    if (!/^[a-z]{3}$/.test(currency)) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'currency deve seguir ISO 4217 em 3 letras (ex.: brl, usd).',
      });
      return;
    }

    if (!['day', 'week', 'month', 'year'].includes(recurringInterval)) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'recurringInterval invalido. Use day, week, month ou year.',
      });
      return;
    }

    const firestore = admin.firestore();
    const authContext = await verifyFirebaseAuthFromRequest(request);
    if (!authContext.ok) {
      response.status(authContext.status).json({
        error: authContext.error,
        message: authContext.message,
      });
      return;
    }

    const platformAccess = await assertPlatformAdminActor({
      firestore,
      uid: authContext.uid,
    });
    if (!platformAccess.allowed) {
      response.status(platformAccess.status).json({
        error: platformAccess.error,
        message: platformAccess.message,
      });
      return;
    }

    const integrationReady = await loadStripeIntegrationRuntime({
      firestore,
      requireWebhookSecret: false,
    });
    if (!integrationReady.ok) {
      response.status(integrationReady.status).json({
        error: integrationReady.error,
        message: integrationReady.message,
      });
      return;
    }

    try {
      const stripeClient = integrationReady.stripeClient;
      const stripeAccount = await stripeClient.accounts.retrieve();

      const metadata = buildStripeCatalogPlanMetadata({
        billingPlanKey,
        amountMinorUnits,
        currency,
        recurringInterval,
        recurringIntervalCount,
        lookupKey: effectiveLookupKey,
        actorUid: authContext.uid,
        actorEmail: authContext.email,
      });

      const product = await stripeClient.products.create({
        name: productName,
        description: productDescription || undefined,
        active,
        metadata,
      });

      const pricePayload = {
        product: String(product.id ?? '').trim(),
        currency,
        unit_amount: amountMinorUnits,
        recurring: {
          interval: recurringInterval,
          interval_count: recurringIntervalCount,
        },
        nickname: priceNickname || undefined,
        lookup_key: effectiveLookupKey || undefined,
        active,
        metadata,
      };

      if (['inclusive', 'exclusive', 'unspecified'].includes(taxBehavior)) {
        pricePayload.tax_behavior = taxBehavior;
      }

      const price = await stripeClient.prices.create(pricePayload);

      await firestore.collection('platform_admin_audit').add({
        action: 'stripe_catalog_plan_created',
        actorUid: authContext.uid,
        actorEmail: authContext.email,
        actorLabel: authContext.email || authContext.uid,
        targetUid: authContext.uid,
        targetEmail: authContext.email,
        targetDisplayName: authContext.email || authContext.uid,
        details: {
          billingPlanKey,
          activeEnvironment: integrationReady.environment,
          stripeAccountId: String(stripeAccount.id ?? '').trim(),
          productId: String(product.id ?? '').trim(),
          priceId: String(price.id ?? '').trim(),
          amountMinorUnits,
          currency,
          recurringInterval,
          recurringIntervalCount,
        },
        createdAt: admin.firestore.Timestamp.fromDate(new Date()),
      });

      response.status(200).json({
        activeEnvironment: integrationReady.environment,
        stripeAccountId: String(stripeAccount.id ?? '').trim(),
        productId: String(product.id ?? '').trim(),
        productName: String(product.name ?? '').trim(),
        productDescription: String(product.description ?? '').trim(),
        priceId: String(price.id ?? '').trim(),
        priceNickname: String(price.nickname ?? '').trim(),
        lookupKey:
          String(price.lookup_key ?? '').trim() || effectiveLookupKey,
        currency: String(price.currency ?? '').trim(),
        unitAmount: Number(price.unit_amount ?? 0),
        recurringInterval: String(price.recurring?.interval ?? '').trim(),
        recurringIntervalCount: Number(price.recurring?.interval_count ?? 0),
        billingPlanKey,
      });
    } catch (error) {
      const statusCode = Number(error?.statusCode ?? 500);
      const safeStatus = statusCode >= 400 && statusCode < 600 ? statusCode : 500;
      const message =
        String(error?.raw?.message ?? '').trim() ||
        (error instanceof Error ? error.message : String(error));

      response.status(safeStatus).json({
        error: 'stripe_catalog_create_plan_failed',
        message: message || 'Falha ao criar Product/Price no Stripe.',
      });
    }
  },
);

exports.listStripeCheckoutPlans = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 45,
  },
  async (request, response) => {
    if (request.method !== 'POST' && request.method !== 'GET') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const payload = request.method === 'GET' ? request.query : request.body;
    const tenantId = String(payload?.tenantId ?? '').trim();
    if (!tenantId) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'tenantId e obrigatorio.',
      });
      return;
    }

    const firestore = admin.firestore();
    const authContext = await verifyFirebaseAuthFromRequest(request);
    if (!authContext.ok) {
      response.status(authContext.status).json({
        error: authContext.error,
        message: authContext.message,
      });
      return;
    }

    const actorPermission = await assertTenantBillingActorPermission({
      firestore,
      uid: authContext.uid,
      tenantId,
    });
    if (!actorPermission.allowed) {
      response.status(actorPermission.status).json({
        error: actorPermission.error,
        message: actorPermission.message,
      });
      return;
    }

    const tenantDoc = await firestore.collection('tenants').doc(tenantId).get();
    if (!tenantDoc.exists) {
      response.status(404).json({
        error: 'tenant_not_found',
        message: 'Tenant nao encontrado.',
      });
      return;
    }

    const tenantData = tenantDoc.data() || {};
    const workspaceType = String(tenantData.workspaceType ?? '')
      .trim()
      .toLowerCase();
    const requiredPrefix = resolveStripePlanPrefixByWorkspaceType(workspaceType);

    const snapshot = await firestore
      .collection('billing_integrations')
      .doc('stripe')
      .collection('plan_mappings')
      .where('active', '==', true)
      .where('mappingType', '==', 'base')
      .limit(200)
      .get();

    const plans = [];
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const billingPlanKey = normalizeBillingPlanKey(data.billingPlanKey ?? doc.id);
      const stripePriceId = String(data.stripePriceId ?? '').trim();
      if (!billingPlanKey || !stripePriceId) {
        continue;
      }

      if (requiredPrefix && !billingPlanKey.startsWith(`${requiredPrefix}_`)) {
        continue;
      }

      const planDisplayName =
        String(data.planDisplayName ?? '').trim() ||
        String(data.stripeProductName ?? '').trim() ||
        String(data.stripePriceNickname ?? '').trim() ||
        billingPlanKey;

      const planDisplayAmount =
        String(data.planDisplayAmount ?? '').trim() ||
        formatPlanAmountLabel({
          amountMinorUnits: Number(data.stripeUnitAmount ?? 0),
          currency: String(data.stripeCurrency ?? '').trim(),
          recurringInterval: String(data.stripeRecurringInterval ?? '').trim(),
          recurringIntervalCount: Number(data.stripeRecurringIntervalCount ?? 0),
        });

      plans.push({
        mappingId: doc.id,
        billingPlanKey,
        planDisplayName,
        planDisplayAmount,
        stripePriceId,
        stripeProductId: String(data.stripeProductId ?? '').trim(),
        stripeProductName: String(data.stripeProductName ?? '').trim(),
      });
    }

    plans.sort((a, b) => {
      const byName = String(a.planDisplayName ?? '').localeCompare(
        String(b.planDisplayName ?? ''),
        'pt-BR',
      );
      if (byName !== 0) {
        return byName;
      }
      return String(a.billingPlanKey ?? '').localeCompare(
        String(b.billingPlanKey ?? ''),
      );
    });

    response.status(200).json({
      tenantId,
      workspaceType,
      requiredPrefix,
      plans,
    });
  },
);

exports.consumeImpersonationSession = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 60,
    serviceAccount: 'smart-sfa@appspot.gserviceaccount.com',
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const sessionId = String(request.body?.sessionId ?? '').trim();
    const sessionKey = String(request.body?.sessionKey ?? '').trim();
    if (!sessionId || !sessionKey) {
      response.status(400).json({
        error: 'missing_session_data',
        message: 'sessionId e sessionKey sao obrigatorios.',
      });
      return;
    }

    const firestore = admin.firestore();
    const sessionRef = firestore.collection('platform_impersonation_sessions').doc(sessionId);
    const requestIp = resolveRequestIp(request);
    const userAgent = String(request.headers['user-agent'] ?? '').trim().slice(0, 300);
    const sessionKeyHash = sha256Hex(sessionKey);
    const nowDate = new Date();

    let sessionData = null;
    try {
      await firestore.runTransaction(async (tx) => {
        const sessionDoc = await tx.get(sessionRef);
        if (!sessionDoc.exists) {
          throw new Error('session_not_found');
        }

        const data = sessionDoc.data() || {};
        assertImpersonationSessionConsumable({
          data,
          sessionKeyHash,
          nowDate,
        });
        sessionData = data;
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : String(error);
      const responseMap = mapImpersonationConsumeError(code);
      response.status(responseMap.status).json({
        error: responseMap.error,
        message: responseMap.message,
      });
      return;
    }

    const actorUid = String(sessionData?.actorUid ?? '').trim();
    const actorEmail = String(sessionData?.actorEmail ?? '').trim();
    const actorLabel = String(sessionData?.actorLabel ?? '').trim();
    const targetUid = String(sessionData?.targetUid ?? '').trim();
    const targetTenantId = String(sessionData?.targetTenantId ?? '').trim();
    const targetMembershipId = String(sessionData?.targetMembershipId ?? '').trim();
    const targetEmail = String(sessionData?.targetEmail ?? '').trim();
    const targetDisplayName = String(sessionData?.targetDisplayName ?? '').trim();
    const reason = String(sessionData?.reason ?? '').trim();
    const expiresAtTimestamp = sessionData?.expiresAt;
    const expiresAtDate =
      expiresAtTimestamp && typeof expiresAtTimestamp.toDate === 'function'
        ? expiresAtTimestamp.toDate()
        : null;

    if (!targetUid) {
      response.status(400).json({
        error: 'invalid_target_uid',
        message: 'Sessao de impersonation sem usuario alvo valido.',
      });
      return;
    }

    const targetUserDoc = await firestore.collection('usuarios').doc(targetUid).get();
    if (!targetUserDoc.exists) {
      response.status(404).json({
        error: 'target_not_found',
        message: 'Usuario alvo nao encontrado para consumo da sessao.',
      });
      return;
    }

    const targetUserData = targetUserDoc.data() || {};
    if (targetUserData.ativoGlobal === false) {
      response.status(400).json({
        error: 'target_inactive',
        message: 'Conta alvo inativa para acesso assistido.',
      });
      return;
    }

    let customToken = '';
    try {
      customToken = await admin.auth().createCustomToken(targetUid, {
        impersonation: true,
        impersonatedByUid: actorUid,
        impersonationSessionId: sessionId,
        impersonationTenantId: targetTenantId,
        impersonationMembershipId: targetMembershipId,
      });
    } catch (error) {
      console.error(
        'consumeImpersonationSession createCustomToken failed',
        error,
      );
      response.status(500).json({
        error: 'custom_token_generation_failed',
        message:
          'Falha interna ao preparar autenticacao da sessao assistida. Tente novamente.',
      });
      return;
    }

    const consumedAtDate = new Date();
    try {
      await firestore.runTransaction(async (tx) => {
        const sessionDoc = await tx.get(sessionRef);
        if (!sessionDoc.exists) {
          throw new Error('session_not_found');
        }

        const data = sessionDoc.data() || {};
        assertImpersonationSessionConsumable({
          data,
          sessionKeyHash,
          nowDate: consumedAtDate,
        });

        tx.update(sessionRef, {
          status: 'consumed',
          consumedAt: admin.firestore.Timestamp.fromDate(consumedAtDate),
          consumedByIp: requestIp,
          consumedUserAgent: userAgent,
        });
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : String(error);
      const responseMap = mapImpersonationConsumeError(code);
      response.status(responseMap.status).json({
        error: responseMap.error,
        message: responseMap.message,
      });
      return;
    }

    try {
      await firestore.collection('platform_admin_audit').add({
        action: 'impersonation_session_consumed',
        actorUid,
        actorEmail,
        actorLabel,
        targetUid,
        targetEmail,
        targetDisplayName,
        details: {
          targetTenantId,
          targetMembershipId,
          reason,
          sessionId,
          consumedByIp: requestIp,
        },
        createdAt: admin.firestore.Timestamp.fromDate(consumedAtDate),
      });
    } catch (error) {
      console.error('consumeImpersonationSession audit write failed', error);
    }

    response.status(200).json({
      success: true,
      customToken,
      targetUid,
      targetTenantId,
      targetMembershipId,
      expiresAt: expiresAtDate ? expiresAtDate.toISOString() : '',
    });
  },
);

async function validateEnterpriseOwnerAccess({ firestore, request, tenantId }) {
  const authHeader = String(request.headers?.authorization ?? '').trim();
  if (!authHeader.toLowerCase().startsWith('bearer ')) {
    return {
      allowed: false,
      status: 401,
      error: 'missing_firebase_auth',
      message: 'Envie Authorization: Bearer <Firebase ID token>.',
    };
  }

  const idToken = authHeader.substring(7).trim();
  if (!idToken) {
    return {
      allowed: false,
      status: 401,
      error: 'invalid_firebase_auth',
      message: 'Token Firebase invalido ou ausente.',
    };
  }

  let decodedToken;
  try {
    decodedToken = await admin.auth().verifyIdToken(idToken);
  } catch (_) {
    return {
      allowed: false,
      status: 401,
      error: 'firebase_auth_failed',
      message: 'Falha ao validar autenticacao Firebase para sync ERP.',
    };
  }

  const uid = String(decodedToken?.uid ?? '').trim();
  if (!uid) {
    return {
      allowed: false,
      status: 401,
      error: 'missing_uid',
      message: 'Usuario autenticado sem UID valido.',
    };
  }

  const tenantDoc = await firestore.collection('tenants').doc(tenantId).get();
  if (!tenantDoc.exists) {
    return {
      allowed: false,
      status: 404,
      error: 'tenant_not_found',
      message: 'Tenant nao encontrado para o sync ERP.',
    };
  }

  const tenantData = tenantDoc.data() || {};
  const workspaceType = String(tenantData.workspaceType ?? '').trim();
  if (workspaceType !== 'brand_owner_workspace') {
    return {
      allowed: false,
      status: 403,
      error: 'workspace_not_allowed',
      message:
        'Sincronizacao ERP permitida apenas para contas enterprise (brand_owner_workspace).',
    };
  }

  const membership = await loadTenantMembershipByTenantAndUser({
    firestore,
    tenantId,
    uid,
  });

  if (!membership) {
    return {
      allowed: false,
      status: 403,
      error: 'membership_not_found',
      message: 'Usuario sem membership ativa neste tenant.',
    };
  }

  const role = String(membership.role ?? '').trim().toLowerCase();
  const state = String(membership.state ?? 'active').trim().toLowerCase();
  const ativo = membership.ativo !== false;

  if (role !== 'owner' || !ativo || state !== 'active') {
    return {
      allowed: false,
      status: 403,
      error: 'owner_required',
      message:
        'Somente owner ativo do tenant enterprise pode configurar e executar sync ERP.',
    };
  }

  return {
    allowed: true,
    status: 200,
    error: '',
    message: '',
  };
}

async function loadTenantMembershipByTenantAndUser({ firestore, tenantId, uid }) {
  const memberships = firestore.collection('tenant_memberships');
  const patternDoc = await memberships.doc(`${tenantId}_${uid}`).get();
  if (patternDoc.exists) {
    return patternDoc.data() || null;
  }

  const byUidSnapshot = await memberships.where('uid', '==', uid).limit(20).get();
  for (const doc of byUidSnapshot.docs) {
    const data = doc.data() || {};
    const rowTenantId = String(data.tenantId ?? '').trim();
    if (rowTenantId === tenantId) {
      return data;
    }
  }

  return null;
}

exports.fetchSankhyaOperationTypes = onRequest(
  { cors: true, region: 'us-central1', timeoutSeconds: 30 },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const environment = String(request.body?.environment ?? '')
      .trim()
      .toLowerCase();
    const clientId = String(request.body?.clientId ?? '').trim();
    const clientSecret = String(request.body?.clientSecret ?? '').trim();
    const xToken = String(request.body?.xToken ?? '').trim();

    if (!['homolog', 'prod'].includes(environment)) {
      response.status(400).json({
        error: 'invalid_environment',
        message: 'Use homolog ou prod.',
      });
      return;
    }
    if (!clientId || !clientSecret || !xToken) {
      response.status(400).json({
        error: 'missing_credentials',
        message: 'Client Id, Client Secret e X-Token sao obrigatorios.',
      });
      return;
    }

    const baseUrl =
      environment === 'prod'
        ? 'https://api.sankhya.com.br'
        : 'https://api.sandbox.sankhya.com.br';

    try {
      const authPayload = await authenticateInSankhya({
        baseUrl,
        clientId,
        clientSecret,
        xToken,
      });

      const bearerToken = readBearerToken(authPayload);
      if (!bearerToken) {
        response.status(502).json({
          error: 'missing_bearer',
          message:
            'Autenticacao retornou sem access_token. Verifique credenciais e permissao do app Sankhya.',
        });
        return;
      }

      const sql = buildSankhyaOperationTypesSql();
      const queryResult = await executeSankhyaDbExplorerQuery({
        baseUrl,
        bearerToken,
        xToken,
        sql,
      });

      const operationTypes = queryResult.rows
        .map((row) => mapSankhyaOperationTypeRow(row))
        .filter((item) => item && item.code);

      response.status(200).json({
        ok: true,
        environment,
        endpoint: queryResult.endpointPath,
        rowCount: operationTypes.length,
        operationTypes,
      });
    } catch (error) {
      response.status(502).json({
        error: 'sankhya_operation_types_failed',
        message: error instanceof Error ? error.message : String(error),
      });
    }
  },
);

function buildSankhyaOperationTypesSql() {
  return `
SELECT
    T.CODTIPOPER AS CodTipoOper,
    T.DESCROPER AS Descricao,
    T.TIPMOV AS TipoMovimento,
    T.CALCDIFALPART AS CalcDifalPart,
    T.CALCICMS AS CalcIcms,
    T.CALCFCPINT AS CalcFcpInt,
    T.CALCFUSTTOP AS CalcFustTop
FROM TGFTOP T
WHERE T.ATIVO = 'S'
  AND T.DHALTER = (
        SELECT MAX(T2.DHALTER) FROM TGFTOP T2 WHERE T2.CODTIPOPER = T.CODTIPOPER
      )
ORDER BY T.CODTIPOPER
`.trim();
}

function mapSankhyaOperationTypeRow(row) {
  const code = toCodeString(
    readRowValueByAliases(row, ['CodTipoOper', 'CODTIPOOPER']),
  );
  if (!code) {
    return null;
  }

  return {
    code,
    description: String(
      readRowValueByAliases(row, ['Descricao', 'DESCRICAO']) ?? '',
    ).trim(),
    movementType: String(
      readRowValueByAliases(row, ['TipoMovimento', 'TIPOMOVIMENTO']) ?? '',
    ).trim(),
    calcDifalPart: String(
      readRowValueByAliases(row, ['CalcDifalPart', 'CALCDIFALPART']) ?? '',
    ).trim(),
    calcIcms: String(
      readRowValueByAliases(row, ['CalcIcms', 'CALCICMS']) ?? '',
    ).trim(),
    calcFcpInt: String(
      readRowValueByAliases(row, ['CalcFcpInt', 'CALCFCPINT']) ?? '',
    ).trim(),
    calcFustTop: String(
      readRowValueByAliases(row, ['CalcFustTop', 'CALCFUSTTOP']) ?? '',
    ).trim(),
  };
}

exports.syncSankhyaPriceTablesNightly = onSchedule(
  {
    region: 'us-central1',
    schedule: '0 3 * * *',
    timeZone: 'America/Sao_Paulo',
    timeoutSeconds: 540,
  },
  async () => {
    const firestore = admin.firestore();
    const tenantsSnapshot = await firestore.collection('tenants').get();

    let processedTenants = 0;
    let skippedTenants = 0;
    let failedTenants = 0;

    for (const tenantDoc of tenantsSnapshot.docs) {
      const tenantId = tenantDoc.id;
      const tenantData = tenantDoc.data() || {};
      const integration =
        tenantData.erpIntegration && typeof tenantData.erpIntegration === 'object'
          ? tenantData.erpIntegration
          : {};
      const credentials =
        integration.credentials && typeof integration.credentials === 'object'
          ? integration.credentials
          : {};

      const provider = String(integration.provider ?? '').trim().toLowerCase();
      const environment = String(integration.environment ?? '')
        .trim()
        .toLowerCase();
      const clientId = String(credentials.username ?? '').trim();
      const clientSecret = String(credentials.password ?? '').trim();
      const xToken = String(credentials.accessToken ?? '').trim();

      if (
        provider !== 'sankhya' ||
        !['homolog', 'prod'].includes(environment) ||
        !clientId ||
        !clientSecret ||
        !xToken
      ) {
        skippedTenants += 1;
        continue;
      }

      const baseUrl =
        environment === 'prod'
          ? 'https://api.sankhya.com.br'
          : 'https://api.sandbox.sankhya.com.br';

      try {
        const authPayload = await authenticateInSankhya({
          baseUrl,
          clientId,
          clientSecret,
          xToken,
        });

        const bearerToken = readBearerToken(authPayload);
        if (!bearerToken) {
          throw new Error('Autenticacao sem access_token.');
        }

        await syncSankhyaPriceTablesModule({
          firestore,
          tenantId,
          baseUrl,
          bearerToken,
          xToken,
        });
        processedTenants += 1;
      } catch (error) {
        failedTenants += 1;
        console.error(
          '[syncSankhyaPriceTablesNightly] tenant_failed',
          JSON.stringify({
            tenantId,
            message: error instanceof Error ? error.message : String(error),
          }),
        );
      }
    }

    console.log(
      '[syncSankhyaPriceTablesNightly] summary',
      JSON.stringify({ processedTenants, skippedTenants, failedTenants }),
    );
  },
);

async function authenticateInSankhya({
  baseUrl,
  clientId,
  clientSecret,
  xToken,
}) {
  const formBody = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    grant_type: 'client_credentials',
  });

  const authResponse = await fetch(`${baseUrl}/authenticate`, {
    method: 'POST',
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      'x-token': xToken,
    },
    body: formBody,
    signal: AbortSignal.timeout(15000),
  });

  const authBodyText = await authResponse.text();
  if (authResponse.status !== 200) {
    throw new Error(
      `Falha na autenticacao Sankhya (HTTP ${authResponse.status}): ${authBodyText.slice(0, 300)}`,
    );
  }

  const jsonPayload = tryParseJson(authBodyText);
  if (jsonPayload && typeof jsonPayload === 'object') {
    return jsonPayload;
  }

  return Object.fromEntries(new URLSearchParams(authBodyText));
}

async function updateTenantSyncState({ firestore, tenantId, patch }) {
  const ref = firestore.collection('tenant_sync_state').doc(tenantId);
  await ref.set(
    {
      tenantId,
      ...patch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function readBearerToken(payload) {
  if (!payload || typeof payload !== 'object') {
    return '';
  }

  const candidates = [
    payload.access_token,
    payload.accessToken,
    payload.token,
    payload.bearerToken,
  ];

  for (const candidate of candidates) {
    const value = String(candidate ?? '').trim();
    if (value) {
      return value;
    }
  }

  return '';
}

async function buildTenantNcmGroupIndex({ firestore, tenantId }) {
  const snapshot = await firestore
    .collection('tax_rule_groups')
    .where('tenantId', '==', tenantId)
    .select('memberNcms')
    .get();

  const index = new Map();
  for (const doc of snapshot.docs) {
    const memberNcms = doc.data()?.memberNcms;
    if (!Array.isArray(memberNcms)) {
      continue;
    }
    for (const ncmDigits of memberNcms) {
      const digits = normalizeDigits(ncmDigits);
      if (digits) {
        index.set(digits, doc.id);
      }
    }
  }
  return index;
}

async function syncSankhyaProductsModule({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
}) {
  const sourceUrl = `${baseUrl}${SANKHYA_PRODUCTS_PATH}`;
  const sankhyaResponse = await fetch(sourceUrl, {
    method: 'GET',
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${bearerToken}`,
      'x-token': xToken,
    },
    signal: AbortSignal.timeout(30000),
  });

  const sourceText = await sankhyaResponse.text();
  if (sankhyaResponse.status !== 200) {
    throw new Error(
      `Falha ao consultar modulo produtos no endpoint ${SANKHYA_PRODUCTS_PATH} (HTTP ${sankhyaResponse.status}): ${sourceText.slice(0, 300)}`,
    );
  }

  const sourceData = tryParseJson(sourceText);
  const sourceProducts = Array.isArray(sourceData?.produtos)
    ? sourceData.produtos
    : [];

  const validProducts = [];
  let filteredOutZeroCodeCount = 0;

  for (const rawItem of sourceProducts) {
    if (!rawItem || typeof rawItem !== 'object') {
      continue;
    }

    const productCode = toCodeString(rawItem.codigoProduto);
    if (!productCode || isZeroCode(productCode)) {
      filteredOutZeroCodeCount++;
      continue;
    }

    validProducts.push(rawItem);
    if (validProducts.length >= TEMPORARY_IMPORT_LIMIT) {
      break;
    }
  }

  const nowIso = new Date().toISOString();
  const syncBatchId = `sankhya_${Date.now()}`;
  const productsCollection = firestore.collection('produtos');
  const validProductCodes = validProducts
    .map((item) => toCodeString(item?.codigoProduto))
    .filter((item) => item && !isZeroCode(item));

  let fiscalQueryOk = false;
  let fiscalQueryEndpoint = null;
  let fiscalQueryRowsCount = 0;
  let fiscalQueryError = null;
  let fiscalMatchedCount = 0;
  let fiscalEnrichmentCount = 0;
  let fiscalOriginEnrichmentCount = 0;
  let fiscalIpiEnrichmentCount = 0;
  let productFiscalByCode = new Map();
  const ncmToGroupId = await buildTenantNcmGroupIndex({ firestore, tenantId });

  if (validProductCodes.length > 0) {
    try {
      const fiscalResult = await fetchSankhyaProductsFiscalData({
        baseUrl,
        bearerToken,
        xToken,
        productCodes: validProductCodes,
      });
      fiscalQueryOk = true;
      fiscalQueryEndpoint = fiscalResult.endpointPath;
      fiscalQueryRowsCount = fiscalResult.rowCount;
      productFiscalByCode = fiscalResult.byProductCode;
    } catch (error) {
      fiscalQueryError = error instanceof Error ? error.message : String(error);
      console.warn(
        '[syncSankhyaProductsModule] fiscal_enrichment_failed',
        JSON.stringify({
          tenantId,
          message: fiscalQueryError,
        }),
      );
    }
  }

  for (const rawItem of validProducts) {
    const erpProductCode = toCodeString(rawItem.codigoProduto);
    const docId = buildProductDocId(tenantId, erpProductCode);
    const docRef = productsCollection.doc(docId);
    const existingDoc = await docRef.get();
    const existingData = existingDoc.exists ? existingDoc.data() || {} : {};
    const nextSyncVersion = readInt(existingData.syncVersion) + 1;
    const internalCode = await resolveInternalProductCode({
      firestore,
      tenantId,
      erpProductCode,
      existingData,
    });
    const productFiscal = productFiscalByCode.get(erpProductCode);
    if (productFiscal) {
      fiscalMatchedCount += 1;
      if (productFiscal.origemMercadoriaCst !== null) {
        fiscalOriginEnrichmentCount += 1;
      }
      if (productFiscal.aliquotaIpiBase !== null) {
        fiscalIpiEnrichmentCount += 1;
      }
      if (
        productFiscal.origemMercadoriaCst !== null ||
        productFiscal.aliquotaIpiBase !== null
      ) {
        fiscalEnrichmentCount += 1;
      }
    }

    const payload = mapSankhyaProductToFirestore({
      tenantId,
      nowIso,
      syncBatchId,
      internalCode,
      source: rawItem,
      productFiscal,
      existingData,
      nextSyncVersion,
      ncmToGroupId,
    });

    await docRef.set(payload, { merge: true });
  }

  await updateTenantSyncState({
    firestore,
    tenantId,
    patch: {
      lastProductsSyncedAt: nowIso,
      lastProductsSyncAt: nowIso,
      lastProductsImportedCount: validProducts.length,
      lastProductsSourceCount: sourceProducts.length,
      lastProductsFilteredOutZeroCodeCount: filteredOutZeroCodeCount,
      lastProductsAppliedLimit: TEMPORARY_IMPORT_LIMIT,
      lastProductsFiscalQueryOk: fiscalQueryOk,
      lastProductsFiscalEndpoint: fiscalQueryEndpoint,
      lastProductsFiscalRowsCount: fiscalQueryRowsCount,
      lastProductsFiscalMatchedCount: fiscalMatchedCount,
      lastProductsFiscalEnrichedCount: fiscalEnrichmentCount,
      lastProductsFiscalOriginEnrichedCount: fiscalOriginEnrichmentCount,
      lastProductsFiscalIpiEnrichedCount: fiscalIpiEnrichmentCount,
      lastProductsFiscalQueryError: fiscalQueryError,
    },
  });

  return {
    message:
      'Sincronizacao de produtos concluida com limite temporario de 5, filtro de codigo 0 e enriquecimento fiscal por SQL.',
    endpoint: SANKHYA_PRODUCTS_PATH,
    sourceStatus: sankhyaResponse.status,
    sourceCount: sourceProducts.length,
    importedCount: validProducts.length,
    filteredOutZeroCodeCount,
    fiscalQueryOk,
    fiscalQueryEndpoint,
    fiscalQueryRowsCount,
    fiscalMatchedCount,
    fiscalEnrichmentCount,
    fiscalOriginEnrichmentCount,
    fiscalIpiEnrichmentCount,
    fiscalQueryError,
    skippedNotFoundCount: 0,
    appliedLimit: TEMPORARY_IMPORT_LIMIT,
  };
}

async function syncSankhyaPriceTablesModule({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
}) {
  const tenantSnapshot = await firestore.collection('tenants').doc(tenantId).get();
  const tenantData = tenantSnapshot.exists ? tenantSnapshot.data() || {} : {};
  const priceTableCodes = normalizePriceTableCodes(
    tenantData?.erpIntegration?.priceTableCodes,
  );

  if (priceTableCodes.length === 0) {
    throw new Error(
      'Nenhum codigo de tabela foi configurado em erpIntegration.priceTableCodes para sincronizar tabelas de preco.',
    );
  }

  const nowIso = new Date().toISOString();
  const primaryTableCode = priceTableCodes[0];
  const defaultPriceTableDocId = buildDefaultPriceTableDocId(tenantId);

  await upsertDefaultPriceTableDocument({
    firestore,
    tenantId,
    defaultPriceTableDocId,
    primaryTableCode,
    nowIso,
  });

  const productIndex = await buildTenantProductIndex({
    firestore,
    tenantId,
  });
  const syncBatchId = `sankhya_precos_${Date.now()}`;
  const pricesCollection = firestore.collection('product_base_prices');

  let sourceCount = 0;
  let importedCount = 0;
  let skippedNotFoundCount = 0;
  let filteredOutZeroCodeCount = 0;
  const incrementalModeActive = false;
  const incrementalFallbackReason = null;
  const incrementalCandidatesCount = 0;
  const incrementalApiLookups = 0;
  const incrementalReadRows = 0;
  const incrementalScannedPages = 0;
  const incrementalScanComplete = true;

  const tableSummaries = [];
  const primaryTablePriceByProductId = new Map();

  const pricesWriter = firestore.bulkWriter();
  pricesWriter.onWriteError((error) => {
    // Retry transient failures a few times before surfacing the error.
    if (error.failedAttempts < 3) {
      return true;
    }
    console.error(
      '[syncSankhyaPriceTablesModule] write_failed',
      JSON.stringify({
        code: error.code,
        message: error.message,
        documentPath: error.documentRef?.path || null,
        failedAttempts: error.failedAttempts,
      }),
    );
    return false;
  });

  try {
    for (const tableCode of priceTableCodes) {
      const priceTableDocId = buildPriceTableDocId(tenantId, tableCode);
      await upsertPriceTableDocument({
        firestore,
        tenantId,
        priceTableDocId,
        tableCode,
        nowIso,
      });

      let page = 1;
      let hasMore = true;
      let tableSourceCount = 0;
      let tableImportedCount = 0;
      const tableUniqueProductIds = new Set();

      while (hasMore) {
        const endpointPath = `/v1/precos/tabela/${encodeURIComponent(
          tableCode,
        )}?pagina=${page}`;
        const url = `${baseUrl}${endpointPath}`;

        const pageResponse = await fetch(url, {
          method: 'GET',
          headers: {
            Accept: 'application/json',
            Authorization: `Bearer ${bearerToken}`,
            'x-token': xToken,
          },
          signal: AbortSignal.timeout(30000),
        });

        const pageText = await pageResponse.text();
        if (pageResponse.status !== 200) {
          throw new Error(
            `Falha ao consultar tabela de preco ${tableCode} (pagina ${page}, HTTP ${pageResponse.status}): ${pageText.slice(0, 300)}`,
          );
        }

        const pageData = tryParseJson(pageText) || {};
        const rows = readPriceRowsFromPayload(pageData);

        sourceCount += rows.length;
        tableSourceCount += rows.length;

        for (const row of rows) {
          const productCode = toCodeString(row?.codigoProduto);
          if (!productCode || isZeroCode(productCode)) {
            filteredOutZeroCodeCount++;
            continue;
          }

          const mappedProduct = productIndex.get(productCode);
          if (!mappedProduct) {
            skippedNotFoundCount++;
            continue;
          }

          const priceValue = toNumberOrNull(row?.valor);
          if (priceValue === null) {
            continue;
          }

          const localCode = toCodeString(row?.codigoLocalEstoque) || '0';
          const unitCode = normalizeTextToken(row?.unidade, 'UN');
          const controlCode = normalizeTextToken(row?.controle, 'SEM_CONTROLE');
          const priceDocId = buildProductBasePriceDocId({
            tenantId,
            tableCode,
            productId: mappedProduct.productId,
            localCode,
            unitCode,
            controlCode,
          });

          const payload = {
            id: priceDocId,
            tenantId,
            productId: mappedProduct.productId,
            priceTableId: priceTableDocId,
            regionId: 'ALL',
            basePrice: priceValue,
            status: 'active',
            currencyCode: 'BRL',
            validFrom: null,
            validUntil: null,
            createdAt: nowIso,
            updatedAt: nowIso,
            origin: 'erp',
            erpSyncId: syncBatchId,
            erpMeta: {
              codigoTabela: tableCode,
              codigoProduto: productCode,
              codigoLocalEstoque: localCode,
              unidade: unitCode,
              controle: controlCode,
            },
          };

          pricesWriter.set(pricesCollection.doc(priceDocId), payload, { merge: true });
          importedCount++;
          tableImportedCount++;
          tableUniqueProductIds.add(mappedProduct.productId);

          if (tableCode === primaryTableCode) {
            if (!primaryTablePriceByProductId.has(mappedProduct.productId)) {
              primaryTablePriceByProductId.set(mappedProduct.productId, priceValue);
            }

            const defaultPriceDocId = buildDefaultProductBasePriceDocId({
              tenantId,
              productId: mappedProduct.productId,
              defaultPriceTableDocId,
            });

            pricesWriter.set(
              pricesCollection.doc(defaultPriceDocId),
              {
                id: defaultPriceDocId,
                tenantId,
                productId: mappedProduct.productId,
                priceTableId: defaultPriceTableDocId,
                regionId: 'default',
                basePrice: priceValue,
                status: 'active',
                currencyCode: 'BRL',
                validFrom: null,
                validUntil: null,
                createdAt: nowIso,
                updatedAt: nowIso,
                origin: 'erp',
                erpSyncId: syncBatchId,
                erpMeta: {
                  codigoTabela: tableCode,
                  codigoProduto: productCode,
                  codigoLocalEstoque: localCode,
                  unidade: unitCode,
                  controle: controlCode,
                },
              },
              { merge: true },
            );
          }
        }

        const rawHasMore = pageData.temMaisRegistros;
        const normalizedHasMore = String(rawHasMore ?? '').toLowerCase();
        const hasMoreFlagKnown =
          rawHasMore === true ||
          rawHasMore === false ||
          normalizedHasMore === 'true' ||
          normalizedHasMore === 'false';
        const hasMoreByFlag =
          rawHasMore === true ||
          normalizedHasMore === 'true';
        hasMore = hasMoreFlagKnown ? hasMoreByFlag : rows.length > 0;
        page += 1;
        if (page > 1000) {
          throw new Error(
            `Limite de paginas excedido ao consultar tabela ${tableCode}.`,
          );
        }
      }

      await firestore.collection('tabelas_preco').doc(priceTableDocId).set(
        {
          rowCount: tableUniqueProductIds.size,
          updatedAt: nowIso,
        },
        { merge: true },
      );

      tableSummaries.push({
        codigoTabela: tableCode,
        sourceCount: tableSourceCount,
        importedCount: tableImportedCount,
        uniqueProductCount: tableUniqueProductIds.size,
        mode: 'full',
      });
    }

    if (primaryTablePriceByProductId.size > 0) {
      for (const [productId, priceValue] of primaryTablePriceByProductId.entries()) {
        pricesWriter.set(
          firestore.collection('produtos').doc(productId),
          {
            valorBruto: priceValue,
            moeda: 'BRL',
            erpSyncId: syncBatchId,
            updatedAt: nowIso,
          },
          { merge: true },
        );
      }
    }
  } finally {
    await pricesWriter.close();
  }

  await firestore.collection('tabelas_preco').doc(defaultPriceTableDocId).set(
    {
      rowCount: primaryTablePriceByProductId.size,
      updatedAt: nowIso,
    },
    { merge: true },
  );

  await updateTenantSyncState({
    firestore,
    tenantId,
    patch: {
      lastPriceSyncAt: nowIso,
      lastPriceSyncMode: 'full',
      lastPriceSyncFallbackReason: incrementalFallbackReason,
      lastPriceSyncCandidatesCount: incrementalCandidatesCount,
      lastPriceSyncApiLookups: incrementalApiLookups,
      lastPriceSyncReadRows: sourceCount,
      lastPriceSyncScannedProductPages: incrementalScannedPages,
      lastPriceSyncProductScanComplete: incrementalScanComplete,
      lastPriceSyncImportedCount: importedCount,
    },
  });

  return {
    message:
      'Sincronizacao de tabelas de preco concluida. Apenas produtos ja cadastrados no SaaS receberam preco.',
    endpoint: '/v1/precos/tabela/{codigoTabela}?pagina=N',
    sourceCount,
    importedCount,
    filteredOutZeroCodeCount,
    skippedNotFoundCount,
    primaryTableCode,
    mirroredDefaultPriceCount: primaryTablePriceByProductId.size,
    appliedPriceTableCodes: priceTableCodes,
    incrementalMode: incrementalModeActive,
    incrementalFallbackReason,
    incrementalCandidatesCount,
    incrementalApiLookups,
    incrementalReadRows,
    incrementalScannedProductPages: incrementalScannedPages,
    incrementalScanComplete,
    tableSummaries,
  };
}

function normalizePriceTableCodes(raw) {
  const tokens = [];
  if (Array.isArray(raw)) {
    for (const item of raw) {
      tokens.push(String(item ?? ''));
    }
  } else if (typeof raw === 'string') {
    tokens.push(...raw.split(/[\s,;|]+/));
  }

  const normalized = [];
  const seen = new Set();
  for (const token of tokens) {
    const clean = String(token ?? '').trim();
    if (!clean || !/^\d+$/.test(clean)) {
      continue;
    }
    if (seen.has(clean)) {
      continue;
    }
    seen.add(clean);
    normalized.push(clean);
  }
  return normalized;
}

async function buildTenantProductIndex({ firestore, tenantId }) {
  const snapshot = await firestore
    .collection('produtos')
    .where('tenantId', '==', tenantId)
    .select('erpProductId', 'codigoFabricante', 'deletedAt')
    .get();

  const index = new Map();
  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    if (data.deletedAt) {
      continue;
    }

    const keys = [
      toCodeString(data.erpProductId),
      toCodeString(data.codigoFabricante),
    ];

    for (const key of keys) {
      if (!key || isZeroCode(key)) {
        continue;
      }
      if (!index.has(key)) {
        index.set(key, {
          productId: doc.id,
        });
      }
    }
  }

  return index;
}

async function upsertPriceTableDocument({
  firestore,
  tenantId,
  priceTableDocId,
  tableCode,
  nowIso,
}) {
  const docRef = firestore.collection('tabelas_preco').doc(priceTableDocId);
  const snapshot = await docRef.get();
  const existing = snapshot.exists ? snapshot.data() || {} : {};

  await docRef.set(
    {
      id: priceTableDocId,
      tenantId,
      nome: existing.nome || `Tabela Sankhya ${tableCode}`,
      scopeType: existing.scopeType || 'general',
      scopeLabel: existing.scopeLabel || `Sankhya CODTAB ${tableCode}`,
      scopeIndex: existing.scopeIndex || [`sankhya`, `codtab_${tableCode}`],
      origem: 'erp',
      status: 'ativo',
      linkedEntityId: existing.linkedEntityId || null,
      createdAt: existing.createdAt || nowIso,
      updatedAt: nowIso,
    },
    { merge: true },
  );
}

async function upsertDefaultPriceTableDocument({
  firestore,
  tenantId,
  defaultPriceTableDocId,
  primaryTableCode,
  nowIso,
}) {
  const docRef = firestore.collection('tabelas_preco').doc(defaultPriceTableDocId);
  const snapshot = await docRef.get();
  const existing = snapshot.exists ? snapshot.data() || {} : {};

  await docRef.set(
    {
      id: defaultPriceTableDocId,
      tenantId,
      nome: existing.nome || 'Tabela padrao',
      scopeType: existing.scopeType || 'general',
      scopeLabel:
        existing.scopeLabel || `Tabela padrao vinculada ao Sankhya CODTAB ${primaryTableCode}`,
      scopeIndex: existing.scopeIndex || ['default', 'tenant_default'],
      origem: existing.origem || 'system',
      status: existing.status || 'ativo',
      linkedEntityId: existing.linkedEntityId || null,
      createdAt: existing.createdAt || nowIso,
      updatedAt: nowIso,
    },
    { merge: true },
  );

  await firestore.collection('tenants').doc(tenantId).set(
    {
      defaultPriceTableIds: { tenant_default: defaultPriceTableDocId },
      defaultPriceRegionIds: { tenant_default: 'default' },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function readPriceRowsFromPayload(payload) {
  if (Array.isArray(payload?.produtos)) {
    return payload.produtos;
  }
  if (Array.isArray(payload?.precos)) {
    return payload.precos;
  }
  return [];
}

function buildPriceTableDocId(tenantId, tableCode) {
  return `erp_pt_${tenantId}_${toCodeString(tableCode)}`;
}

function buildDefaultPriceTableDocId(tenantId) {
  return `pt_default_${tenantId}`;
}

function buildDefaultProductBasePriceDocId({
  tenantId,
  productId,
  defaultPriceTableDocId,
}) {
  return `pbp_${tenantId}_${productId}_${defaultPriceTableDocId}`;
}

function normalizeTextToken(value, fallback) {
  const raw = String(value ?? '').trim();
  if (!raw) {
    return fallback;
  }
  const normalized = raw
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^A-Za-z0-9_-]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return normalized || fallback;
}

function buildProductBasePriceDocId({
  tenantId,
  tableCode,
  productId,
  localCode,
  unitCode,
  controlCode,
}) {
  return [
    'erp_pbp',
    tenantId,
    toCodeString(tableCode),
    productId,
    normalizeTextToken(localCode, '0'),
    normalizeTextToken(unitCode, 'UN'),
    normalizeTextToken(controlCode, 'SEM_CONTROLE'),
  ].join('_');
}

function mapSankhyaProductToFirestore({
  tenantId,
  nowIso,
  syncBatchId,
  internalCode,
  source,
  productFiscal,
  existingData,
  nextSyncVersion,
  ncmToGroupId,
}) {
  const code = toCodeString(source.codigoProduto);
  const name = String(source.nome ?? '').trim();
  const groupName = String(source.nomeGrupoProduto ?? '').trim();
  const volume = String(source.volume ?? '').trim();
  const brand = String(source.marca ?? '').trim();
  const ncmRaw = String(source.ncm ?? '').trim();
  const cestRaw = String(source.cest ?? '').trim();
  const eanRaw = String(source.referencia ?? '').trim();
  const origemMercadoriaCst = normalizeOrigemMercadoriaCst(
    productFiscal?.origemMercadoriaCst ?? existingData.origemMercadoriaCst,
  );
  const aliquotaIpiBase = toNumberOrNull(
    productFiscal?.aliquotaIpiBase ?? existingData.aliquotaIpiBase,
  );
  const ncmDigits = normalizeDigits(ncmRaw);
  const grupoTributarioId =
    (ncmDigits ? ncmToGroupId?.get(ncmDigits) : null) ??
    existingData.grupoTributarioId ??
    null;

  return {
    id: buildProductDocId(tenantId, code),
    tenantId,
    representedCompanyId: existingData.representedCompanyId ?? null,
    codigoInterno: internalCode,
    descricao: name || `Produto ${code}`,
    descricaoResumida: name || null,
    descricaoLonga: String(source.complemento ?? '').trim() || null,
    codigoFabricante: code,
    ean: eanRaw || null,
    marca: brand || null,
    categoria: groupName || null,
    unidade: volume || null,
    ncm: ncmRaw || null,
    cest: cestRaw || null,
    grupoTributarioId,
    origemMercadoriaCst,
    aliquotaIpiBase,
    pesoKg: toNumberOrNull(source.pesoBruto),
    larguraMm: toNumberOrNull(source.largura),
    alturaMm: toNumberOrNull(source.altura),
    comprimentoMm: toNumberOrNull(source.espessura),
    origemCadastro: 'erp',
    status: source.ativo === false ? 'inativo' : 'ativo',
    erpProductId: code,
    erpSyncId: syncBatchId,
    updatedAt: nowIso,
    createdAt: existingData.createdAt || nowIso,
    deletedAt: null,
    syncVersion: nextSyncVersion,
  };
}

async function resolveInternalProductCode({
  firestore,
  tenantId,
  erpProductCode,
  existingData,
}) {
  const currentInternalCode = String(existingData.codigoInterno ?? '').trim();
  if (currentInternalCode && currentInternalCode !== erpProductCode) {
    return currentInternalCode;
  }

  const sequence = await nextTenantErpProductInternalSequence({
    firestore,
    tenantId,
  });
  return `ERP-${String(sequence).padStart(6, '0')}`;
}

async function nextTenantErpProductInternalSequence({ firestore, tenantId }) {
  const tenantRef = firestore.collection('tenants').doc(tenantId);
  return firestore.runTransaction(async (transaction) => {
    const tenantSnapshot = await transaction.get(tenantRef);
    const current = readInt(tenantSnapshot.data()?.erpInternalProductSequence);
    const next = current + 1;
    transaction.set(
      tenantRef,
      {
        erpInternalProductSequence: next,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return next;
  });
}

function buildProductDocId(tenantId, productCode) {
  return `erp_prod_${tenantId}_${toCodeString(productCode)}`;
}

function toCodeString(value) {
  if (value === null || value === undefined) {
    return '';
  }

  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      return '';
    }
    return String(Math.trunc(value));
  }

  return String(value).trim();
}

function isZeroCode(codeValue) {
  const normalized = String(codeValue ?? '').trim();
  if (!normalized) {
    return true;
  }

  const numeric = Number(normalized.replace(',', '.'));
  if (Number.isFinite(numeric) && numeric === 0) {
    return true;
  }

  return /^0+$/.test(normalized);
}

function toNumberOrNull(value) {
  if (value === null || value === undefined || value === '') {
    return null;
  }

  const numeric = Number(String(value).replace(',', '.'));
  return Number.isFinite(numeric) ? numeric : null;
}

function readInt(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }

  if (typeof value === 'string') {
    const parsed = Number.parseInt(value.trim(), 10);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  return 0;
}

function tryParseJson(text) {
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

async function fetchSankhyaProductsFiscalData({
  baseUrl,
  bearerToken,
  xToken,
  productCodes,
}) {
  const normalizedCodes = normalizeSankhyaNumericCodeList(productCodes);
  if (normalizedCodes.length === 0) {
    return {
      endpointPath: null,
      rowCount: 0,
      byProductCode: new Map(),
    };
  }

  const sql = buildSankhyaProductFiscalSql(normalizedCodes);
  const queryResult = await executeSankhyaDbExplorerQuery({
    baseUrl,
    bearerToken,
    xToken,
    sql,
  });

  const byProductCode = new Map();
  for (const row of queryResult.rows) {
    const productCode = toCodeString(
      readRowValueByAliases(row, [
        'CodigoProduto',
        'CODIGOPRODUTO',
        'CODPROD',
      ]),
    );
    if (!productCode || isZeroCode(productCode)) {
      continue;
    }

    const origemMercadoriaCst = normalizeOrigemMercadoriaCst(
      readRowValueByAliases(row, [
        'OrigemMercadoria',
        'ORIGEMMERCADORIA',
        'ORIGPROD',
      ]),
    );
    const aliquotaIpiBase = toNumberOrNull(
      readRowValueByAliases(row, [
        'AliquotaIPI',
        'ALIQUOTAIPI',
        'PERCENTUAL',
        'IPI',
      ]),
    );

    byProductCode.set(productCode, {
      origemMercadoriaCst,
      aliquotaIpiBase,
    });
  }

  return {
    endpointPath: queryResult.endpointPath,
    rowCount: queryResult.rows.length,
    byProductCode,
  };
}

function buildSankhyaProductFiscalSql(productCodes) {
  const safeCodes = normalizeSankhyaNumericCodeList(productCodes);
  if (safeCodes.length === 0) {
    return '';
  }

  const codesInClause = safeCodes.join(', ');
  return `
SELECT
    TO_CHAR(PRO.CODPROD) AS CodigoProduto,
    NVL(TO_CHAR(PRO.ORIGPROD), '0') AS OrigemMercadoria,
    COALESCE(
        IPI_ESPECIFICO.PERCENTUAL,
        TO_NUMBER(REPLACE(NCM.IPI, ',', '.')),
        0
    ) AS AliquotaIPI
FROM TGFPRO PRO
LEFT JOIN TGFIPI IPI_ESPECIFICO ON PRO.CODIPI = IPI_ESPECIFICO.CODIPI
LEFT JOIN TGFNCM NCM ON LTRIM(REPLACE(NCM.CODNCM, '.', ''), '0') = LTRIM(REPLACE(PRO.NCM, '.', ''), '0')
WHERE PRO.ATIVO = 'S'
  AND PRO.CODPROD IN (${codesInClause})
`.trim();
}

async function executeSankhyaDbExplorerQuery({
  baseUrl,
  bearerToken,
  xToken,
  sql,
}) {
  const payloadVariants = [
    {
      name: 'serviceName_requestBody_sql',
      payload: {
        serviceName: 'DbExplorerSP.executeQuery',
        requestBody: { sql },
      },
    },
    {
      name: 'requestBody_sql',
      payload: {
        requestBody: { sql },
      },
    },
    {
      name: 'requestBody_query',
      payload: {
        requestBody: { query: sql },
      },
    },
  ];

  const failures = [];
  for (const endpointPath of SANKHYA_DBEXPLORER_ENDPOINT_PATHS) {
    for (const payloadVariant of payloadVariants) {
      const response = await fetch(`${baseUrl}${endpointPath}`, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          Authorization: `Bearer ${bearerToken}`,
          'content-type': 'application/json',
          'x-token': xToken,
        },
        body: JSON.stringify(payloadVariant.payload),
        signal: AbortSignal.timeout(30000),
      });

      const bodyText = await response.text();
      const parsed = tryParseJson(bodyText);
      const xmlError = extractSankhyaXmlError(bodyText);
      if (response.ok) {
        if (xmlError) {
          failures.push({
            endpointPath,
            payloadVariant: payloadVariant.name,
            status: response.status,
            bodyPreview: xmlError,
          });
          continue;
        }
        return {
          endpointPath,
          payloadVariant: payloadVariant.name,
          rows: normalizeDbExplorerRows(parsed),
        };
      }

      failures.push({
        endpointPath,
        payloadVariant: payloadVariant.name,
        status: response.status,
        bodyPreview: bodyText.slice(0, 220),
      });
    }
  }

  const details = failures
    .map(
      (item) =>
        `${item.endpointPath} [${item.payloadVariant}] -> HTTP ${item.status}: ${item.bodyPreview}`,
    )
    .join(' | ')
    .slice(0, 1800);

  throw new Error(`DbExplorer executeQuery falhou. Tentativas: ${details}`);
}

function extractSankhyaXmlError(bodyText) {
  if (!bodyText || !bodyText.includes('<serviceResponse')) {
    return null;
  }

  const statusMatch = bodyText.match(/status="(\d+)"/i);
  if (!statusMatch || statusMatch[1] !== '0') {
    return null;
  }

  const cdataMatch = bodyText.match(/<statusMessage><!\[CDATA\[(.*?)\]\]><\/statusMessage>/is);
  const encoded = String(cdataMatch?.[1] ?? '').trim();
  if (!encoded) {
    return 'Sankhya XML status=0 (sem mensagem detalhada).';
  }

  try {
    const decoded = Buffer.from(encoded, 'base64').toString('latin1').trim();
    return decoded || `Sankhya XML status=0: ${encoded}`;
  } catch {
    return `Sankhya XML status=0: ${encoded}`;
  }
}

function normalizeDbExplorerRows(payload) {
  if (!payload || typeof payload !== 'object') {
    return [];
  }

  const root = payload.responseBody && typeof payload.responseBody === 'object'
    ? payload.responseBody
    : payload;
  const rawRows = Array.isArray(root.rows) ? root.rows : [];
  if (rawRows.length === 0) {
    return [];
  }

  if (
    rawRows.every(
      (row) => row && typeof row === 'object' && !Array.isArray(row),
    )
  ) {
    return rawRows;
  }

  const fields = Array.isArray(root.fieldsMetadata) ? root.fieldsMetadata : [];
  if (fields.length === 0) {
    return [];
  }

  return rawRows
    .filter((row) => Array.isArray(row))
    .map((row) => {
      const mapped = {};
      for (let index = 0; index < fields.length; index++) {
        const fieldName = String(fields[index]?.name ?? '').trim();
        if (!fieldName) {
          continue;
        }
        mapped[fieldName] = row[index] ?? null;
      }
      return mapped;
    });
}

function readRowValueByAliases(row, aliases) {
  if (!row || typeof row !== 'object') {
    return undefined;
  }

  for (const alias of aliases) {
    if (Object.prototype.hasOwnProperty.call(row, alias)) {
      return row[alias];
    }
  }

  const loweredMap = new Map(
    Object.entries(row).map(([key, value]) => [key.toLowerCase(), value]),
  );
  for (const alias of aliases) {
    const value = loweredMap.get(String(alias).toLowerCase());
    if (value !== undefined) {
      return value;
    }
  }

  return undefined;
}

function normalizeOrigemMercadoriaCst(value) {
  const normalized = String(value ?? '').trim();
  if (!normalized) {
    return null;
  }
  const parsed = Number.parseInt(normalized, 10);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 8) {
    return null;
  }
  return String(parsed);
}

function normalizeSankhyaNumericCodeList(values) {
  const normalized = [];
  const seen = new Set();
  for (const value of values) {
    const token = String(value ?? '').trim();
    if (!/^\d+$/.test(token)) {
      continue;
    }
    if (isZeroCode(token)) {
      continue;
    }
    const clean = String(Number.parseInt(token, 10));
    if (!clean || seen.has(clean)) {
      continue;
    }
    seen.add(clean);
    normalized.push(clean);
  }
  return normalized;
}

async function syncSankhyaTaxRulesModule({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
}) {
  const nowIso = new Date().toISOString();
  const syncBatchId = `sankhya_tax_${Date.now()}`;
  const sql = buildSankhyaTaxRulesSql();
  const queryResult = await executeSankhyaDbExplorerQuery({
    baseUrl,
    bearerToken,
    xToken,
    sql,
  });

  // Passo 1: mapeia todas as linhas em memoria (descarta linhas invalidas ou
  // excecoes por NCM sem nenhum valor fiscal real - ver mapSankhyaTaxRuleRow).
  const syncVersionBase = Date.now() * 1000;
  const mappedRows = [];
  let skippedInvalidCount = 0;
  for (let index = 0; index < queryResult.rows.length; index++) {
    const row = queryResult.rows[index];
    const mapped = mapSankhyaTaxRuleRow({
      tenantId,
      row,
      nowIso,
      syncBatchId,
      syncVersion: syncVersionBase + index,
    });
    if (!mapped) {
      skippedInvalidCount += 1;
      continue;
    }
    mappedRows.push(mapped);
  }

  // Passo 2: separa regras genericas por UF (sem NCM - tier 3 do motor) das
  // regras por NCM, e agrupa os NCMs com perfil fiscal identico (fingerprint)
  // em Grupos Tributarios automaticos.
  const genericRows = [];
  const ncmVectorMap = new Map();
  for (const mapped of mappedRows) {
    const ncmDigits = normalizeDigits(mapped.ncm);
    if (!ncmDigits) {
      genericRows.push(mapped);
      continue;
    }
    if (!ncmVectorMap.has(ncmDigits)) {
      ncmVectorMap.set(ncmDigits, []);
    }
    ncmVectorMap.get(ncmDigits).push(mapped);
  }

  const clustersByHash = new Map();
  for (const [ncmDigits, vectorRows] of ncmVectorMap.entries()) {
    const hash = computeFingerprintHash(buildTaxFingerprintKey(vectorRows));
    if (!clustersByHash.has(hash)) {
      clustersByHash.set(hash, { ncmDigitsList: [], vectorRows });
    }
    clustersByHash.get(hash).ncmDigitsList.push(ncmDigits);
  }

  const groupedNcmDigits = new Set();
  const ncmToGroupId = new Map();
  const groupDocsToUpsert = [];
  const groupRuleDocs = [];
  for (const cluster of clustersByHash.values()) {
    if (cluster.ncmDigitsList.length < 2) {
      continue;
    }
    const hash = computeFingerprintHash(
      buildTaxFingerprintKey(cluster.vectorRows),
    );
    const groupId = `erp_group_${tenantId}_${hash}`;
    const memberNcms = cluster.ncmDigitsList.slice().sort();
    for (const ncmDigits of memberNcms) {
      groupedNcmDigits.add(ncmDigits);
      ncmToGroupId.set(ncmDigits, groupId);
    }
    groupDocsToUpsert.push({
      groupId,
      hash,
      memberNcms,
      vectorRows: cluster.vectorRows,
    });
    for (const vectorRow of cluster.vectorRows) {
      const ruleId = `erp_taxgroup_${tenantId}_${hash}_${sanitizeKeyToken(vectorRow.ufOrigem, 'ANY')}_${sanitizeKeyToken(vectorRow.ufDestino, 'ANY')}`;
      groupRuleDocs.push({
        ...vectorRow,
        id: ruleId,
        ncm: null,
        cest: null,
        taxGroupId: groupId,
      });
    }
  }

  const taxRulesCollection = firestore.collection('tax_rules');
  const taxRuleGroupsCollection = firestore.collection('tax_rule_groups');
  const writer = firestore.bulkWriter();
  writer.onWriteError((error) => {
    if (error.failedAttempts < 3) {
      return true;
    }
    console.error(
      '[syncSankhyaTaxRulesModule] write_failed',
      JSON.stringify({
        code: error.code,
        message: error.message,
        documentPath: error.documentRef?.path || null,
        failedAttempts: error.failedAttempts,
      }),
    );
    return false;
  });

  let importedCount = 0;
  let importedMissingCestCount = 0;
  let prunedStaleRuleCount = 0;
  const mappedRuleIds = new Set();

  try {
    const writeRule = (ruleDoc) => {
      mappedRuleIds.add(ruleDoc.id);
      writer.set(taxRulesCollection.doc(ruleDoc.id), ruleDoc, { merge: true });
      importedCount += 1;
      if (!ruleDoc.cest) {
        importedMissingCestCount += 1;
      }
    };

    for (const mapped of genericRows) {
      writeRule(mapped);
    }
    for (const [ncmDigits, vectorRows] of ncmVectorMap.entries()) {
      if (groupedNcmDigits.has(ncmDigits)) {
        continue;
      }
      for (const mapped of vectorRows) {
        writeRule(mapped);
      }
    }
    for (const ruleDoc of groupRuleDocs) {
      writeRule(ruleDoc);
    }

    for (const groupDoc of groupDocsToUpsert) {
      const ref = taxRuleGroupsCollection.doc(groupDoc.groupId);
      const existingSnapshot = await ref.get();
      const existing = existingSnapshot.exists
        ? existingSnapshot.data() || {}
        : {};
      const isAutoName = existing.autoGenerated !== false;
      const autoName = buildAutoGroupName(
        groupDoc.vectorRows,
        groupDoc.memberNcms.length,
      );
      const name = isAutoName ? autoName : existing.name || autoName;
      writer.set(
        ref,
        {
          id: groupDoc.groupId,
          tenantId,
          representedCompanyId: null,
          status: existing.status || 'active',
          source: 'erp_sync',
          erpProvider: 'sankhya',
          externalCode: groupDoc.hash,
          fingerprint: groupDoc.hash,
          memberNcms: groupDoc.memberNcms,
          memberNcmCount: groupDoc.memberNcms.length,
          priority: existing.priority ?? 0,
          autoGenerated: existing.autoGenerated ?? true,
          name,
          normalizedName: name.trim().toLowerCase(),
          description:
            existing.description ||
            buildAutoGroupDescription(groupDoc.vectorRows, groupDoc.memberNcms),
          createdAt: existing.createdAt || nowIso,
          updatedAt: nowIso,
          erpSyncId: syncBatchId,
        },
        { merge: true },
      );
    }

    const existingSnapshot = await taxRulesCollection
      .where('tenantId', '==', tenantId)
      .get();
    for (const doc of existingSnapshot.docs) {
      const payload = doc.data() || {};
      const origin = String(payload.origin ?? '').trim().toLowerCase();
      if (origin !== 'erp') {
        continue;
      }

      const representedScope = String(payload.representedCompanyId ?? '').trim();
      if (representedScope) {
        continue;
      }

      if (mappedRuleIds.has(doc.id)) {
        continue;
      }

      writer.delete(doc.ref);
      prunedStaleRuleCount += 1;
    }
  } finally {
    await writer.close();
  }

  let productsGroupLinkedCount = 0;
  if (ncmToGroupId.size > 0) {
    productsGroupLinkedCount = await applyTaxGroupsToExistingProducts({
      firestore,
      tenantId,
      ncmToGroupId,
    });
  }

  await updateTenantSyncState({
    firestore,
    tenantId,
    patch: {
      lastTaxRulesSyncAt: nowIso,
      lastTaxRulesSyncMode: 'full',
      lastTaxRulesSourceCount: queryResult.rows.length,
      lastTaxRulesImportedCount: importedCount,
      lastTaxRulesSkippedInvalidCount: skippedInvalidCount,
      lastTaxRulesImportedMissingCestCount: importedMissingCestCount,
      lastTaxRulesPrunedStaleRuleCount: prunedStaleRuleCount,
      lastTaxRulesGroupsCreatedCount: groupDocsToUpsert.length,
      lastTaxRulesGroupedNcmCount: groupedNcmDigits.size,
      lastTaxRulesProductsGroupLinkedCount: productsGroupLinkedCount,
      lastTaxRulesEndpoint: queryResult.endpointPath,
    },
  });

  return {
    message:
      'Sincronizacao completa de tax_rules concluida via SQL DbExplorer, com agrupamento automatico de grupos tributarios.',
    endpoint: queryResult.endpointPath,
    sourceCount: queryResult.rows.length,
    importedCount,
    skippedInvalidCount,
    importedMissingCestCount,
    prunedStaleRuleCount,
    groupsCreatedCount: groupDocsToUpsert.length,
    groupedNcmCount: groupedNcmDigits.size,
    productsGroupLinkedCount,
    filteredOutZeroCodeCount: 0,
    skippedNotFoundCount: 0,
    mirroredRuleCount: mappedRuleIds.size,
  };
}

function buildClienteDocId(tenantId, codigoParceiro) {
  return `erp_cliente_${tenantId}_${toCodeString(codigoParceiro)}`;
}

// Mantido em paridade com `defaultTaxRegime` de lib/src/core/models/domain_types.dart.
// TGFPAR nao possui coluna de regime tributario do parceiro; usado apenas
// como fallback quando o documento ainda nao tem valor definido manualmente.
const SANKHYA_DEFAULT_TAX_REGIME = 'simples_nacional';

// Sync de clientes/parceiros Sankhya (TGFPAR) para a colecao `clientes`. UF e
// resolvida via TGFPAR.CODCID -> TSICID.UF (codigo numerico) -> TSIUFS.UF
// (sigla), mesmo join ja usado em tax_rules. CLASSIFICMS ("Classificacao
// ICMS" no cadastro de parceiros do Sankhya) tem 6 opcoes na tela (Revendedor,
// Produtor Rural, Consumidor Final Nao Contribuinte, Usar a da TOP, Isento de
// ICMS, Consumidor Final Contribuinte). Letras confirmadas empiricamente
// 2026-10-27 alterando o mesmo cliente de teste (191, CODPARC com IE valida)
// entre as 6 opcoes na tela do Sankhya e conferindo `erpClassificmsRaw` apos
// cada resync: R=Revendedor (contribuinte), P=Produtor Rural (contribuinte),
// T=Usar a da TOP (sem classificacao fixa, cai no fallback por IE), C=
// Consumidor Final NAO Contribuinte (a letra sugere o contrario, mas foi
// confirmado pela tela do Sankhya para o cliente 1887, IE nula), X=
// Consumidor Final Contribuinte (a letra 'C' ja estava ocupada por outra
// opcao, entao o Sankhya usa 'X' aqui). I=Isento de ICMS (nao contribuinte,
// validado com o cliente 1231, IE nula). 'N' nunca foi observado neste tenant
// (nao ha clientes produtor/consumidor final nao-PJ com essa letra), mas
// mantido no set nao_contribuinte por seguranca caso apareca futuramente -
// nao deve ser confundido com 'C', que e a letra realmente usada para o caso
// "Nao Contribuinte" nesta instalacao. Qualquer codigo nao mapeado
// (null/T/desconhecido) cai no fallback por Inscricao Estadual valida.
// taxRegime nao tem coluna correspondente em TGFPAR e permanece com o valor
// existente/manual.
const SANKHYA_CLASSIFICMS_CONTRIBUINTE_CODES = new Set(['R', 'P', 'X']);
const SANKHYA_CLASSIFICMS_NAO_CONTRIBUINTE_CODES = new Set(['C', 'I', 'N']);

function buildSankhyaClientesSql({ codigosFiltro } = {}) {
  const safeCodes = normalizeSankhyaNumericCodeList(codigosFiltro ?? []);
  const filtroCodigo =
    safeCodes.length > 0 ? `\n  AND PAR.CODPARC IN (${safeCodes.join(', ')})` : '';

  return `
SELECT
    TO_CHAR(PAR.CODPARC) AS CODPARC,
    PAR.NOMEPARC,
    PAR.RAZAOSOCIAL,
    PAR.CGC_CPF,
    PAR.TIPPESSOA,
    PAR.ATIVO,
    PAR.IDENTINSCESTAD,
    PAR.INSCMUN,
    PAR.CLASSIFICMS,
    PAR.CEP,
    PAR.NUMEND,
    PAR.COMPLEMENTO,
    PAR.TELEFONE,
    PAR.EMAIL,
    CID.NOMECID,
    UFS.UF AS SIGLA_UF
FROM TGFPAR PAR
LEFT JOIN TSICID CID ON CID.CODCID = PAR.CODCID
LEFT JOIN TSIUFS UFS ON UFS.CODUF = CID.UF
WHERE PAR.CLIENTE = 'S'${filtroCodigo}
`;
}

function mapSankhyaClienteRow({
  tenantId,
  row,
  nowIso,
  syncBatchId,
  syncVersion,
  existingData,
}) {
  const existing = existingData || {};
  const codigo = toCodeString(readRowValueByAliases(row, ['CODPARC']));
  if (!codigo || isZeroCode(codigo)) {
    return null;
  }

  const razaoSocial = String(
    readRowValueByAliases(row, ['RAZAOSOCIAL']) ?? '',
  ).trim();
  const nomeFantasia = String(
    readRowValueByAliases(row, ['NOMEPARC']) ?? '',
  ).trim();
  const documento = normalizeDigits(readRowValueByAliases(row, ['CGC_CPF']));
  const tipPessoaRaw = String(readRowValueByAliases(row, ['TIPPESSOA']) ?? '')
    .trim()
    .toUpperCase();
  const ativoRaw = String(readRowValueByAliases(row, ['ATIVO']) ?? '')
    .trim()
    .toUpperCase();
  const inscricaoEstadualRaw = String(
    readRowValueByAliases(row, ['IDENTINSCESTAD']) ?? '',
  ).trim();
  const classificmsRaw =
    nullableString(readRowValueByAliases(row, ['CLASSIFICMS']))?.toUpperCase() ??
    null;
  const inscricaoEstadualUpper = inscricaoEstadualRaw.toUpperCase();
  const hasValidIe =
    inscricaoEstadualUpper.length > 0 && inscricaoEstadualUpper !== 'ISENTO';

  let taxProfile;
  if (SANKHYA_CLASSIFICMS_CONTRIBUINTE_CODES.has(classificmsRaw)) {
    taxProfile = 'contribuinte';
  } else if (SANKHYA_CLASSIFICMS_NAO_CONTRIBUINTE_CODES.has(classificmsRaw)) {
    taxProfile = 'nao_contribuinte';
  } else {
    taxProfile = hasValidIe ? 'contribuinte' : 'nao_contribuinte';
  }

  let salePurposeFromClassificms = null;
  if (classificmsRaw === 'R') {
    salePurposeFromClassificms = 'revenda';
  } else if (
    classificmsRaw === 'C' ||
    classificmsRaw === 'N' ||
    classificmsRaw === 'X'
  ) {
    salePurposeFromClassificms = 'uso_consumo';
  }

  return {
    id: buildClienteDocId(tenantId, codigo),
    tenantId,
    representedCompanyId: existing.representedCompanyId ?? null,
    ownerId: existing.ownerId ?? null,
    gerenteId: existing.gerenteId ?? null,
    representanteId: existing.representanteId ?? null,
    vendedorId: existing.vendedorId ?? null,
    nome: razaoSocial || nomeFantasia || `Cliente ${codigo}`,
    nomeFantasia: nullableString(nomeFantasia),
    documento: nullableString(documento),
    tipoPessoa: tipPessoaRaw === 'F' ? 'pf' : 'pj',
    cep: nullableString(normalizeDigits(readRowValueByAliases(row, ['CEP']))),
    numero: nullableString(readRowValueByAliases(row, ['NUMEND'])),
    complemento: nullableString(readRowValueByAliases(row, ['COMPLEMENTO'])),
    cidade: nullableString(readRowValueByAliases(row, ['NOMECID'])),
    estado: nullableString(
      String(readRowValueByAliases(row, ['SIGLA_UF']) ?? '')
        .trim()
        .toUpperCase(),
    ),
    logradouro: existing.logradouro ?? null,
    bairro: existing.bairro ?? null,
    telefone: nullableString(readRowValueByAliases(row, ['TELEFONE'])),
    email: nullableString(readRowValueByAliases(row, ['EMAIL'])),
    inscricaoEstadual: nullableString(inscricaoEstadualRaw),
    inscricaoMunicipal: nullableString(
      readRowValueByAliases(row, ['INSCMUN']),
    ),
    taxProfile,
    taxRegime: existing.taxRegime || SANKHYA_DEFAULT_TAX_REGIME,
    isZfmSuframa: existing.isZfmSuframa ?? false,
    salePurpose: salePurposeFromClassificms || existing.salePurpose || 'revenda',
    origemCadastro: 'erp',
    // Sankhya e a fonte da verdade quando a integracao esta ativa: um cliente
    // ativo no ERP e gravado direto como 'aprovado' (nao 'sincronizado'), sem
    // exigir aprovacao manual no app - do contrario ele nunca aparece no
    // seletor de cliente da tela de pedido, que so lista status 'aprovado'.
    status: ativoRaw === 'S' ? 'aprovado' : 'inativo',
    erpClassificmsRaw: classificmsRaw,
    erpSyncId: syncBatchId,
    createdAt: existing.createdAt || nowIso,
    updatedAt: nowIso,
    deletedAt: null,
    syncVersion,
  };
}

// Mesma API publica (BrasilAPI) ja usada no app Flutter para preencher
// logradouro/bairro a partir do CEP (ver cliente_pre_cadastro_page.dart). Nao
// e relevante para o calculo fiscal, so para completar o cadastro de
// endereco; falhas sao toleradas silenciosamente (o campo so fica vazio).
async function lookupCepAddress(cep) {
  try {
    const response = await fetch(`https://brasilapi.com.br/api/cep/v2/${cep}`);
    if (!response.ok) {
      return null;
    }
    const data = await response.json();
    return {
      logradouro: nullableString(data?.street),
      bairro: nullableString(data?.neighborhood),
    };
  } catch (error) {
    console.error(
      '[lookupCepAddress] failed',
      JSON.stringify({ cep, message: error?.message }),
    );
    return null;
  }
}

async function syncSankhyaClientesModule({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
  codigosFiltro,
}) {
  const nowIso = new Date().toISOString();
  const syncBatchId = `sankhya_clientes_${Date.now()}`;
  const sql = buildSankhyaClientesSql({ codigosFiltro });
  const queryResult = await executeSankhyaDbExplorerQuery({
    baseUrl,
    bearerToken,
    xToken,
    sql,
  });

  const clientesCollection = firestore.collection('clientes');
  const writer = firestore.bulkWriter();
  writer.onWriteError((error) => {
    if (error.failedAttempts < 3) {
      return true;
    }
    console.error(
      '[syncSankhyaClientesModule] write_failed',
      JSON.stringify({
        code: error.code,
        message: error.message,
        documentPath: error.documentRef?.path || null,
        failedAttempts: error.failedAttempts,
      }),
    );
    return false;
  });

  const syncVersionBase = Date.now() * 1000;
  let importedCount = 0;
  let skippedInvalidCount = 0;
  let prunedInactiveCount = 0;
  const cepCache = new Map();
  const mappedClienteIds = new Set();
  const isFullSync = !codigosFiltro || codigosFiltro.length === 0;

  try {
    for (let index = 0; index < queryResult.rows.length; index++) {
      const row = queryResult.rows[index];
      const docId = buildClienteDocId(
        tenantId,
        readRowValueByAliases(row, ['CODPARC']),
      );
      const ref = clientesCollection.doc(docId);
      const existingSnapshot = await ref.get();
      const existingData = existingSnapshot.exists
        ? existingSnapshot.data() || {}
        : {};

      const mapped = mapSankhyaClienteRow({
        tenantId,
        row,
        nowIso,
        syncBatchId,
        syncVersion: syncVersionBase + index,
        existingData,
      });

      if (!mapped) {
        skippedInvalidCount += 1;
        continue;
      }

      if (mapped.cep && !mapped.logradouro) {
        if (!cepCache.has(mapped.cep)) {
          cepCache.set(mapped.cep, await lookupCepAddress(mapped.cep));
        }
        const cepInfo = cepCache.get(mapped.cep);
        if (cepInfo) {
          mapped.logradouro = mapped.logradouro || cepInfo.logradouro;
          mapped.bairro = mapped.bairro || cepInfo.bairro;
        }
      }

      writer.set(ref, mapped, { merge: true });
      mappedClienteIds.add(docId);
      importedCount += 1;
    }

    // Prune: so roda em sync completo (sem codigosFiltro), nunca em teste
    // restrito a poucos codigos - do contrario qualquer cliente ERP fora do
    // filtro de teste seria incorretamente marcado como inativo. Clientes ERP
    // que deixaram de aparecer na consulta completa do Sankhya sao apenas
    // marcados como 'inativo' no Firestore (soft, nunca excluidos), pois
    // Sankhya e a fonte da verdade de quem esta ativo/existe no ERP.
    if (isFullSync) {
      const existingErpSnapshot = await clientesCollection
        .where('tenantId', '==', tenantId)
        .where('origemCadastro', '==', 'erp')
        .get();
      for (const doc of existingErpSnapshot.docs) {
        if (mappedClienteIds.has(doc.id)) {
          continue;
        }
        const payload = doc.data() || {};
        if (payload.status === 'inativo') {
          continue;
        }
        writer.set(
          doc.ref,
          { status: 'inativo', updatedAt: nowIso },
          { merge: true },
        );
        prunedInactiveCount += 1;
      }
    }
  } finally {
    await writer.close();
  }

  await updateTenantSyncState({
    firestore,
    tenantId,
    patch: {
      lastClientesSyncAt: nowIso,
      lastClientesSyncMode: codigosFiltro?.length ? 'test_filtered' : 'full',
      lastClientesSourceCount: queryResult.rows.length,
      lastClientesImportedCount: importedCount,
      lastClientesSkippedInvalidCount: skippedInvalidCount,
      lastClientesPrunedInactiveCount: prunedInactiveCount,
      lastClientesEndpoint: queryResult.endpointPath,
    },
  });

  return {
    message: codigosFiltro?.length
      ? `Sincronizacao de teste de clientes concluida (restrita aos codigos: ${codigosFiltro.join(', ')}).`
      : 'Sincronizacao completa de clientes concluida via SQL DbExplorer.',
    endpoint: queryResult.endpointPath,
    sourceCount: queryResult.rows.length,
    importedCount,
    skippedInvalidCount,
    prunedInactiveCount,
    codigosFiltro: codigosFiltro ?? [],
  };
}

function buildSankhyaTaxRulesSql() {
  return `
SELECT DISTINCT
    'active' AS STATUS,
    CASE
        WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('N', '4', 'H')
             AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
            THEN NCM1.CODNCM
        WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('N', '4', 'H')
             AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
            THEN NCM2.CODNCM
        WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
             AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO1.NCM
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('P', '1')
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO2.NCM
    WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'I'
       AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO_GI1.NCM
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'I'
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO_GI2.NCM
    WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'K'
       AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO_GK1.NCM
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'K'
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO_GK2.NCM
        ELSE NULL
    END AS NCM,
  CASE
    WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
       AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO1.CODESPECST
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('P', '1')
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO2.CODESPECST
    WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'I'
       AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO_GI1.CODESPECST
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'I'
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO_GI2.CODESPECST
    WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'K'
       AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO_GK1.CODESPECST
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'K'
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO_GK2.CODESPECST
    ELSE NULL
  END AS CEST,
    NVL(UFO.UF, 'ANY') AS UFORIGEM,
    NVL(UFD.UF, 'ANY') AS UFDESTINO,
    CASE
        WHEN NVL(TRIM(TO_CHAR(ICM.PAUTAVLRSTFIXO)), 'N') NOT IN ('0', '0,0', '0,00', '0.0', '0.00', 'N') THEN 'pmc'
        ELSE 'mva'
    END AS TIPOST,
    TO_CHAR(NULL) AS PRECOPARACALCULOST,
    CASE
        WHEN NVL(TRIM(TO_CHAR(ICM.REDBASEST)), 'N') = 'N' THEN '0'
        ELSE TO_CHAR(ICM.REDBASEST)
    END AS REDUCAOBASEICMSST,
    CASE
        WHEN NVL(TRIM(TO_CHAR(ICM.PAUTAVLRSTFIXO)), 'N') = 'N' THEN '0'
        ELSE TO_CHAR(ICM.PAUTAVLRSTFIXO)
    END AS BASECALCULOICMSST,
    CASE
        WHEN NVL(TRIM(TO_CHAR(ICM.ALIQSUBTRIB)), 'N') <> 'N' THEN TO_CHAR(ICM.ALIQSUBTRIB)
        WHEN NVL(TRIM(TO_CHAR(ICM.ALIQINTDEST)), 'N') <> 'N' THEN TO_CHAR(ICM.ALIQINTDEST)
        WHEN NVL(TRIM(TO_CHAR(ICM.ALIQUOTA)), 'N') <> 'N' THEN TO_CHAR(ICM.ALIQUOTA)
        ELSE '0'
    END AS ALIQUOTADESTINO,
    CASE
        WHEN NVL(TRIM(TO_CHAR(ICM.ALIQUOTA)), 'N') <> 'N' THEN TO_CHAR(ICM.ALIQUOTA)
        WHEN NVL(TRIM(TO_CHAR(ICM.ALIQINTDEST)), 'N') <> 'N' THEN TO_CHAR(ICM.ALIQINTDEST)
        ELSE '0'
    END AS ALIQUOTACREDITO,
    CASE
        WHEN NVL(ICM.ALIQINTDEST, 0) > 0
             AND UFO.UF IS NOT NULL
             AND UFD.UF IS NOT NULL
             AND UFO.UF <> UFD.UF
            THEN TO_CHAR(GREATEST(ICM.ALIQINTDEST - NVL(ICM.ALIQUOTA, 0), 0))
        ELSE TO_CHAR(NULL)
    END AS ALIQUOTADIFAL,
    TO_CHAR(ICM.PERCICMSFCPINT) AS PERCFCPINTERNO,
    TO_CHAR(ICM.PERCICMSFCP) AS PERCFCPGERAL,
    TO_CHAR(ICM.PERCSTFCPINT) AS PERCSTFCPINTERNO,
    TO_CHAR(ICM.CSOSN) AS CST_CSOSN,
    CASE
      WHEN NVL(TRIM(TO_CHAR(ICM.MARGLUCRO)), 'N') NOT IN ('N', '0', '0,0', '0,00', '0.0', '0.00') THEN TO_CHAR(ICM.MARGLUCRO)
      WHEN NVL(TRIM(TO_CHAR(ICM.MVASTUFDEST)), 'N') NOT IN ('N', '0', '0,0', '0,00', '0.0', '0.00') THEN TO_CHAR(ICM.MVASTUFDEST)
      WHEN NVL(TRIM(TO_CHAR(ICM.MARGLUCROEST)), 'N') NOT IN ('N', '0', '0,0', '0,00', '0.0', '0.00') THEN TO_CHAR(ICM.MARGLUCROEST)
      ELSE '0'
    END AS MVA,
    (
        'TIPRESTRICAO=' || NVL(TO_CHAR(ICM.TIPRESTRICAO), '-') ||
        ';CODRESTRICAO=' || NVL(TO_CHAR(ICM.CODRESTRICAO), '-') ||
        ';TIPRESTRICAO2=' || NVL(TO_CHAR(ICM.TIPRESTRICAO2), '-') ||
        ';CODRESTRICAO2=' || NVL(TO_CHAR(ICM.CODRESTRICAO2), '-') ||
        ';TIPCALCDIFAL=' || NVL(TO_CHAR(ICM.TIPCALCDIFAL), '-')
    ) AS EXCECAOFISCAL,
    ICM.DTINICIOVIGENCIA AS VIGENCIAINICIAL,
    ICM.DTFIMVIGENCIA AS VIGENCIAFINAL,
    TO_CHAR(
        CASE
            WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
                 AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
                THEN 300000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('N', '4', 'H')
                 AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
                THEN 200000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('N', '4', 'H')
                 AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
                THEN 190000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'I'
             AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
            THEN 180000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'I'
             AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
            THEN 170000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'K'
             AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
            THEN 160000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'K'
             AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
            THEN 150000 + NVL(ICM.SEQUENCIA, 0)
            ELSE 100000 + NVL(ICM.SEQUENCIA, 0)
        END
    ) AS PRIORIDADE,
    TO_CHAR(ICM.CODTRIB) AS GRUPOFISCALID,
    TO_CHAR(ICM.CODTAB) AS CODTAB,
    TO_CHAR(ICM.SEQUENCIA) AS SEQUENCIA,
    TO_CHAR(ICM.IDALIQ) AS IDALIQ
FROM TGFICM ICM
LEFT JOIN TSIUFS UFO
    ON ICM.UFORIG = UFO.CODUF
LEFT JOIN TSIUFS UFD
    ON ICM.UFDEST = UFD.CODUF
LEFT JOIN TGFPRO PRO1
    ON TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
  AND ICM.CODRESTRICAO = PRO1.CODPROD
LEFT JOIN TGFPRO PRO2
   ON TO_CHAR(ICM.TIPRESTRICAO2) IN ('P', '1')
  AND ICM.CODRESTRICAO2 = PRO2.CODPROD
LEFT JOIN TGFPRO PRO_GI1
  ON TO_CHAR(ICM.TIPRESTRICAO) = 'I'
  AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
  AND NVL(PRO_GI1.GRUPOICMS, -1) = NVL(ICM.CODRESTRICAO, -2)
LEFT JOIN TGFPRO PRO_GI2
  ON TO_CHAR(ICM.TIPRESTRICAO2) = 'I'
  AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
  AND NVL(PRO_GI2.GRUPOICMS, -1) = NVL(ICM.CODRESTRICAO2, -2)
LEFT JOIN TGFPRO PRO_GK1
  ON TO_CHAR(ICM.TIPRESTRICAO) = 'K'
  AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
  AND NVL(PRO_GK1.GRUPOICMS2, -1) = NVL(ICM.CODRESTRICAO, -2)
LEFT JOIN TGFPRO PRO_GK2
  ON TO_CHAR(ICM.TIPRESTRICAO2) = 'K'
  AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
  AND NVL(PRO_GK2.GRUPOICMS2, -1) = NVL(ICM.CODRESTRICAO2, -2)
LEFT JOIN TGFNCM NCM1
   ON TO_CHAR(ICM.TIPRESTRICAO) IN ('N', '4', 'H')
   AND LTRIM(TO_CHAR(ICM.CODRESTRICAO), '0') = LTRIM(REPLACE(NCM1.CODNCM, '.', ''), '0')
LEFT JOIN TGFNCM NCM2
   ON TO_CHAR(ICM.TIPRESTRICAO2) IN ('N', '4', 'H')
   AND LTRIM(TO_CHAR(ICM.CODRESTRICAO2), '0') = LTRIM(REPLACE(NCM2.CODNCM, '.', ''), '0')
WHERE
    ICM.DTINICIOVIGENCIA IS NULL
    OR ICM.DTINICIOVIGENCIA <= SYSDATE
ORDER BY
    UFORIGEM,
    UFDESTINO,
    PRIORIDADE DESC,
    NCM,
    CEST
`.trim();
}

function mapSankhyaTaxRuleRow({
  tenantId,
  row,
  nowIso,
  syncBatchId,
  syncVersion,
}) {
  const ncmDigits = normalizeDigits(
    readRowValueByAliases(row, ['NCM']),
  );
  const ufDestino = normalizeTaxRuleUf(
    readRowValueByAliases(row, ['UFDESTINO']),
  );
  if (!ufDestino) {
    return null;
  }

  const ufOrigem =
    normalizeTaxRuleUf(readRowValueByAliases(row, ['UFORIGEM'])) || 'ANY';
  const cestDigits = normalizeDigits(
    readRowValueByAliases(row, ['CEST']),
  );
  const stType = normalizeTaxRuleStType(
    readRowValueByAliases(row, ['TIPOST', 'STCALCULATIONTYPE']),
  );
  const aliquotaDestino = toNumberOrNull(
    readRowValueByAliases(row, ['ALIQUOTADESTINO']),
  );
  const aliquotaCredito = toNumberOrNull(
    readRowValueByAliases(row, ['ALIQUOTACREDITO']),
  );
  const mvaIva = toNumberOrNull(
    readRowValueByAliases(row, [
      'MVA',
      'MARGLUCRO',
      'MVASTUFDEST',
      'MARGLUCROEST',
      'MVAORIGINAL',
      'MVASIMPLIFICADO',
      'IVA_ORIGINAL',
      'IVAORIGINAL',
      'IVA',
    ]),
  );
  const stBaseReductionPercent = toNumberOrNull(
    readRowValueByAliases(row, ['REDUCAOBASEICMSST', 'REDBASEST']),
  );
  const stBaseAmount = toNumberOrNull(
    readRowValueByAliases(row, ['BASECALCULOICMSST', 'PAUTAVLRSTFIXO']),
  );
  const aliquotaDifalValue = toNumberOrNull(
    readRowValueByAliases(row, ['ALIQUOTADIFAL']),
  );
  const aliquotaFcpValue =
    toNumberOrNull(readRowValueByAliases(row, ['PERCFCPINTERNO'])) ??
    toNumberOrNull(readRowValueByAliases(row, ['PERCFCPGERAL']));
  const aliquotaFcpStValue = toNumberOrNull(
    readRowValueByAliases(row, ['PERCSTFCPINTERNO']),
  );

  // Linhas de excecao por NCM/produto/grupo que nao carregam NENHUM valor
  // fiscal real (todos os campos numericos zerados/nulos) sao descartadas:
  // no Sankhya elas so existem para fins de CST/CSOSN/CEST e, se importadas
  // como regra por NCM (tier 2), mascarariam com 0% a regra generica por UF
  // (tier 3) que e quem realmente carrega a aliquota. A regra generica (sem
  // NCM) nunca e descartada por este filtro.
  if (ncmDigits) {
    const hasRealValue = [
      aliquotaDestino,
      aliquotaCredito,
      mvaIva,
      stBaseReductionPercent,
      stBaseAmount,
      aliquotaDifalValue,
      aliquotaFcpValue,
      aliquotaFcpStValue,
    ].some((value) => (value ?? 0) > 0);
    if (!hasRealValue) {
      return null;
    }
  }

  const codTab = sanitizeKeyToken(readRowValueByAliases(row, ['CODTAB']), '-');
  const sequencia = sanitizeKeyToken(
    readRowValueByAliases(row, ['SEQUENCIA']),
    '-',
  );
  const idAliq = sanitizeKeyToken(readRowValueByAliases(row, ['IDALIQ']), '-');

  const identityParts = [
    codTab,
    sequencia,
    idAliq,
    sanitizeKeyToken(ufOrigem, 'ANY'),
    sanitizeKeyToken(ufDestino, 'ANY'),
    sanitizeKeyToken(ncmDigits || 'ANY', 'ANY'),
    sanitizeKeyToken(cestDigits || 'ANY', 'ANY'),
  ];

  const id = `erp_tax_${tenantId}_${identityParts.join('_')}`;

  return {
    id,
    tenantId,
    representedCompanyId: null,
    status: normalizeTaxRuleStatus(
      readRowValueByAliases(row, ['STATUS']),
    ),
    ncm: ncmDigits ? formatNcmMasked(ncmDigits) : null,
    cest: cestDigits ? formatCestMasked(cestDigits) : null,
    fiscalException: nullableString(
      readRowValueByAliases(row, ['EXCECAOFISCAL', 'FISCALEXCEPTION']),
    ),
    stCalculationType: stType,
    stPriceForCalculation: toNumberOrNull(
      readRowValueByAliases(row, ['PRECOPARACALCULOST', 'STPRICEFORCALCULATION']),
    ),
    stBaseReductionPercent,
    stBaseAmount,
    aliquotaDestino,
    aliquotaCredito,
    grupoFiscalId: nullableString(
      readRowValueByAliases(row, ['GRUPOFISCALID', 'CODTRIB']),
    ),
    salePurpose: null,
    ufOrigem,
    ufDestino,
    cstCsosn: nullableString(
      readRowValueByAliases(row, ['CST_CSOSN', 'CSTCSOSN']),
    ),
    aliquotaIcms: aliquotaCredito,
    mvaIva,
    aliquotaSt: aliquotaDestino,
    aliquotaDifal: aliquotaDifalValue,
    aliquotaFcp: aliquotaFcpValue,
    aliquotaFcpSt: aliquotaFcpStValue,
    priority: readInt(readRowValueByAliases(row, ['PRIORIDADE'])),
    validFrom: toIsoDateOrNull(
      readRowValueByAliases(row, ['VIGENCIAINICIAL', 'VALIDFROM']),
      false,
    ),
    validUntil: toIsoDateOrNull(
      readRowValueByAliases(row, ['VIGENCIAFINAL', 'VALIDUNTIL']),
      true,
    ),
    origin: 'erp',
    erpSyncId: syncBatchId,
    syncVersion,
    deletedAt: null,
    createdAt: nowIso,
    updatedAt: nowIso,
  };
}

// --- Agrupamento inteligente de regras fiscais (Grupo Tributario automatico) ---
//
// Objetivo: NCMs que, na pratica, tem exatamente o mesmo "perfil fiscal"
// (mesma aliquota interna/interestadual, MVA, reducao de base, CST/CSOSN,
// FCP etc. em cada par de UF) sao agrupados automaticamente em um unico
// `tax_rule_groups` + um unico conjunto de `tax_rules` por grupo, em vez de
// uma regra por NCM. Isso evita a explosao de regras quase-identicas e
// aproxima o cadastro do que o usuario faria manualmente ao analisar uma
// planilha de produtos (varios NCMs com o mesmo tratamento fiscal).
function roundForFingerprint(value) {
  const numeric = Number(value ?? 0);
  if (!Number.isFinite(numeric)) {
    return 0;
  }
  return Math.round(numeric * 10000) / 10000;
}

function buildTaxFingerprintKey(vectorRows) {
  const parts = vectorRows
    .map((row) =>
      [
        row.ufOrigem,
        row.ufDestino,
        roundForFingerprint(row.aliquotaDestino),
        roundForFingerprint(row.aliquotaCredito),
        roundForFingerprint(row.aliquotaDifal),
        roundForFingerprint(row.mvaIva),
        roundForFingerprint(row.stBaseReductionPercent),
        roundForFingerprint(row.stBaseAmount),
        row.stCalculationType || 'mva',
        row.cstCsosn || '',
        roundForFingerprint(row.aliquotaFcp),
        roundForFingerprint(row.aliquotaFcpSt),
      ].join('|'),
    )
    .sort();
  return parts.join('#');
}

function computeFingerprintHash(key) {
  return crypto.createHash('sha1').update(key).digest('hex').slice(0, 16);
}

function buildAutoGroupName(vectorRows, memberCount) {
  const representative =
    vectorRows.find((row) => (row.aliquotaDestino ?? 0) > 0) || vectorRows[0];
  const icms = roundForFingerprint(representative?.aliquotaDestino);
  const mva = roundForFingerprint(representative?.mvaIva);
  const parts = [`ICMS ${icms}%`];
  if (mva > 0) {
    parts.push(`MVA ${mva}%`);
  }
  return `Grupo Fiscal ERP (${parts.join(' / ')}) - ${memberCount} NCMs`;
}

function buildAutoGroupDescription(vectorRows, memberNcms) {
  const sampleNcms = memberNcms
    .slice(0, 8)
    .map((digits) => formatNcmMasked(digits))
    .join(', ');
  const suffix = memberNcms.length > 8 ? '...' : '';
  const ufCount = new Set(vectorRows.map((row) => row.ufDestino)).size;
  return `Grupo criado automaticamente na sincronizacao com o ERP (Sankhya), agrupando ${memberNcms.length} NCMs com identico tratamento fiscal em ${ufCount} UF(s) de destino. NCMs: ${sampleNcms}${suffix}`;
}

async function applyTaxGroupsToExistingProducts({
  firestore,
  tenantId,
  ncmToGroupId,
}) {
  const snapshot = await firestore
    .collection('produtos')
    .where('tenantId', '==', tenantId)
    .select('ncm', 'grupoTributarioId', 'deletedAt')
    .get();

  const writer = firestore.bulkWriter();
  writer.onWriteError((error) => error.failedAttempts < 3);
  let linkedCount = 0;

  try {
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      if (data.deletedAt) {
        continue;
      }
      const ncmDigits = normalizeDigits(data.ncm);
      if (!ncmDigits) {
        continue;
      }
      const groupId = ncmToGroupId.get(ncmDigits);
      if (!groupId || data.grupoTributarioId === groupId) {
        continue;
      }
      writer.set(
        doc.ref,
        { grupoTributarioId: groupId },
        { merge: true },
      );
      linkedCount += 1;
    }
  } finally {
    await writer.close();
  }

  return linkedCount;
}

function normalizeTaxRuleUf(value) {
  const token = String(value ?? '').trim().toUpperCase();
  if (!token) {
    return 'ANY';
  }
  if (token === 'ANY' || token === 'TODOS' || token === 'TODAS') {
    return 'ANY';
  }
  if (/^[A-Z]{2}$/.test(token)) {
    return token;
  }
  return 'ANY';
}

function normalizeTaxRuleStType(value) {
  const token = String(value ?? '').trim().toLowerCase();
  if (token === 'pmc') {
    return 'pmc';
  }
  return 'mva';
}

function normalizeTaxRuleStatus(value) {
  const token = String(value ?? '').trim().toLowerCase();
  if (
    token === 'inactive' ||
    token === 'inativo' ||
    token === 'desativado'
  ) {
    return 'inactive';
  }
  return 'active';
}

function normalizeDigits(value) {
  const token = String(value ?? '').trim();
  if (!token) {
    return '';
  }
  return token.replace(/[^0-9]/g, '');
}

function formatNcmMasked(digits) {
  const raw = String(digits ?? '').replace(/[^0-9]/g, '');
  if (!raw) {
    return '';
  }
  const normalized = raw.padStart(8, '0');
  return `${normalized.slice(0, 4)}.${normalized.slice(4, 6)}.${normalized.slice(6, 8)}`;
}

function formatCestMasked(digits) {
  const raw = String(digits ?? '').replace(/[^0-9]/g, '');
  if (!raw) {
    return '';
  }
  const normalized = raw.padStart(7, '0');
  return `${normalized.slice(0, 2)}.${normalized.slice(2, 5)}.${normalized.slice(5, 7)}`;
}

function nullableString(value) {
  const token = String(value ?? '').trim();
  return token ? token : null;
}

function sanitizeKeyToken(value, fallback) {
  const token = String(value ?? '').trim();
  if (!token) {
    return fallback;
  }
  const normalized = token
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^A-Za-z0-9_-]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return normalized || fallback;
}

function toIsoDateOrNull(value, endOfDay) {
  if (value === null || value === undefined || value === '') {
    return null;
  }

  if (value instanceof Date) {
    const utc = new Date(value);
    if (endOfDay) {
      utc.setUTCHours(23, 59, 59, 999);
    } else {
      utc.setUTCHours(0, 0, 0, 0);
    }
    return utc.toISOString();
  }

  const text = String(value).trim();
  if (!text) {
    return null;
  }

  const direct = new Date(text);
  if (!Number.isNaN(direct.getTime())) {
    if (endOfDay) {
      direct.setUTCHours(23, 59, 59, 999);
    } else {
      direct.setUTCHours(0, 0, 0, 0);
    }
    return direct.toISOString();
  }

  const br = /^(\d{2})\/(\d{2})\/(\d{4})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?$/.exec(text);
  if (br) {
    const day = Number.parseInt(br[1], 10);
    const month = Number.parseInt(br[2], 10) - 1;
    const year = Number.parseInt(br[3], 10);
    const date = new Date(Date.UTC(year, month, day, 0, 0, 0, 0));
    if (Number.isNaN(date.getTime())) {
      return null;
    }
    if (endOfDay) {
      date.setUTCHours(23, 59, 59, 999);
    }
    return date.toISOString();
  }

  return null;
}

async function syncSankhyaProductImagesModule({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
}) {
  const sourceUrl = `${baseUrl}${SANKHYA_PRODUCTS_PATH}`;
  const sankhyaResponse = await fetch(sourceUrl, {
    method: 'GET',
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${bearerToken}`,
      'x-token': xToken,
    },
    signal: AbortSignal.timeout(30000),
  });

  const sourceText = await sankhyaResponse.text();
  if (sankhyaResponse.status !== 200) {
    throw new Error(
      `Falha ao consultar modulo produtos para sync de imagens (HTTP ${sankhyaResponse.status}): ${sourceText.slice(0, 300)}`,
    );
  }

  const sourceData = tryParseJson(sourceText);
  const sourceProducts = Array.isArray(sourceData?.produtos)
    ? sourceData.produtos
    : [];

  const validProducts = [];
  let filteredOutZeroCodeCount = 0;
  for (const rawItem of sourceProducts) {
    if (!rawItem || typeof rawItem !== 'object') {
      continue;
    }

    const productCode = toCodeString(rawItem.codigoProduto);
    if (!productCode || isZeroCode(productCode)) {
      filteredOutZeroCodeCount += 1;
      continue;
    }

    validProducts.push(rawItem);
    if (validProducts.length >= TEMPORARY_IMPORT_LIMIT) {
      break;
    }
  }

  const validProductCodes = validProducts
    .map((item) => toCodeString(item?.codigoProduto))
    .filter((item) => item && !isZeroCode(item));

  if (validProductCodes.length === 0) {
    return {
      message:
        'Nenhum produto valido foi encontrado no lote temporario para sincronizacao de imagens.',
      endpoint: SANKHYA_PRODUCTS_PATH,
      sourceStatus: sankhyaResponse.status,
      sourceCount: sourceProducts.length,
      importedCount: 0,
      filteredOutZeroCodeCount,
      skippedNotFoundCount: 0,
      appliedLimit: TEMPORARY_IMPORT_LIMIT,
    };
  }

  const imageSql = buildSankhyaProductImageChunksSql(validProductCodes);
  const queryResult = await executeSankhyaDbExplorerQuery({
    baseUrl,
    bearerToken,
    xToken,
    sql: imageSql,
  });

  const chunksByProduct = new Map();
  for (const row of queryResult.rows) {
    const productCode = toCodeString(
      readRowValueByAliases(row, ['CodigoProduto', 'CODPROD']),
    );
    if (!productCode) {
      continue;
    }

    const chunkIndex =
      readInt(readRowValueByAliases(row, ['ChunkIndex', 'CHUNKINDEX'])) || 0;
    const chunkHex = String(
      readRowValueByAliases(row, ['ChunkHex', 'CHUNKHEX']) ?? '',
    )
      .trim()
      .toUpperCase();

    if (!chunkHex) {
      continue;
    }

    const productChunks = chunksByProduct.get(productCode) || [];
    productChunks.push({ chunkIndex, chunkHex });
    chunksByProduct.set(productCode, productChunks);
  }

  const imageByProductCode = new Map();
  for (const [productCode, chunks] of chunksByProduct.entries()) {
    chunks.sort((left, right) => left.chunkIndex - right.chunkIndex);
    const mergedHex = chunks.map((item) => item.chunkHex).join('');
    if (!mergedHex) {
      continue;
    }

    const imageBuffer = Buffer.from(mergedHex, 'hex');
    if (!imageBuffer || imageBuffer.length === 0) {
      continue;
    }

    const imageHash = crypto
      .createHash('sha256')
      .update(imageBuffer)
      .digest('hex');
    imageByProductCode.set(productCode, {
      imageBuffer,
      imageHash,
    });
  }

  const nowIso = new Date().toISOString();
  const syncBatchId = `sankhya_img_${Date.now()}`;
  const productsCollection = firestore.collection('produtos');
  const mediaCollection = firestore.collection('product_media_assets');

  const existingAssetsSnapshot = await mediaCollection
    .where('tenantId', '==', tenantId)
    .get();
  const existingAssetByHash = new Map();
  for (const doc of existingAssetsSnapshot.docs) {
    const data = doc.data() || {};
    const scopeKey = String(data.scopeKey ?? '').trim();
    const imageHash = String(data.imageHash ?? '').trim().toLowerCase();
    if (
      scopeKey !== DEFAULT_PRODUCT_MEDIA_SCOPE_KEY ||
      !imageHash ||
      !data.downloadUrl ||
      !data.storagePath
    ) {
      continue;
    }
    existingAssetByHash.set(imageHash, {
      assetId: doc.id,
      downloadUrl: String(data.downloadUrl ?? '').trim(),
      storagePath: String(data.storagePath ?? '').trim(),
      thumbnailBase64: String(data.thumbnailBase64 ?? '').trim(),
    });
  }

  const uploadedAssetByHash = new Map();
  const bucketName =
    process.env.FIREBASE_STORAGE_BUCKET ||
    process.env.GCLOUD_STORAGE_BUCKET ||
    DEFAULT_STORAGE_BUCKET;
  const bucket = admin.storage().bucket(bucketName);

  let sourceCount = validProductCodes.length;
  let importedCount = 0;
  let skippedNotFoundCount = 0;
  let productsWithoutImageCount = 0;
  let reusedWithinBatchCount = 0;
  let reusedExistingAssetCount = 0;
  let uploadedAssetCount = 0;
  let alreadyUpToDateCount = 0;

  for (const productCode of validProductCodes) {
    const docId = buildProductDocId(tenantId, productCode);
    const docRef = productsCollection.doc(docId);
    const existingDoc = await docRef.get();
    if (!existingDoc.exists) {
      skippedNotFoundCount += 1;
      continue;
    }

    const existingData = existingDoc.data() || {};
    const imageData = imageByProductCode.get(productCode);
    if (!imageData) {
      productsWithoutImageCount += 1;
      continue;
    }

    const { imageBuffer, imageHash } = imageData;
    const normalizedHash = String(imageHash).trim().toLowerCase();
    let resolvedAsset = uploadedAssetByHash.get(normalizedHash);

    if (!resolvedAsset) {
      const existingAsset = existingAssetByHash.get(normalizedHash);
      if (existingAsset) {
        resolvedAsset = existingAsset;
        uploadedAssetByHash.set(normalizedHash, resolvedAsset);
        reusedExistingAssetCount += 1;
      }
    } else {
      reusedWithinBatchCount += 1;
    }

    if (!resolvedAsset) {
      const imageFormat = detectImageFormat(imageBuffer);
      const extension = imageFormat === 'png' ? 'png' : 'jpg';
      const contentType = imageFormat === 'png' ? 'image/png' : 'image/jpeg';
      const thumbnailBase64 = imageBuffer.toString('base64');

      const assetId = `erp_pma_${tenantId}_${normalizedHash.slice(0, 24)}`;
      const storagePath =
        `tenants/${tenantId}/product_media/${DEFAULT_PRODUCT_MEDIA_SCOPE_KEY}/erp_sync/${assetId}.${extension}`;
      const downloadToken = crypto.randomUUID();
      const file = bucket.file(storagePath);

      await file.save(imageBuffer, {
        resumable: false,
        metadata: {
          contentType,
          metadata: {
            firebaseStorageDownloadTokens: downloadToken,
            origin: 'erp-sync-product-images',
            scopeKey: DEFAULT_PRODUCT_MEDIA_SCOPE_KEY,
            imageHash: normalizedHash,
            erpProvider: 'sankhya',
          },
        },
      });

      const downloadUrl = buildFirebaseDownloadUrl({
        bucketName,
        storagePath,
        token: downloadToken,
      });

      await mediaCollection.doc(assetId).set(
        {
          id: assetId,
          tenantId,
          representedCompanyId: null,
          scopeKey: DEFAULT_PRODUCT_MEDIA_SCOPE_KEY,
          fileName: `${assetId}.${extension}`,
          downloadUrl,
          storagePath,
          thumbnailBase64,
          width: 500,
          height: 500,
          imageHash: normalizedHash,
          source: 'erp_sync',
          erpProvider: 'sankhya',
          erpSyncId: syncBatchId,
          createdAt: existingDoc.createTime
            ? admin.firestore.Timestamp.fromDate(
                new Date(existingDoc.createTime.toDate()),
              )
            : admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      resolvedAsset = {
        assetId,
        downloadUrl,
        storagePath,
        thumbnailBase64,
      };
      uploadedAssetByHash.set(normalizedHash, resolvedAsset);
      existingAssetByHash.set(normalizedHash, resolvedAsset);
      uploadedAssetCount += 1;
    }

    if (!resolvedAsset) {
      continue;
    }

    const existingPhotoUrl = String(existingData.fotoUrl ?? '').trim();
    const existingStoragePath = String(existingData.storagePath ?? '').trim();
    const existingThumb = String(existingData.thumbnailBase64 ?? '').trim();
    const isAlreadyLinked =
      existingPhotoUrl === resolvedAsset.downloadUrl &&
      existingStoragePath === resolvedAsset.storagePath &&
      existingThumb.length > 0;

    if (isAlreadyLinked) {
      alreadyUpToDateCount += 1;
      continue;
    }

    const nextSyncVersion = readInt(existingData.syncVersion) + 1;
    await docRef.set(
      {
        fotoUrl: resolvedAsset.downloadUrl,
        storagePath: resolvedAsset.storagePath,
        thumbnailBase64: resolvedAsset.thumbnailBase64,
        erpSyncId: syncBatchId,
        syncVersion: nextSyncVersion,
        updatedAt: nowIso,
      },
      { merge: true },
    );
    importedCount += 1;
  }

  await updateTenantSyncState({
    firestore,
    tenantId,
    patch: {
      lastProductImagesSyncedAt: nowIso,
      lastProductImagesSyncAt: nowIso,
      lastProductImagesSourceCount: sourceCount,
      lastProductImagesImportedCount: importedCount,
      lastProductImagesFilteredOutZeroCodeCount: filteredOutZeroCodeCount,
      lastProductImagesSkippedNotFoundCount: skippedNotFoundCount,
      lastProductImagesWithoutImageCount: productsWithoutImageCount,
      lastProductImagesUploadedAssetCount: uploadedAssetCount,
      lastProductImagesReusedWithinBatchCount: reusedWithinBatchCount,
      lastProductImagesReusedExistingAssetCount: reusedExistingAssetCount,
      lastProductImagesAlreadyUpToDateCount: alreadyUpToDateCount,
      lastProductImagesAppliedLimit: TEMPORARY_IMPORT_LIMIT,
    },
  });

  return {
    message:
      'Sincronizacao manual de fotos concluida. Imagens repetidas foram deduplicadas e vinculadas aos produtos do lote temporario.',
    endpoint: queryResult.endpointPath,
    sourceStatus: sankhyaResponse.status,
    sourceCount,
    importedCount,
    filteredOutZeroCodeCount,
    skippedNotFoundCount,
    productsWithoutImageCount,
    uploadedAssetCount,
    reusedWithinBatchCount,
    reusedExistingAssetCount,
    alreadyUpToDateCount,
    appliedLimit: TEMPORARY_IMPORT_LIMIT,
  };
}

function buildSankhyaProductImageChunksSql(productCodes) {
  const safeCodes = normalizeSankhyaNumericCodeList(productCodes);
  if (safeCodes.length === 0) {
    return '';
  }

  const chunkSize = SANKHYA_IMAGE_CHUNK_BYTES;
  const codesInClause = safeCodes.join(', ');
  return `
SELECT
    TO_CHAR(P.CODPROD) AS CodigoProduto,
    LEVEL AS ChunkIndex,
    RAWTOHEX(
      DBMS_LOB.SUBSTR(
        P.IMAGEM,
        ${chunkSize},
        ((LEVEL - 1) * ${chunkSize}) + 1
      )
    ) AS ChunkHex
FROM TGFPRO P
WHERE P.CODPROD IN (${codesInClause})
  AND P.ATIVO = 'S'
  AND P.IMAGEM IS NOT NULL
CONNECT BY PRIOR P.CODPROD = P.CODPROD
   AND PRIOR SYS_GUID() IS NOT NULL
   AND LEVEL <= CEIL(DBMS_LOB.GETLENGTH(P.IMAGEM) / ${chunkSize})
ORDER BY P.CODPROD, LEVEL
`.trim();
}

function detectImageFormat(buffer) {
  if (!buffer || buffer.length < 4) {
    return 'jpg';
  }

  if (
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47
  ) {
    return 'png';
  }

  return 'jpg';
}

function buildFirebaseDownloadUrl({ bucketName, storagePath, token }) {
  const encodedPath = encodeURIComponent(storagePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedPath}?alt=media&token=${token}`;
}

async function verifyFirebaseAuthFromRequest(request) {
  const authHeader = String(request.headers?.authorization ?? '').trim();
  if (!authHeader.toLowerCase().startsWith('bearer ')) {
    return {
      ok: false,
      status: 401,
      error: 'missing_firebase_auth',
      message: 'Envie Authorization: Bearer <Firebase ID token>.',
      uid: '',
      email: '',
    };
  }

  const idToken = authHeader.substring(7).trim();
  if (!idToken) {
    return {
      ok: false,
      status: 401,
      error: 'invalid_firebase_auth',
      message: 'Token Firebase invalido ou ausente.',
      uid: '',
      email: '',
    };
  }

  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const uid = String(decodedToken?.uid ?? '').trim();
    if (!uid) {
      return {
        ok: false,
        status: 401,
        error: 'missing_uid',
        message: 'Usuario autenticado sem UID valido.',
        uid: '',
        email: '',
      };
    }

    return {
      ok: true,
      status: 200,
      error: '',
      message: '',
      uid,
      email: String(decodedToken?.email ?? '').trim(),
    };
  } catch (_) {
    return {
      ok: false,
      status: 401,
      error: 'firebase_auth_failed',
      message: 'Falha ao validar autenticacao Firebase.',
      uid: '',
      email: '',
    };
  }
}

function normalizeLaunchOrigin(rawOrigin, request) {
  const directOrigin = String(rawOrigin ?? '').trim();
  if (isValidHttpOrigin(directOrigin)) {
    return stripTrailingSlash(directOrigin);
  }

  const headerOrigin = String(request.headers?.origin ?? '').trim();
  if (isValidHttpOrigin(headerOrigin)) {
    return stripTrailingSlash(headerOrigin);
  }

  const host = String(request.headers?.host ?? '').trim();
  if (!host) {
    return '';
  }

  const protocol =
    String(request.headers?.['x-forwarded-proto'] ?? 'https').trim() ||
    'https';
  return stripTrailingSlash(`${protocol}://${host}`);
}

function isValidHttpOrigin(value) {
  if (!value) {
    return false;
  }
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

function stripTrailingSlash(value) {
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

function resolveRequestIp(request) {
  const forwarded = String(request.headers?.['x-forwarded-for'] ?? '').trim();
  if (forwarded) {
    return forwarded.split(',')[0].trim();
  }

  return String(request.ip ?? request.connection?.remoteAddress ?? '').trim();
}

function sha256Hex(value) {
  return crypto.createHash('sha256').update(String(value ?? '')).digest('hex');
}

function resolveUserDisplayLabel(userData, fallbackEmail, fallbackUid) {
  const preferred = String(
    userData.displayName ?? userData.name ?? userData.nome ?? '',
  ).trim();
  if (preferred) {
    return preferred;
  }

  const email = String(fallbackEmail ?? '').trim();
  if (email) {
    return email;
  }

  return String(fallbackUid ?? '').trim();
}

function assertImpersonationSessionConsumable({ data, sessionKeyHash, nowDate }) {
  const status = String(data.status ?? '').trim().toLowerCase();
  const consumedAt = data.consumedAt ?? null;
  const revokedAt = data.revokedAt ?? null;
  const expiresAt = data.expiresAt;
  const expiresAtDate =
    expiresAt && typeof expiresAt.toDate === 'function'
      ? expiresAt.toDate()
      : null;
  const storedHash = String(data.sessionKeyHash ?? '').trim();

  if (revokedAt != null) {
    throw new Error('session_revoked');
  }
  if (status !== 'issued' || consumedAt != null) {
    throw new Error('session_already_consumed');
  }
  if (!storedHash || storedHash !== sessionKeyHash) {
    throw new Error('invalid_session_key');
  }
  if (!expiresAtDate || expiresAtDate.getTime() <= nowDate.getTime()) {
    throw new Error('session_expired');
  }
}

function mapImpersonationConsumeError(code) {
  switch (String(code ?? '').trim()) {
    case 'session_not_found':
      return {
        status: 404,
        error: 'session_not_found',
        message: 'Sessao de acesso assistido nao encontrada.',
      };
    case 'session_revoked':
      return {
        status: 403,
        error: 'session_revoked',
        message: 'Sessao de acesso assistido revogada.',
      };
    case 'session_already_consumed':
      return {
        status: 409,
        error: 'session_already_consumed',
        message: 'Sessao de acesso assistido ja consumida.',
      };
    case 'invalid_session_key':
      return {
        status: 403,
        error: 'invalid_session_key',
        message: 'Chave da sessao de acesso assistido invalida.',
      };
    case 'session_expired':
      return {
        status: 410,
        error: 'session_expired',
        message: 'Sessao de acesso assistido expirada.',
      };
    default:
      return {
        status: 500,
        error: 'session_consume_failed',
        message: 'Falha ao consumir sessao de acesso assistido.',
      };
  }
}

function normalizeBillingPlanKey(rawValue) {
  return String(rawValue ?? '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_');
}

function buildStripeRecommendedLookupKey({
  billingPlanKey,
  currency,
  recurringInterval,
  recurringIntervalCount,
}) {
  const normalizedPlanKey = normalizeBillingPlanKey(billingPlanKey).replace(
    /[^a-z0-9_-]+/g,
    '_',
  );
  if (!normalizedPlanKey) {
    return '';
  }

  const normalizedCurrency = String(currency ?? '').trim().toLowerCase();
  const normalizedInterval = String(recurringInterval ?? '').trim().toLowerCase();
  const normalizedCount = Number.isFinite(Number(recurringIntervalCount))
    ? Math.max(1, Math.floor(Number(recurringIntervalCount)))
    : 1;
  const countSuffix = normalizedCount > 1 ? `x${normalizedCount}` : '';

  const raw = `smartsfa_${normalizedPlanKey}_${normalizedCurrency}_${normalizedInterval}${countSuffix}`;
  const compact = raw
    .replace(/[^a-z0-9_]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '');
  return compact.length <= 120 ? compact : compact.slice(0, 120);
}

function parseBillingPlanKeyParts(billingPlanKey) {
  const normalized = normalizeBillingPlanKey(billingPlanKey);
  if (!normalized) {
    return { prefix: '', slug: '' };
  }

  const separatorIndex = normalized.indexOf('_');
  if (separatorIndex <= 0 || separatorIndex >= normalized.length - 1) {
    return { prefix: normalized, slug: normalized };
  }

  return {
    prefix: normalized.slice(0, separatorIndex),
    slug: normalized.slice(separatorIndex + 1),
  };
}

function sanitizeStripeMetadataValue(value, maxLength = 200) {
  const text = String(value ?? '').trim();
  if (!text) {
    return '';
  }
  return text.length <= maxLength ? text : text.slice(0, maxLength);
}

function buildStripeCatalogPlanMetadata({
  billingPlanKey,
  amountMinorUnits,
  currency,
  recurringInterval,
  recurringIntervalCount,
  lookupKey,
  actorUid,
  actorEmail,
}) {
  const parts = parseBillingPlanKeyParts(billingPlanKey);
  return {
    source: 'smartsfa_admin_console',
    billingPlanKey: sanitizeStripeMetadataValue(billingPlanKey),
    billingPlanPrefix: sanitizeStripeMetadataValue(parts.prefix),
    billingPlanSlug: sanitizeStripeMetadataValue(parts.slug),
    amountMinorUnits: sanitizeStripeMetadataValue(String(amountMinorUnits ?? '')),
    currency: sanitizeStripeMetadataValue(String(currency ?? '').toLowerCase(), 12),
    recurringInterval: sanitizeStripeMetadataValue(
      String(recurringInterval ?? '').toLowerCase(),
      20,
    ),
    recurringIntervalCount: sanitizeStripeMetadataValue(
      String(recurringIntervalCount ?? ''),
      8,
    ),
    lookupKey: sanitizeStripeMetadataValue(lookupKey),
    createdByUid: sanitizeStripeMetadataValue(actorUid),
    createdByEmail: sanitizeStripeMetadataValue(actorEmail),
  };
}

function resolveStripePlanPrefixByWorkspaceType(workspaceType) {
  const normalized = String(workspaceType ?? '').trim().toLowerCase();
  if (normalized === 'seller_solo_workspace') {
    return 'individual';
  }
  if (normalized === 'rep_workspace') {
    return 'representacoes';
  }
  if (normalized === 'brand_owner_workspace') {
    return 'enterprise';
  }
  return '';
}

function formatPlanAmountLabel({
  amountMinorUnits,
  currency,
  recurringInterval,
  recurringIntervalCount,
}) {
  const amount = Number(amountMinorUnits ?? 0);
  if (!Number.isFinite(amount) || amount <= 0) {
    return '';
  }

  const normalizedCurrency = String(currency ?? '').trim().toLowerCase();
  const currencyLabel =
    normalizedCurrency === 'brl'
      ? 'R$'
      : normalizedCurrency
        ? normalizedCurrency.toUpperCase()
        : '';
  const base = `${currencyLabel ? `${currencyLabel} ` : ''}${(amount / 100).toFixed(2)}`;

  const interval = String(recurringInterval ?? '').trim().toLowerCase();
  if (!interval) {
    return base;
  }

  const intervalCount = Number(recurringIntervalCount ?? 0);
  const normalizedCount = Number.isFinite(intervalCount) && intervalCount > 0
    ? Math.floor(intervalCount)
    : 1;

  return `${base} / ${interval} x${normalizedCount}`;
}

function isValidHttpAbsoluteUrl(value) {
  const raw = String(value ?? '').trim();
  if (!raw) {
    return false;
  }

  try {
    const parsed = new URL(raw);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

async function assertPlatformAdminActor({ firestore, uid }) {
  const normalizedUid = String(uid ?? '').trim();
  if (!normalizedUid) {
    return {
      allowed: false,
      status: 401,
      error: 'missing_uid',
      message: 'Usuario autenticado sem UID valido.',
      userData: null,
    };
  }

  const userDoc = await firestore.collection('usuarios').doc(normalizedUid).get();
  if (!userDoc.exists) {
    return {
      allowed: false,
      status: 403,
      error: 'user_not_found',
      message: 'Usuario autenticado nao encontrado em usuarios/{uid}.',
      userData: null,
    };
  }

  const userData = userDoc.data() || {};
  const platformRole = String(userData.platformRole ?? '').trim().toLowerCase();
  const activeGlobal = userData.ativoGlobal !== false;
  const consoleEnabled = userData.maintainerConsoleEnabled !== false;

  if (platformRole !== 'platform_admin' || !activeGlobal || !consoleEnabled) {
    return {
      allowed: false,
      status: 403,
      error: 'forbidden',
      message: 'Apenas platform_admin ativo com console habilitado pode operar billing Stripe.',
      userData,
    };
  }

  return {
    allowed: true,
    status: 200,
    error: '',
    message: '',
    userData,
  };
}

async function assertTenantBillingActorPermission({ firestore, uid, tenantId }) {
  const platformAccess = await assertPlatformAdminActor({ firestore, uid });
  if (platformAccess.allowed) {
    return {
      allowed: true,
      status: 200,
      error: '',
      message: '',
    };
  }

  const membership = await loadTenantMembershipByTenantAndUser({
    firestore,
    tenantId,
    uid,
  });

  if (!membership) {
    return {
      allowed: false,
      status: 403,
      error: 'membership_not_found',
      message: 'Usuario sem membership ativa no tenant informado.',
    };
  }

  const role = String(membership.role ?? '').trim().toLowerCase();
  const state = String(membership.state ?? 'active').trim().toLowerCase();
  const active = membership.ativo !== false;
  if (!active || state !== 'active' || role !== 'owner') {
    return {
      allowed: false,
      status: 403,
      error: 'owner_required',
      message: 'Somente owner ativo (ou platform_admin) pode operar checkout/billing do tenant.',
    };
  }

  return {
    allowed: true,
    status: 200,
    error: '',
    message: '',
  };
}

async function loadStripeIntegrationRuntime({ firestore, requireWebhookSecret }) {
  const config = await readStripeIntegrationConfig(firestore);
  const environment = config.activeEnvironment;
  const secretKey = getStripeSecretForEnvironment(environment);
  if (!secretKey) {
    return {
      ok: false,
      status: 503,
      error: 'integration_not_ready',
      message: `Secret Stripe ausente para ambiente ${environment}. Configure STRIPE_SK_${environment.toUpperCase()}.`,
      environment,
      webhookSecret: '',
      enabledEvents: config.webhookEvents,
      stripeClient: null,
    };
  }

  const webhookSecret = getStripeWebhookSecretForEnvironment(environment);
  if (requireWebhookSecret && !webhookSecret) {
    return {
      ok: false,
      status: 503,
      error: 'integration_not_ready',
      message: `Webhook secret ausente para ambiente ${environment}. Configure STRIPE_WHSEC_${environment.toUpperCase()}.`,
      environment,
      webhookSecret: '',
      enabledEvents: config.webhookEvents,
      stripeClient: null,
    };
  }

  return {
    ok: true,
    status: 200,
    error: '',
    message: '',
    environment,
    webhookSecret,
    enabledEvents: config.webhookEvents,
    stripeClient: getStripeClient(secretKey),
  };
}

async function readStripeIntegrationConfig(firestore) {
  const doc = await firestore.collection('billing_integrations').doc('stripe').get();
  const data = doc.data() || {};
  const envFromDoc = String(data.activeEnvironment ?? '').trim().toLowerCase();
  const envFromProcess = String(process.env.STRIPE_ACTIVE_ENVIRONMENT ?? '')
    .trim()
    .toLowerCase();

  const activeEnvironment = ['test', 'live'].includes(envFromDoc)
    ? envFromDoc
    : ['test', 'live'].includes(envFromProcess)
      ? envFromProcess
      : 'test';

  const webhookEvents = Array.isArray(data.webhookEvents)
    ? data.webhookEvents
      .map((value) => String(value ?? '').trim())
      .filter((value) => value)
    : [];

  return {
    activeEnvironment,
    webhookEvents:
      webhookEvents.length > 0 ? webhookEvents : STRIPE_DEFAULT_WEBHOOK_EVENTS,
  };
}

function getStripeSecretForEnvironment(environment) {
  if (environment === 'live') {
    return String(process.env.STRIPE_SK_LIVE ?? '').trim();
  }
  return String(process.env.STRIPE_SK_TEST ?? '').trim();
}

function getStripeWebhookSecretForEnvironment(environment) {
  if (environment === 'live') {
    return String(process.env.STRIPE_WHSEC_LIVE ?? '').trim();
  }
  return String(process.env.STRIPE_WHSEC_TEST ?? '').trim();
}

function getStripeClient(secretKey) {
  const normalizedSecret = String(secretKey ?? '').trim();
  if (!normalizedSecret) {
    throw new Error('Missing Stripe secret key.');
  }

  if (!STRIPE_CLIENT_CACHE.has(normalizedSecret)) {
    STRIPE_CLIENT_CACHE.set(normalizedSecret, new Stripe(normalizedSecret));
  }
  return STRIPE_CLIENT_CACHE.get(normalizedSecret);
}

async function loadStripePlanMapping({ firestore, billingPlanKey }) {
  const normalizedPlanKey = normalizeBillingPlanKey(billingPlanKey);
  if (!normalizedPlanKey) {
    return null;
  }

  const byIdDoc = await firestore
    .collection('billing_integrations')
    .doc('stripe')
    .collection('plan_mappings')
    .doc(normalizedPlanKey)
    .get();

  if (byIdDoc.exists) {
    const data = byIdDoc.data() || {};
    if (data.active !== false && String(data.stripePriceId ?? '').trim()) {
      return {
        billingPlanKey: normalizeBillingPlanKey(data.billingPlanKey ?? normalizedPlanKey),
        stripeProductId: String(data.stripeProductId ?? '').trim(),
        stripePriceId: String(data.stripePriceId ?? '').trim(),
        mappingType: String(data.mappingType ?? 'base').trim().toLowerCase(),
        overageMetric: String(data.overageMetric ?? '').trim().toLowerCase(),
        active: data.active !== false,
      };
    }
  }

  const querySnapshot = await firestore
    .collection('billing_integrations')
    .doc('stripe')
    .collection('plan_mappings')
    .where('billingPlanKey', '==', normalizedPlanKey)
    .limit(5)
    .get();

  for (const doc of querySnapshot.docs) {
    const data = doc.data() || {};
    if (data.active === false) {
      continue;
    }
    const priceId = String(data.stripePriceId ?? '').trim();
    if (!priceId) {
      continue;
    }
    return {
      billingPlanKey: normalizeBillingPlanKey(data.billingPlanKey ?? normalizedPlanKey),
      stripeProductId: String(data.stripeProductId ?? '').trim(),
      stripePriceId: priceId,
      mappingType: String(data.mappingType ?? 'base').trim().toLowerCase(),
      overageMetric: String(data.overageMetric ?? '').trim().toLowerCase(),
      active: true,
    };
  }

  return null;
}

async function resolveBillingPlanKeyByStripePriceId({ firestore, stripePriceId }) {
  const normalizedPriceId = String(stripePriceId ?? '').trim();
  if (!normalizedPriceId) {
    return '';
  }

  const snapshot = await firestore
    .collection('billing_integrations')
    .doc('stripe')
    .collection('plan_mappings')
    .where('stripePriceId', '==', normalizedPriceId)
    .limit(10)
    .get();

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    if (data.active === false) {
      continue;
    }
    const planKey = normalizeBillingPlanKey(data.billingPlanKey);
    if (planKey) {
      return planKey;
    }
  }
  return '';
}

async function processStripeWebhookEvent({ firestore, event, enabledEvents }) {
  const type = String(event?.type ?? '').trim();
  if (!type) {
    throw new Error('Webhook Stripe sem event.type.');
  }

  const enabledSet = new Set(
    (enabledEvents || STRIPE_DEFAULT_WEBHOOK_EVENTS)
      .map((item) => String(item ?? '').trim())
      .filter((item) => item),
  );

  if (!enabledSet.has(type)) {
    return {
      ignored: true,
      duplicate: false,
      tenantId: '',
    };
  }

  const eventId = String(event.id ?? '').trim();
  if (!eventId) {
    throw new Error('Webhook Stripe sem event.id.');
  }

  const eventRef = firestore.collection('billing_webhook_events').doc(eventId);
  let duplicate = false;

  await firestore.runTransaction(async (transaction) => {
    const existingDoc = await transaction.get(eventRef);
    if (existingDoc.exists) {
      const existingData = existingDoc.data() || {};
      const status = String(existingData.processingStatus ?? '')
        .trim()
        .toLowerCase();
      if (status === 'success') {
        duplicate = true;
        return;
      }
      const retryCount = Number(existingData.retryCount ?? 0);
      transaction.set(
        eventRef,
        {
          provider: 'stripe',
          eventId,
          type,
          receivedAt: new Date().toISOString(),
          processingStatus: 'processing',
          retryCount: Number.isFinite(retryCount) ? retryCount + 1 : 1,
        },
        { merge: true },
      );
      return;
    }

    transaction.set(eventRef, {
      provider: 'stripe',
      eventId,
      type,
      receivedAt: new Date().toISOString(),
      processingStatus: 'processing',
      retryCount: 0,
    });
  });

  if (duplicate) {
    return {
      ignored: false,
      duplicate: true,
      tenantId: '',
    };
  }

  try {
    const tenantId = await applyStripeWebhookEventToTenant({
      firestore,
      event,
    });

    await eventRef.set(
      {
        tenantId,
        processedAt: new Date().toISOString(),
        processingStatus: 'success',
        errorMessage: '',
      },
      { merge: true },
    );

    return {
      ignored: false,
      duplicate: false,
      tenantId,
    };
  } catch (error) {
    await eventRef.set(
      {
        processedAt: new Date().toISOString(),
        processingStatus: 'error',
        errorMessage: error instanceof Error ? error.message : String(error),
      },
      { merge: true },
    );
    throw error;
  }
}

async function applyStripeWebhookEventToTenant({ firestore, event }) {
  const type = String(event?.type ?? '').trim();
  const payload = event?.data?.object ?? {};

  if (type === 'checkout.session.completed') {
    const tenantId = await resolveTenantIdFromStripeReferences({
      firestore,
      explicitTenantId: payload?.metadata?.tenantId || payload?.client_reference_id,
      stripeCustomerId: payload?.customer,
      stripeSubscriptionId: payload?.subscription,
    });
    if (!tenantId) {
      throw new Error('checkout.session.completed sem tenantId resolvido.');
    }

    const billingPlanKey = normalizeBillingPlanKey(payload?.metadata?.billingPlanKey);
    await firestore.collection('tenants').doc(tenantId).set(
      {
        stripeCustomerId: String(payload?.customer ?? '').trim(),
        stripeCheckoutSessionId: String(payload?.id ?? '').trim(),
        stripeSubscriptionId: String(payload?.subscription ?? '').trim(),
        ...(billingPlanKey ? { billingPlanKey } : {}),
        billingUpdatedAt: new Date().toISOString(),
      },
      { merge: true },
    );

    return tenantId;
  }

  if (
    type === 'customer.subscription.created' ||
    type === 'customer.subscription.updated' ||
    type === 'customer.subscription.deleted'
  ) {
    const tenantId = await resolveTenantIdFromStripeReferences({
      firestore,
      explicitTenantId: payload?.metadata?.tenantId,
      stripeCustomerId: payload?.customer,
      stripeSubscriptionId: payload?.id,
    });
    if (!tenantId) {
      throw new Error(`${type} sem tenantId resolvido.`);
    }

    const priceId = readStripeSubscriptionPriceId(payload);
    const mappedPlanKey = await resolveBillingPlanKeyByStripePriceId({
      firestore,
      stripePriceId: priceId,
    });
    const fallbackPlanKey = normalizeBillingPlanKey(payload?.metadata?.billingPlanKey);

    await firestore.collection('tenants').doc(tenantId).set(
      buildTenantPatchFromStripeSubscription({
        subscription: payload,
        billingPlanKey: mappedPlanKey || fallbackPlanKey,
      }),
      { merge: true },
    );

    return tenantId;
  }

  if (
    type === 'invoice.paid' ||
    type === 'invoice.payment_failed' ||
    type === 'invoice.finalized'
  ) {
    const tenantId = await resolveTenantIdFromStripeReferences({
      firestore,
      explicitTenantId: payload?.metadata?.tenantId,
      stripeCustomerId: payload?.customer,
      stripeSubscriptionId: payload?.subscription,
    });
    if (!tenantId) {
      return '';
    }

    const nowIso = new Date().toISOString();
    const patch = {
      stripeCustomerId: String(payload?.customer ?? '').trim(),
      stripeSubscriptionId: String(payload?.subscription ?? '').trim(),
      stripeInvoiceId: String(payload?.id ?? '').trim(),
      stripePaymentIntentId: String(payload?.payment_intent ?? '').trim(),
      billingUpdatedAt: nowIso,
    };

    if (type === 'invoice.paid') {
      patch.billingStatus = 'active';
      patch.billingPastDueSinceAt = '';
    } else if (type === 'invoice.payment_failed') {
      patch.billingStatus = 'past_due';
      patch.billingPastDueSinceAt = nowIso;
    }

    await firestore.collection('tenants').doc(tenantId).set(patch, { merge: true });
    return tenantId;
  }

  return '';
}

async function resolveTenantIdFromStripeReferences({
  firestore,
  explicitTenantId,
  stripeCustomerId,
  stripeSubscriptionId,
}) {
  const explicit = String(explicitTenantId ?? '').trim();
  if (explicit) {
    return explicit;
  }

  const subscriptionId = String(stripeSubscriptionId ?? '').trim();
  if (subscriptionId) {
    const subscriptionSnapshot = await firestore
      .collection('tenants')
      .where('stripeSubscriptionId', '==', subscriptionId)
      .limit(1)
      .get();
    if (!subscriptionSnapshot.empty) {
      return subscriptionSnapshot.docs[0].id;
    }
  }

  const customerId = String(stripeCustomerId ?? '').trim();
  if (customerId) {
    const customerSnapshot = await firestore
      .collection('tenants')
      .where('stripeCustomerId', '==', customerId)
      .limit(1)
      .get();
    if (!customerSnapshot.empty) {
      return customerSnapshot.docs[0].id;
    }
  }

  return '';
}

function readStripeSubscriptionPriceId(subscription) {
  const items = Array.isArray(subscription?.items?.data)
    ? subscription.items.data
    : [];
  const firstItem = items.length > 0 ? items[0] : null;
  return String(firstItem?.price?.id ?? '').trim();
}

function readStripeSubscriptionCycle(subscription) {
  const items = Array.isArray(subscription?.items?.data)
    ? subscription.items.data
    : [];
  const firstItem = items.length > 0 ? items[0] : null;
  return String(firstItem?.price?.recurring?.interval ?? '').trim() || 'month';
}

function mapStripeSubscriptionStatusToBillingStatus(rawStatus) {
  const status = String(rawStatus ?? '').trim().toLowerCase();
  switch (status) {
    case 'trialing':
      return 'trial';
    case 'active':
      return 'active';
    case 'past_due':
    case 'unpaid':
    case 'incomplete':
      return 'past_due';
    case 'paused':
      return 'suspended';
    case 'canceled':
    case 'incomplete_expired':
      return 'canceled';
    default:
      return 'active';
  }
}

function toIsoFromUnixSeconds(value) {
  const seconds = Number(value);
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return '';
  }
  return new Date(seconds * 1000).toISOString();
}

function buildTenantPatchFromStripeSubscription({ subscription, billingPlanKey }) {
  const priceId = readStripeSubscriptionPriceId(subscription);
  const nowIso = new Date().toISOString();
  const billingStatus = mapStripeSubscriptionStatusToBillingStatus(
    subscription?.status,
  );

  const patch = {
    stripeCustomerId: String(subscription?.customer ?? '').trim(),
    stripeSubscriptionId: String(subscription?.id ?? '').trim(),
    stripePriceId: priceId,
    billingStatus,
    billingCycle: readStripeSubscriptionCycle(subscription),
    billingCurrentPeriodStartAt: toIsoFromUnixSeconds(
      subscription?.current_period_start,
    ),
    billingCurrentPeriodEndAt: toIsoFromUnixSeconds(
      subscription?.current_period_end,
    ),
    billingUpdatedAt: nowIso,
  };

  const normalizedPlanKey = normalizeBillingPlanKey(billingPlanKey);
  if (normalizedPlanKey) {
    patch.billingPlanKey = normalizedPlanKey;
  }

  if (billingStatus === 'past_due') {
    patch.billingPastDueSinceAt = nowIso;
  }
  if (billingStatus === 'active') {
    patch.billingPastDueSinceAt = '';
    patch.billingSuspendedAt = '';
  }
  if (billingStatus === 'canceled') {
    patch.billingSuspendedAt = nowIso;
  }

  return patch;
}

async function reconcileTenantStripeState({ firestore, stripeClient, tenantId }) {
  const tenantRef = firestore.collection('tenants').doc(tenantId);
  const tenantDoc = await tenantRef.get();
  if (!tenantDoc.exists) {
    throw new Error('Tenant nao encontrado para reconciliacao.');
  }

  const tenantData = tenantDoc.data() || {};
  const previousBillingStatus = String(tenantData.billingStatus ?? '').trim();
  const stripeCustomerId = String(tenantData.stripeCustomerId ?? '').trim();
  let stripeSubscriptionId = String(tenantData.stripeSubscriptionId ?? '').trim();

  if (!stripeCustomerId && !stripeSubscriptionId) {
    throw new Error('Tenant sem stripeCustomerId/stripeSubscriptionId para reconciliar.');
  }

  let subscription = null;
  if (stripeSubscriptionId) {
    try {
      subscription = await stripeClient.subscriptions.retrieve(stripeSubscriptionId, {
        expand: ['items.data.price'],
      });
    } catch (_) {
      subscription = null;
    }
  }

  if (!subscription && stripeCustomerId) {
    const list = await stripeClient.subscriptions.list({
      customer: stripeCustomerId,
      status: 'all',
      limit: 1,
      expand: ['data.items.data.price'],
    });
    if (Array.isArray(list.data) && list.data.length > 0) {
      subscription = list.data[0];
      stripeSubscriptionId = String(subscription.id ?? '').trim();
    }
  }

  let patch;
  if (subscription) {
    const priceId = readStripeSubscriptionPriceId(subscription);
    const mappedPlanKey = await resolveBillingPlanKeyByStripePriceId({
      firestore,
      stripePriceId: priceId,
    });
    patch = buildTenantPatchFromStripeSubscription({
      subscription,
      billingPlanKey: mappedPlanKey || tenantData.billingPlanKey,
    });
  } else {
    patch = {
      stripeCustomerId,
      stripeSubscriptionId,
      billingStatus: 'canceled',
      billingSuspendedAt: new Date().toISOString(),
      billingUpdatedAt: new Date().toISOString(),
    };
  }

  await tenantRef.set(patch, { merge: true });

  return {
    stripeSubscriptionId: String(patch.stripeSubscriptionId ?? '').trim(),
    previousBillingStatus,
    currentBillingStatus: String(patch.billingStatus ?? '').trim(),
    updatedAt: String(patch.billingUpdatedAt ?? '').trim(),
  };
}

async function applyTenantBillingActionToStripe({
  stripeClient,
  tenantId,
  tenantData,
  action,
  reason,
  actorUid,
}) {
  const stripeCustomerId = String(tenantData?.stripeCustomerId ?? '').trim();
  const stripeSubscriptionId = String(tenantData?.stripeSubscriptionId ?? '').trim();
  if (!stripeCustomerId && !stripeSubscriptionId) {
    return {
      applied: false,
      action: 'no_stripe_reference',
      message: 'Tenant sem stripeCustomerId/stripeSubscriptionId.',
    };
  }

  const nowIso = new Date().toISOString();
  const metadataBase = {
    smartsfaTenantId: sanitizeStripeMetadataValue(tenantId, 120),
    smartsfaBillingAction: sanitizeStripeMetadataValue(action, 60),
    smartsfaBillingReason: sanitizeStripeMetadataValue(reason || 'manual', 120),
    smartsfaBillingActorUid: sanitizeStripeMetadataValue(actorUid, 120),
    smartsfaBillingUpdatedAt: sanitizeStripeMetadataValue(nowIso, 60),
  };

  if (action === 'grant_7_days' || action === 'grant_30_days') {
    metadataBase.smartsfaGraceDays = action === 'grant_30_days' ? '30' : '7';
  }

  if (stripeCustomerId) {
    await stripeClient.customers.update(stripeCustomerId, {
      metadata: metadataBase,
    });
  }

  if (!stripeSubscriptionId) {
    return {
      applied: true,
      action: 'customer_metadata_updated',
      message: 'Subscription ausente; apenas metadata do customer foi atualizada.',
    };
  }

  if (action === 'suspend_billing') {
    await stripeClient.subscriptions.update(stripeSubscriptionId, {
      pause_collection: {
        behavior: 'void',
      },
      metadata: metadataBase,
    });
    return {
      applied: true,
      action: 'subscription_paused_collection_void',
      message: 'Cobranca pausada no Stripe (pause_collection=void).',
    };
  }

  if (action === 'normalize_billing') {
    await stripeClient.subscriptions.update(stripeSubscriptionId, {
      pause_collection: null,
      metadata: metadataBase,
    });
    return {
      applied: true,
      action: 'subscription_resumed_collection',
      message: 'Cobranca normalizada no Stripe (pause_collection removido).',
    };
  }

  await stripeClient.subscriptions.update(stripeSubscriptionId, {
    metadata: metadataBase,
  });
  return {
    applied: true,
    action: 'subscription_metadata_updated',
    message: 'Metadata da subscription atualizada no Stripe.',
  };
}

exports.auditTenantOwnershipIntegrityDaily = onSchedule(
  { region: 'us-central1', timeoutSeconds: 540, schedule: '17 3 * * *' },
  async () => {
    const firestore = admin.firestore();
    const nowIso = new Date().toISOString();

    const tenantsSnapshot = await firestore.collection('tenants').get();
    let processed = 0;
    let violations = 0;

    for (const tenantDoc of tenantsSnapshot.docs) {
      const tenantId = String(tenantDoc.id ?? '').trim();
      if (!tenantId) {
        continue;
      }

      const tenantData = tenantDoc.data() || {};
      const membershipsSnapshot = await firestore
        .collection('tenant_memberships')
        .where('tenantId', '==', tenantId)
        .where('ativo', '==', true)
        .get();

      const activeOwnerUids = [];
      for (const membershipDoc of membershipsSnapshot.docs) {
        const membership = membershipDoc.data() || {};
        const role = String(membership.role || '').trim().toLowerCase();
        const state = String(membership.state || 'active').trim().toLowerCase();
        const uid = String(membership.uid || '').trim();
        if (role === 'owner' && state === 'active' && uid) {
          activeOwnerUids.push(uid);
        }
      }

      const uniqueOwnerUids = [...new Set(activeOwnerUids)];
      const patch = {
        workspaceIntegrityUpdatedAt: nowIso,
      };

      if (uniqueOwnerUids.length > 0) {
        patch.workspaceIntegrityState = 'ok';
        patch.workspaceAbandoned = false;
        if (!String(tenantData.ownerUid || '').trim()) {
          patch.ownerUid = uniqueOwnerUids[0];
        }

        const billingOwnerUid = String(tenantData.billingOwnerUid || '').trim();
        if (!billingOwnerUid) {
          patch.billingOwnerUid = uniqueOwnerUids[0];
          const ownerDoc = await firestore
            .collection('usuarios')
            .doc(uniqueOwnerUids[0])
            .get();
          const ownerData = ownerDoc.data() || {};
          patch.billingOwnerEmail = String(
            ownerData.email || ownerData.userEmail || '',
          ).trim();
        }
      } else {
        violations += 1;
        patch.workspaceIntegrityState = 'orphan_violation';
        patch.workspaceAbandoned = true;
        patch.workspaceIntegrityViolationAt =
          String(tenantData.workspaceIntegrityViolationAt || '').trim() || nowIso;

        const lastKnownOwnerUid = String(tenantData.ownerUid || '').trim();
        let lastKnownOwnerEmail = '';
        if (lastKnownOwnerUid) {
          const ownerDoc = await firestore
            .collection('usuarios')
            .doc(lastKnownOwnerUid)
            .get();
          const ownerData = ownerDoc.data() || {};
          lastKnownOwnerEmail = String(
            ownerData.email || ownerData.userEmail || '',
          ).trim();
        }

        patch.ownerRetentionSnapshot = {
          lastKnownOwnerUid,
          lastKnownOwnerEmail,
          capturedAt: nowIso,
          reason: 'no_active_owner_membership',
        };
      }

      await firestore.collection('tenants').doc(tenantId).set(patch, {
        merge: true,
      });
      processed += 1;
    }

    console.log(
      JSON.stringify({
        action: 'auditTenantOwnershipIntegrityDaily',
        processed,
        violations,
      }),
    );
  },
);