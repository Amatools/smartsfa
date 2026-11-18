const { onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const crypto = require('node:crypto');
const {
  formatPlanAmountLabel,
  isValidHttpAbsoluteUrl,
  normalizeBillingPlanKey,
  normalizeBillingSelfServiceAction,
  parseBillingPlanKeyParts,
  readNonNegativeInteger,
  resolveStripePlanPrefixByWorkspaceType,
  sanitizeStripeMetadataValue,
} = require('./src/billing/shared_helpers');
const {
  resolveCheckoutApiProviderSelection,
  resolveTenantBillingProviderKey,
} = require('./src/billing/provider_resolution');
const {
  buildStripePlanMappingFromDocData,
  loadStripePlanMapping,
  resolveStripePlanMappingByPriceId,
  resolveStripeSeatAddonMappingForBasePlan,
} = require('./src/billing/stripe_plan_mappings');
const {
  buildStripeCatalogPlanMetadata,
  buildStripeRecommendedLookupKey,
} = require('./src/billing/stripe_catalog_helpers');
const {
  extractAsaasReferenceInfo,
  mapAsaasCycleToBillingCycle,
  mapBillingStatusToAccountState,
  normalizeAsaasDateToIso,
} = require('./src/billing/asaas_webhook_helpers');
const {
  resolveTenantIdFromAsaasReferences,
  resolveTenantIdFromStripeReferences,
} = require('./src/billing/webhook_tenant_resolution');
const {
  createAsaasWebhookFallbackEventId,
} = require('./src/billing/runtime_secrets');
const {
  ASAAS_DEFAULT_WEBHOOK_EVENTS,
  STRIPE_DEFAULT_WEBHOOK_EVENTS,
  loadBillingProviderRuntime,
  loadStripeIntegrationRuntime,
  readAsaasIntegrationConfig,
} = require('./src/billing/integration_runtime');
const {
  readCheckoutApiConfig,
  resolveAsaasCallbackUrls,
} = require('./src/billing/checkout_config');
const {
  assertPlatformAdminActor,
  assertTenantBillingActorPermission,
} = require('./src/billing/actor_permission_helpers');
const {
  applyTenantBillingActionToProvider: dispatchApplyTenantBillingActionToProvider,
  applyTenantBillingSelfServiceActionToProvider:
    dispatchApplyTenantBillingSelfServiceActionToProvider,
  processBillingWebhookEvent: dispatchProcessBillingWebhookEvent,
  reconcileTenantBillingState: dispatchReconcileTenantBillingState,
} = require('./src/billing/provider_dispatch');
const {
  buildAsaasCheckoutPayload,
  resolveAsaasPortalFallbackUrl,
} = require('./src/billing/asaas_checkout_helpers');
const {
  buildTenantPatchFromAsaasEvent,
} = require('./src/billing/asaas_tenant_patch_helpers');
const {
  applyAsaasWebhookEventToTenant: applyAsaasWebhookEventToTenantHelper,
} = require('./src/billing/asaas_webhook_application_helpers');
const {
  processAsaasWebhookEvent,
} = require('./src/billing/asaas_webhook_processor_helpers');
const {
  resolveAsaasPlanMapping,
} = require('./src/billing/asaas_plan_mapping_helpers');
const {
  listAsaasCheckoutPlansForTenant,
} = require('./src/billing/asaas_checkout_plan_listing_helpers');
const {
  createAsaasCheckoutSession: createAsaasCheckoutSessionHelper,
} = require('./src/billing/asaas_checkout_session_helpers');
const {
  applyTenantBillingActionToAsaas,
  applyTenantBillingSelfServiceActionToAsaas,
  fetchAsaasApiJson,
} = require('./src/billing/asaas_actions_helpers');
const {
  reconcileTenantAsaasState: reconcileTenantAsaasStateHelper,
} = require('./src/billing/asaas_reconcile_helpers');
const {
  loadTenantMembershipByTenantAndUser,
} = require('./src/billing/tenant_membership_helpers');
const {
  writeTenantMembershipAuditEvent,
} = require('./src/billing/tenant_membership_audit_helpers');
const {
  proxyBillingRequestToFunction,
} = require('./src/billing/http_proxy_helpers');
const {
  processStripeWebhookEvent: processStripeWebhookEventHelper,
} = require('./src/billing/stripe_webhook_processor_helpers');
const {
  applyStripeWebhookEventToTenant: applyStripeWebhookEventToTenantHelper,
} = require('./src/billing/stripe_webhook_application_helpers');
const {
  reconcileTenantStripePeriodIfMissing,
} = require('./src/billing/stripe_period_reconcile_helpers');
const {
  reconcileTenantStripeState,
} = require('./src/billing/stripe_reconcile_helpers');
const {
  applyTenantBillingActionToStripe,
} = require('./src/billing/stripe_actions_helpers');
const {
  applyStripeSeatAddonDeltaToActiveSubscription:
    applyStripeSeatAddonDeltaToActiveSubscriptionHelper,
} = require('./src/billing/stripe_seat_addon_helpers');
const {
  enforceTenantSeatAllowanceForTenant:
    enforceTenantSeatAllowanceForTenantHelper,
} = require('./src/billing/seat_enforcement_runtime_helpers');
const {
  auditTenantOwnershipIntegrityDaily,
} = require('./src/billing/tenant_ownership_integrity_audit_helpers');
const {
  executeTenantBillingSelfServiceAction,
} = require('./src/billing/self_service_management_helpers');
const {
  executeManageTenantBillingStateAction,
} = require('./src/billing/tenant_billing_state_management_helpers');
const {
  executeUpdateBillingSeatAddonsAction,
} = require('./src/billing/seat_addon_management_helpers');
const {
  executeListBillingCheckoutPlansAction,
} = require('./src/billing/checkout_plan_listing_management_helpers');
const {
  executeCreateBillingCheckoutSessionAction,
} = require('./src/billing/checkout_session_management_helpers');
const {
  executeCreateBillingPortalSessionAction,
} = require('./src/billing/portal_session_management_helpers');
const {
  executeCreateStripePortalSessionAction,
} = require('./src/billing/stripe_portal_session_management_helpers');
const {
  executeCreateStripeCheckoutSessionAction,
} = require('./src/billing/stripe_checkout_session_management_helpers');
const {
  executeListStripeCheckoutPlansAction,
} = require('./src/billing/stripe_checkout_plan_listing_management_helpers');
const {
  executeReconcileStripeTenantAction,
  executeReconcileAsaasTenantAction,
  executeReconcileAllStripeTenantsAction,
} = require('./src/billing/tenant_reconcile_management_helpers');
const {
  executeListStripeCatalogAction,
  executeCreateStripeCatalogPlanAction,
} = require('./src/billing/stripe_catalog_management_helpers');
const {
  executeExpireTenantGraceDailyAction,
  executeEnforceTenantSeatAllowanceHourlyAction,
} = require('./src/billing/tenant_billing_maintenance_helpers');
const {
  executeSyncSankhyaPriceTablesNightlyAction,
} = require('./src/billing/sankhya_price_tables_sync_management_helpers');
const {
  executeSyncSankhyaCatalogModuleAction,
} = require('./src/billing/sankhya_catalog_sync_management_helpers');
const {
  executeValidateEnterpriseOwnerAccess,
} = require('./src/billing/sankhya_access_validation_helpers');
const {
  executeFetchSankhyaOperationTypesAction,
} = require('./src/billing/sankhya_operation_types_management_helpers');
const {
  executeSyncSankhyaProductsModuleAction,
} = require('./src/billing/sankhya_products_sync_management_helpers');
const {
  executeSyncSankhyaClientesModuleAction,
} = require('./src/billing/sankhya_clientes_sync_management_helpers');
const {
  executeSyncSankhyaTaxRulesModuleAction,
} = require('./src/billing/sankhya_tax_rules_sync_management_helpers');
const {
  executeSyncSankhyaProductImagesModuleAction,
} = require('./src/billing/sankhya_product_images_sync_management_helpers');
const {
  executeSyncSankhyaPriceTablesModuleAction,
} = require('./src/billing/sankhya_price_tables_module_sync_management_helpers');
const {
  normalizePriceTableCodes,
  buildTenantProductIndex,
  upsertPriceTableDocument,
  upsertDefaultPriceTableDocument,
  readPriceRowsFromPayload,
  buildPriceTableDocId,
  buildDefaultPriceTableDocId,
  buildDefaultProductBasePriceDocId,
  normalizeTextToken,
  buildProductBasePriceDocId,
} = require('./src/billing/sankhya_price_tables_data_helpers');
const {
  fetchSankhyaProductsFiscalData,
} = require('./src/billing/sankhya_products_fiscal_query_helpers');
const {
  mapSankhyaProductToFirestore,
  resolveInternalProductCode,
  nextTenantErpProductInternalSequence,
  buildProductDocId,
} = require('./src/billing/sankhya_products_model_helpers');
const {
  executeSankhyaDbExplorerQuery: executeSankhyaDbExplorerQueryAction,
  extractSankhyaXmlError,
  normalizeDbExplorerRows,
} = require('./src/billing/sankhya_dbexplorer_query_helpers');
const {
  parseDateToUnixMs,
  readMembershipOrderingMs,
  readTenantSeatAllowance,
  shouldEnforceTenantSeatAllowance,
} = require('./src/billing/seat_enforcement_helpers');
const {
  buildTenantPatchFromStripeSubscription,
  readStripeSubscriptionLineItems,
  readStripeSubscriptionPeriodFromInvoices,
  readStripeSubscriptionPriceId,
} = require('./src/billing/stripe_subscription_helpers');

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
const STRIPE_SYNC_BATCH_LIMIT = 120;
const STRIPE_RUNTIME_SECRETS = [
  'STRIPE_SK_TEST',
  'STRIPE_SK_LIVE',
  'STRIPE_WHSEC_TEST',
  'STRIPE_WHSEC_LIVE',
  'STRIPE_ACTIVE_ENVIRONMENT',
];
const ASAAS_RUNTIME_SECRETS = [
  'ASAAS_WEBHOOK_TOKEN_SANDBOX',
  'ASAAS_WEBHOOK_TOKEN_PRODUCTION',
  'ASAAS_API_KEY_SANDBOX',
  'ASAAS_API_KEY_PRODUCTION',
];
const BILLING_RUNTIME_SECRETS = [
  ...STRIPE_RUNTIME_SECRETS,
  ...ASAAS_RUNTIME_SECRETS,
];
const CLOUD_FUNCTIONS_BASE_URL = 'https://us-central1-smart-sfa.cloudfunctions.net';
const STRIPE_CHECKOUT_FUNCTION_URL =
  `${CLOUD_FUNCTIONS_BASE_URL}/createStripeCheckoutSession`;
const STRIPE_PORTAL_FUNCTION_URL =
  `${CLOUD_FUNCTIONS_BASE_URL}/createStripePortalSession`;
const STRIPE_LIST_PLANS_FUNCTION_URL =
  `${CLOUD_FUNCTIONS_BASE_URL}/listStripeCheckoutPlans`;
const BILLING_PROVIDER_STRIPE = 'stripe';
const BILLING_PROVIDER_ASAAS = 'asaas';
const BILLING_PROVIDER_DEFAULT = BILLING_PROVIDER_STRIPE;
const TENANT_SEAT_OVER_LIMIT_GRACE_DAYS = 3;
const TENANT_SEAT_ENFORCEMENT_ACTOR_UID = 'system_seat_enforcement';

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

    const result = await executeSyncSankhyaCatalogModuleAction({
      firestore: admin.firestore(),
      request,
      requestBody: request.body,
      validateEnterpriseOwnerAccess,
      authenticateInSankhya,
      readBearerToken,
      syncSankhyaProductsModule,
      syncSankhyaTaxRulesModule,
      syncSankhyaClientesModule,
      syncSankhyaProductImagesModule,
      syncSankhyaPriceTablesModule,
    });

    response.status(result.status).json(result.body);
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

    const result = await executeCreateStripeCheckoutSessionAction({
      firestore,
      payload: request.body,
      tenantId,
      billingPlanKey,
      successUrl,
      cancelUrl,
      authContext,
      assertTenantBillingActorPermission,
      readCheckoutApiConfig,
      loadStripeIntegrationRuntime,
      loadStripePlanMapping,
      resolveStripeSeatAddonMappingForBasePlan,
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
    });

    response.status(result.status).json(result.body);
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

    const result = await executeCreateStripePortalSessionAction({
      firestore,
      tenantId,
      returnUrl,
      authContext,
      assertTenantBillingActorPermission,
      readCheckoutApiConfig,
      loadStripeIntegrationRuntime,
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
    });

    response.status(result.status).json(result.body);
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
      const processing = await processBillingWebhookEvent({
        firestore,
        providerKey: BILLING_PROVIDER_STRIPE,
        event,
        enabledEvents: integrationReady.enabledEvents,
        stripeClient: integrationReady.stripeClient,
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

exports.handleAsaasWebhook = onRequest(
  {
    cors: false,
    region: 'us-central1',
    timeoutSeconds: 120,
    secrets: ASAAS_RUNTIME_SECRETS,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const firestore = admin.firestore();
    const integrationConfig = await readAsaasIntegrationConfig(firestore);
    const sandboxToken = getAsaasWebhookTokenForEnvironment('sandbox');
    const productionToken = getAsaasWebhookTokenForEnvironment('production');

    if (!sandboxToken && !productionToken) {
      response.status(503).json({
        error: 'integration_not_ready',
        message:
          'Webhook token Asaas ausente. Configure ASAAS_WEBHOOK_TOKEN_SANDBOX ou ASAAS_WEBHOOK_TOKEN_PRODUCTION.',
      });
      return;
    }

    const tokenHeader = String(
      request.headers['asaas-access-token'] ?? '',
    ).trim();
    if (!tokenHeader) {
      response.status(401).json({
        error: 'missing_auth_token',
        message: 'Header asaas-access-token ausente.',
      });
      return;
    }

    let matchedEnvironment = '';
    if (sandboxToken && tokenHeader === sandboxToken) {
      matchedEnvironment = 'sandbox';
    }
    if (productionToken && tokenHeader === productionToken) {
      matchedEnvironment = 'production';
    }

    if (!matchedEnvironment) {
      response.status(401).json({
        error: 'invalid_auth_token',
        message: 'Token de autenticacao do webhook Asaas invalido.',
      });
      return;
    }

    const eventPayload =
      request.body && typeof request.body === 'object' ? request.body : {};
    const eventType = String(eventPayload?.event ?? '').trim();
    const eventId = String(eventPayload?.id ?? '').trim();

    if (!eventType) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'Evento Asaas sem campo event.',
      });
      return;
    }

    const enabledSet = new Set(
      (integrationConfig.webhookEvents || [])
        .map((item) => String(item ?? '').trim())
        .filter((item) => item),
    );

    if (enabledSet.size > 0 && !enabledSet.has(eventType)) {
      response.status(200).json({
        received: true,
        ignored: true,
        duplicate: false,
        reason: 'event_not_enabled',
        eventType,
        webhookEnvironment: matchedEnvironment,
      });
      return;
    }

    const eventDocId = eventId
      ? `asaas_${eventId}`
      : createAsaasWebhookFallbackEventId(eventPayload);
    const eventRef = firestore.collection('billing_webhook_events').doc(eventDocId);
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
            provider: BILLING_PROVIDER_ASAAS,
            eventId: eventDocId,
            type: eventType,
            receivedAt: new Date().toISOString(),
            processingStatus: 'processing',
            retryCount: Number.isFinite(retryCount) ? retryCount + 1 : 1,
            webhookEnvironment: matchedEnvironment,
            payload: eventPayload,
          },
          { merge: true },
        );
        return;
      }

      transaction.set(eventRef, {
        provider: BILLING_PROVIDER_ASAAS,
        eventId: eventDocId,
        type: eventType,
        receivedAt: new Date().toISOString(),
        processingStatus: 'processing',
        retryCount: 0,
        webhookEnvironment: matchedEnvironment,
        payload: eventPayload,
      });
    });

    if (duplicate) {
      response.status(200).json({
        received: true,
        ignored: false,
        duplicate: true,
        eventId: eventDocId,
        eventType,
        webhookEnvironment: matchedEnvironment,
      });
      return;
    }

    try {
      const processing = await processBillingWebhookEvent({
        firestore,
        providerKey: BILLING_PROVIDER_ASAAS,
        event: eventPayload,
        enabledEvents: integrationConfig.webhookEvents,
        stripeClient: null,
        asaasRuntime: {
          environment: matchedEnvironment,
        },
      });

      await eventRef.set(
        {
          tenantId: processing.tenantId,
          processedAt: new Date().toISOString(),
          processingStatus: 'success',
          errorMessage: '',
        },
        { merge: true },
      );

      response.status(200).json({
        received: true,
        ignored: processing.ignored,
        duplicate: false,
        eventId: eventDocId,
        eventType,
        tenantId: processing.tenantId,
        billingStatus: processing.billingStatus,
        provider: BILLING_PROVIDER_ASAAS,
        webhookEnvironment: matchedEnvironment,
      });
    } catch (error) {
      await eventRef.set(
        {
          processedAt: new Date().toISOString(),
          processingStatus: 'error',
          errorMessage: error instanceof Error ? error.message : String(error),
        },
        { merge: true },
      );

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

    const result = await executeReconcileStripeTenantAction({
      firestore,
      tenantId,
      reason,
      authContext,
      assertPlatformAdminActor,
      loadStripeIntegrationRuntime,
      reconcileTenantBillingState,
      timestampFromDate: (date) => admin.firestore.Timestamp.fromDate(date),
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
    });

    response.status(result.status).json(result.body);
  },
);

exports.reconcileAsaasTenant = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 90,
    secrets: ASAAS_RUNTIME_SECRETS,
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

    const result = await executeReconcileAsaasTenantAction({
      firestore,
      tenantId,
      reason,
      authContext,
      assertPlatformAdminActor,
      loadBillingProviderRuntime,
      reconcileTenantBillingState,
      timestampFromDate: (date) => admin.firestore.Timestamp.fromDate(date),
      billingProviderAsaas: BILLING_PROVIDER_ASAAS,
    });

    response.status(result.status).json(result.body);
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

    const result = await executeReconcileAllStripeTenantsAction({
      firestore,
      dryRun,
      limit,
      authContext,
      assertPlatformAdminActor,
      loadStripeIntegrationRuntime,
      reconcileTenantBillingState,
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
    });

    response.status(result.status).json(result.body);
  },
);

exports.manageTenantBillingState = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 90,
    secrets: BILLING_RUNTIME_SECRETS,
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
      'clear_plan_link',
    ]);
    if (!supportedActions.has(action)) {
      response.status(400).json({
        error: 'invalid_action',
        message:
          'Acao invalida. Use grant_7_days, grant_30_days, normalize_billing, suspend_billing ou clear_plan_link.',
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

    const result = await executeManageTenantBillingStateAction({
      firestore,
      tenantId,
      action,
      reason,
      providerHint: String(request.body?.provider ?? '').trim(),
      authContext,
      assertPlatformAdminActor,
      readCheckoutApiConfig,
      resolveTenantBillingProviderKey,
      loadBillingProviderRuntime,
      applyTenantBillingActionToProvider,
      enforceTenantSeatAllowanceForTenant,
      timestampFromDate: (date) => admin.firestore.Timestamp.fromDate(date),
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
      billingProviderAsaas: BILLING_PROVIDER_ASAAS,
    });

    response.status(result.status).json(result.body);
  },
);

exports.expireTenantGraceDaily = onSchedule(
  { region: 'us-central1', timeoutSeconds: 540, schedule: '23 2 * * *' },
  async () => {
    return executeExpireTenantGraceDailyAction({
      firestore: admin.firestore(),
      nowDate: new Date(),
    });
  },
);

exports.enforceTenantSeatAllowanceHourly = onSchedule(
  { region: 'us-central1', timeoutSeconds: 540, schedule: '11 * * * *' },
  async () => {
    return executeEnforceTenantSeatAllowanceHourlyAction({
      firestore: admin.firestore(),
      nowDate: new Date(),
      enforceTenantSeatAllowanceForTenant,
      loggerInfo: console.info,
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

    const firestore = admin.firestore();
    const authContext = await verifyFirebaseAuthFromRequest(request);
    if (!authContext.ok) {
      response.status(authContext.status).json({
        error: authContext.error,
        message: authContext.message,
      });
      return;
    }

    const result = await executeListStripeCatalogAction({
      firestore,
      payload,
      authContext,
      assertPlatformAdminActor,
      loadStripeIntegrationRuntime,
    });

    response.status(result.status).json(result.body);
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

    const firestore = admin.firestore();
    const authContext = await verifyFirebaseAuthFromRequest(request);
    if (!authContext.ok) {
      response.status(authContext.status).json({
        error: authContext.error,
        message: authContext.message,
      });
      return;
    }

    const result = await executeCreateStripeCatalogPlanAction({
      firestore,
      payload,
      authContext,
      assertPlatformAdminActor,
      loadStripeIntegrationRuntime,
      normalizeBillingPlanKey,
      buildStripeRecommendedLookupKey,
      buildStripeCatalogPlanMetadata,
      timestampFromDate: (date) => admin.firestore.Timestamp.fromDate(date),
    });

    response.status(result.status).json(result.body);
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

    const result = await executeListStripeCheckoutPlansAction({
      firestore,
      tenantId,
      authContext,
      assertTenantBillingActorPermission,
      readCheckoutApiConfig,
      resolveStripePlanPrefixByWorkspaceType,
      buildStripePlanMappingFromDocData,
      formatPlanAmountLabel,
      normalizeBillingPlanKey,
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
    });

    response.status(result.status).json(result.body);
  },
);

exports.createBillingCheckoutSession = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 60,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const payload = request.body && typeof request.body === 'object'
      ? request.body
      : {};
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

    const result = await executeCreateBillingCheckoutSessionAction({
      firestore,
      request,
      response,
      payload,
      tenantId,
      authContext,
      assertTenantBillingActorPermission,
      readCheckoutApiConfig,
      resolveCheckoutApiProviderSelection,
      proxyBillingRequestToFunction,
      stripeCheckoutFunctionUrl: STRIPE_CHECKOUT_FUNCTION_URL,
      createAsaasCheckoutSession,
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
      billingProviderAsaas: BILLING_PROVIDER_ASAAS,
    });

    if (result.handledByProxy) {
      return;
    }

    response.status(result.status).json(result.body);
  },
);

exports.createBillingPortalSession = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 45,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const payload = request.body && typeof request.body === 'object'
      ? request.body
      : {};
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

    const result = await executeCreateBillingPortalSessionAction({
      firestore,
      request,
      response,
      payload,
      tenantId,
      authContext,
      assertTenantBillingActorPermission,
      readCheckoutApiConfig,
      resolveCheckoutApiProviderSelection,
      proxyBillingRequestToFunction,
      stripePortalFunctionUrl: STRIPE_PORTAL_FUNCTION_URL,
      readAsaasIntegrationConfig,
      resolveAsaasPortalFallbackUrl,
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
      billingProviderAsaas: BILLING_PROVIDER_ASAAS,
    });

    if (result.handledByProxy) {
      return;
    }

    response.status(result.status).json(result.body);
  },
);

exports.updateBillingSeatAddons = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 60,
    secrets: BILLING_RUNTIME_SECRETS,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const payload =
      request.body && typeof request.body === 'object'
        ? request.body
        : {};
    const tenantId = String(payload?.tenantId ?? '').trim();
    const billingPlanKey = normalizeBillingPlanKey(payload?.billingPlanKey);
    const addonSeatsDelta = readNonNegativeInteger(payload?.addonSeatsDelta, 0);

    if (!tenantId) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'tenantId e obrigatorio.',
      });
      return;
    }

    if (addonSeatsDelta <= 0 || addonSeatsDelta > 10) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'addonSeatsDelta deve ser inteiro entre 1 e 10.',
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

    const result = await executeUpdateBillingSeatAddonsAction({
      firestore,
      payload,
      tenantId,
      billingPlanKey,
      addonSeatsDelta,
      authContext,
      assertTenantBillingActorPermission,
      readCheckoutApiConfig,
      resolveCheckoutApiProviderSelection,
      loadBillingProviderRuntime,
      applyStripeSeatAddonDeltaToActiveSubscription,
      enforceTenantSeatAllowanceForTenant,
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
    });

    response.status(result.status).json(result.body);
  },
);

exports.listBillingCheckoutPlans = onRequest(
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

    const payload =
      request.method === 'GET'
        ? request.query
        : request.body && typeof request.body === 'object'
          ? request.body
          : {};

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

    const result = await executeListBillingCheckoutPlansAction({
      firestore,
      request,
      response,
      payload,
      tenantId,
      authContext,
      assertTenantBillingActorPermission,
      readCheckoutApiConfig,
      resolveCheckoutApiProviderSelection,
      proxyBillingRequestToFunction,
      stripeListPlansFunctionUrl: STRIPE_LIST_PLANS_FUNCTION_URL,
      listAsaasCheckoutPlansForTenant,
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
      billingProviderAsaas: BILLING_PROVIDER_ASAAS,
    });

    if (result.handledByProxy) {
      return;
    }

    response.status(result.status).json(result.body);
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
  return executeValidateEnterpriseOwnerAccess({
    firestore,
    request,
    tenantId,
    verifyIdToken: (idToken) => admin.auth().verifyIdToken(idToken),
    loadTenantMembershipByTenantAndUser,
  });
}

exports.fetchSankhyaOperationTypes = onRequest(
  { cors: true, region: 'us-central1', timeoutSeconds: 30 },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const result = await executeFetchSankhyaOperationTypesAction({
      requestBody: request.body,
      authenticateInSankhya,
      readBearerToken,
      buildSankhyaOperationTypesSql,
      executeSankhyaDbExplorerQuery,
      mapSankhyaOperationTypeRow,
    });

    response.status(result.status).json(result.body);
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
    return executeSyncSankhyaPriceTablesNightlyAction({
      firestore: admin.firestore(),
      authenticateInSankhya,
      readBearerToken,
      syncSankhyaPriceTablesModule,
      loggerError: console.error,
      loggerLog: console.log,
    });
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
  return executeSyncSankhyaProductsModuleAction({
    firestore,
    tenantId,
    baseUrl,
    bearerToken,
    xToken,
    fetchImpl: fetch,
    sankhyaProductsPath: SANKHYA_PRODUCTS_PATH,
    tryParseJson,
    toCodeString,
    isZeroCode,
    temporaryImportLimit: TEMPORARY_IMPORT_LIMIT,
    buildTenantNcmGroupIndex,
    fetchSankhyaProductsFiscalData: (input) =>
      fetchSankhyaProductsFiscalData({
        ...input,
        normalizeSankhyaNumericCodeList,
        executeSankhyaDbExplorerQuery,
        toCodeString,
        readRowValueByAliases,
        isZeroCode,
        normalizeOrigemMercadoriaCst,
        toNumberOrNull,
      }),
    resolveInternalProductCode: (input) =>
      resolveInternalProductCode({
        ...input,
        nextTenantErpProductInternalSequence: (seqInput) =>
          nextTenantErpProductInternalSequence({
            ...seqInput,
            readInt,
            admin,
          }),
      }),
    mapSankhyaProductToFirestore: (input) =>
      mapSankhyaProductToFirestore({
        ...input,
        normalizeOrigemMercadoriaCst,
        toNumberOrNull,
        normalizeDigits,
        buildProductDocId,
      }),
    updateTenantSyncState,
    readInt,
  });
}

async function syncSankhyaPriceTablesModule({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
}) {
  return executeSyncSankhyaPriceTablesModuleAction({
    firestore,
    tenantId,
    baseUrl,
    bearerToken,
    xToken,
    normalizePriceTableCodes,
    buildDefaultPriceTableDocId,
    upsertDefaultPriceTableDocument,
    buildTenantProductIndex,
    buildPriceTableDocId,
    upsertPriceTableDocument,
    fetchImpl: fetch,
    tryParseJson,
    readPriceRowsFromPayload,
    toCodeString,
    isZeroCode,
    toNumberOrNull,
    normalizeTextToken,
    buildProductBasePriceDocId,
    buildDefaultProductBasePriceDocId,
    updateTenantSyncState,
    loggerError: console.error,
  });
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

async function executeSankhyaDbExplorerQuery({
  baseUrl,
  bearerToken,
  xToken,
  sql,
}) {
  return executeSankhyaDbExplorerQueryAction({
    baseUrl,
    bearerToken,
    xToken,
    sql,
    endpointPaths: SANKHYA_DBEXPLORER_ENDPOINT_PATHS,
    fetchImpl: fetch,
    tryParseJson,
    extractSankhyaXmlError,
    normalizeDbExplorerRows,
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
  return executeSyncSankhyaTaxRulesModuleAction({
    firestore,
    tenantId,
    baseUrl,
    bearerToken,
    xToken,
    buildSankhyaTaxRulesSql,
    executeSankhyaDbExplorerQuery,
    mapSankhyaTaxRuleRow,
    normalizeDigits,
    computeFingerprintHash,
    buildTaxFingerprintKey,
    sanitizeKeyToken,
    buildAutoGroupName,
    buildAutoGroupDescription,
    applyTaxGroupsToExistingProducts,
    updateTenantSyncState,
    loggerError: console.error,
  });
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
  return executeSyncSankhyaClientesModuleAction({
    firestore,
    tenantId,
    baseUrl,
    bearerToken,
    xToken,
    codigosFiltro,
    buildSankhyaClientesSql,
    executeSankhyaDbExplorerQuery,
    buildClienteDocId,
    readRowValueByAliases,
    mapSankhyaClienteRow,
    lookupCepAddress,
    updateTenantSyncState,
    loggerError: console.error,
  });
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
  return executeSyncSankhyaProductImagesModuleAction({
    firestore,
    tenantId,
    baseUrl,
    bearerToken,
    xToken,
    fetchImpl: fetch,
    sankhyaProductsPath: SANKHYA_PRODUCTS_PATH,
    tryParseJson,
    toCodeString,
    isZeroCode,
    temporaryImportLimit: TEMPORARY_IMPORT_LIMIT,
    buildSankhyaProductImageChunksSql,
    executeSankhyaDbExplorerQuery,
    readRowValueByAliases,
    readInt,
    detectImageFormat,
    buildFirebaseDownloadUrl,
    buildProductDocId,
    defaultProductMediaScopeKey: DEFAULT_PRODUCT_MEDIA_SCOPE_KEY,
    defaultStorageBucket: DEFAULT_STORAGE_BUCKET,
    admin,
    crypto,
    updateTenantSyncState,
  });
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

exports.manageTenantBillingSelfService = onRequest(
  {
    cors: true,
    region: 'us-central1',
    timeoutSeconds: 60,
    secrets: BILLING_RUNTIME_SECRETS,
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const payload = request.body && typeof request.body === 'object'
      ? request.body
      : {};

    const tenantId = String(payload?.tenantId ?? '').trim();
    const action = normalizeBillingSelfServiceAction(payload?.action);
    const reason = String(payload?.reason ?? '').trim().slice(0, 240);

    if (!tenantId) {
      response.status(400).json({
        error: 'invalid_payload',
        message: 'tenantId e obrigatorio.',
      });
      return;
    }

    if (!action) {
      response.status(400).json({
        error: 'invalid_action',
        message: 'Acao invalida. Use stop_renewal ou cancel_now.',
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

    const result = await executeTenantBillingSelfServiceAction({
      firestore,
      payload,
      tenantId,
      action,
      reason,
      authContext,
      assertTenantBillingActorPermission,
      readCheckoutApiConfig,
      resolveCheckoutApiProviderSelection,
      loadBillingProviderRuntime,
      applyTenantBillingSelfServiceActionToProvider,
      mapBillingStatusToAccountState,
      enforceTenantSeatAllowanceForTenant,
      timestampFromDate: (date) => admin.firestore.Timestamp.fromDate(date),
      billingProviderAsaas: BILLING_PROVIDER_ASAAS,
    });

    response.status(result.status).json(result.body);
  },
);

async function processBillingWebhookEvent({
  firestore,
  providerKey,
  event,
  enabledEvents,
  stripeClient,
  asaasRuntime,
}) {
  return dispatchProcessBillingWebhookEvent({
    firestore,
    providerKey,
    event,
    enabledEvents,
    stripeClient,
    asaasRuntime,
    processStripeWebhookEvent: (input) => processStripeWebhookEventHelper({
      ...input,
      defaultEnabledEvents: STRIPE_DEFAULT_WEBHOOK_EVENTS,
      applyStripeWebhookEventToTenant: ({
        firestore,
        event,
        stripeClient,
      }) => applyStripeWebhookEventToTenantHelper({
        firestore,
        event,
        stripeClient,
        normalizeBillingPlanKey,
        resolveTenantIdFromStripeReferences,
        readStripeSubscriptionLineItems,
        resolveStripePlanMappingByPriceId,
        buildTenantPatchFromStripeSubscription,
        reconcileTenantStripePeriodIfMissing,
        reconcileTenantBillingState,
        enforceTenantSeatAllowanceForTenant,
        billingProviderStripe: BILLING_PROVIDER_STRIPE,
      }),
    }),
    processAsaasWebhookEvent: (input) => processAsaasWebhookEvent({
      ...input,
      defaultEnabledEvents: ASAAS_DEFAULT_WEBHOOK_EVENTS,
      applyAsaasWebhookEventToTenant: ({
        firestore,
        eventPayload,
        eventType,
        asaasRuntime,
      }) => applyAsaasWebhookEventToTenantHelper({
        firestore,
        eventPayload,
        eventType,
        asaasRuntime,
        resolveTenantIdFromAsaasReferences,
        buildTenantPatchFromAsaasEvent,
        enforceTenantSeatAllowanceForTenant,
      }),
    }),
  });
}

async function reconcileTenantBillingState({
  firestore,
  providerKey,
  tenantId,
  stripeClient,
  asaasRuntime,
}) {
  return dispatchReconcileTenantBillingState({
    firestore,
    providerKey,
    tenantId,
    stripeClient,
    asaasRuntime,
    reconcileTenantStripeState: reconcileTenantStripeStateWrapper,
    reconcileTenantAsaasState,
  });
}

async function reconcileTenantStripeStateWrapper({
  firestore,
  stripeClient,
  tenantId,
}) {
  return reconcileTenantStripeState({
    firestore,
    stripeClient,
    tenantId,
    billingProviderStripe: BILLING_PROVIDER_STRIPE,
    readStripeSubscriptionPriceId,
    resolveStripePlanMappingByPriceId,
    buildTenantPatchFromStripeSubscription,
    readStripeSubscriptionPeriodFromInvoices,
  });
}

async function applyTenantBillingActionToProvider({
  providerKey,
  stripeClient,
  asaasRuntime,
  tenantId,
  tenantData,
  action,
  reason,
  actorUid,
}) {
  const applyTenantBillingActionToStripeWithDeps = (input) =>
    applyTenantBillingActionToStripe({
      ...input,
      sanitizeStripeMetadataValue,
    });

  return dispatchApplyTenantBillingActionToProvider({
    providerKey,
    stripeClient,
    asaasRuntime,
    tenantId,
    tenantData,
    action,
    reason,
    actorUid,
    applyTenantBillingActionToStripe: applyTenantBillingActionToStripeWithDeps,
    applyTenantBillingActionToAsaas,
  });
}

async function applyTenantBillingSelfServiceActionToProvider({
  providerKey,
  asaasRuntime,
  tenantData,
  action,
}) {
  return dispatchApplyTenantBillingSelfServiceActionToProvider({
    providerKey,
    asaasRuntime,
    tenantData,
    action,
    applyTenantBillingSelfServiceActionToAsaas,
  });
}

async function createAsaasCheckoutSession({
  firestore,
  tenantId,
  tenantData,
  payload,
  providerSelection,
}) {
  return createAsaasCheckoutSessionHelper({
    firestore,
    tenantId,
    tenantData,
    payload,
    providerSelection,
    billingProviderAsaas: BILLING_PROVIDER_ASAAS,
    normalizeBillingPlanKey,
    resolveAsaasCallbackUrls,
    loadAsaasIntegrationRuntime,
    resolveAsaasPlanMapping,
    buildAsaasCheckoutPayload,
    fetchAsaasApiJson,
  });
}

async function enforceTenantSeatAllowanceForTenant({
  firestore,
  tenantId,
  tenantDoc = null,
  nowDate = new Date(),
}) {
  return enforceTenantSeatAllowanceForTenantHelper({
    firestore,
    tenantId,
    tenantDoc,
    nowDate,
    shouldEnforceTenantSeatAllowance,
    readTenantSeatAllowance,
    readMembershipOrderingMs,
    parseDateToUnixMs,
    writeTenantMembershipAuditEvent,
    seatGraceDays: TENANT_SEAT_OVER_LIMIT_GRACE_DAYS,
    seatEnforcementActorUid: TENANT_SEAT_ENFORCEMENT_ACTOR_UID,
  });
}

async function reconcileTenantAsaasState({ firestore, asaasRuntime, tenantId }) {
  return reconcileTenantAsaasStateHelper({
    firestore,
    asaasRuntime,
    tenantId,
    fetchAsaasApiJson,
    buildTenantPatchFromAsaasEvent,
  });
}

async function applyStripeSeatAddonDeltaToActiveSubscription({
  firestore,
  stripeClient,
  tenantId,
  tenantData,
  billingPlanKey,
  addonSeatsDelta,
  actorUid,
}) {
  return applyStripeSeatAddonDeltaToActiveSubscriptionHelper({
    firestore,
    stripeClient,
    tenantId,
    tenantData,
    billingPlanKey,
    addonSeatsDelta,
    actorUid,
    normalizeBillingPlanKey,
    readNonNegativeInteger,
    resolveStripePlanMappingByPriceId,
    loadStripePlanMapping,
    resolveStripeSeatAddonMappingForBasePlan,
    sanitizeStripeMetadataValue,
    reconcileTenantStripeState: reconcileTenantStripeStateWrapper,
  });
}

exports.auditTenantOwnershipIntegrityDaily = onSchedule(
  { region: 'us-central1', timeoutSeconds: 540, schedule: '17 3 * * *' },
  async () => {
    const firestore = admin.firestore();
    const { processed, violations } = await auditTenantOwnershipIntegrityDaily({
      firestore,
    });

    console.log(
      JSON.stringify({
        action: 'auditTenantOwnershipIntegrityDaily',
        processed,
        violations,
      }),
    );
  },
);