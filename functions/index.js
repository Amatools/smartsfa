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
  loadAsaasInternalPlanMapping,
  resolveAsaasPlanMapping,
  resolveAsaasSeatAddonMappingForBasePlan,
} = require('./src/billing/asaas_plan_mapping_helpers');
const {
  applyAsaasSeatAddonDeltaToActiveSubscription:
    applyAsaasSeatAddonDeltaToActiveSubscriptionHelper,
} = require('./src/billing/asaas_seat_addon_helpers');
const {
  listAsaasCheckoutPlansForTenant,
} = require('./src/billing/asaas_checkout_plan_listing_helpers');
const {
  createAsaasCheckoutSession: createAsaasCheckoutSessionHelper,
} = require('./src/billing/asaas_checkout_session_helpers');
const {
  createAsaasBillingQuote: createAsaasBillingQuoteHelper,
} = require('./src/billing/asaas_quote_helpers');
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
  executeCreateBillingQuoteAction,
} = require('./src/billing/quote_management_helpers');
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
  executeExpireBillingQuotesHourlyAction,
  executeExpireLegacyOpenBillingQuotesDailyAction,
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
  buildSankhyaOperationTypesSql,
  mapSankhyaOperationTypeRow,
} = require('./src/billing/sankhya_operation_types_data_helpers');
const {
  executeSyncSankhyaProductsModuleAction,
} = require('./src/billing/sankhya_products_sync_management_helpers');
const {
  executeSyncSankhyaClientesModuleAction,
} = require('./src/billing/sankhya_clientes_sync_management_helpers');
const {
  buildClienteDocId,
  buildSankhyaClientesSql,
  mapSankhyaClienteRow,
  lookupCepAddress,
} = require('./src/billing/sankhya_clientes_data_helpers');
const {
  executeSyncSankhyaTaxRulesModuleAction,
} = require('./src/billing/sankhya_tax_rules_sync_management_helpers');
const {
  buildSankhyaTaxRulesSql,
  mapSankhyaTaxRuleRow,
  buildTaxFingerprintKey,
  computeFingerprintHash,
  buildAutoGroupName,
  buildAutoGroupDescription,
  normalizeDigits,
  formatNcmMasked,
  formatCestMasked,
  nullableString,
  sanitizeKeyToken,
  toIsoDateOrNull,
} = require('./src/billing/sankhya_tax_rules_data_helpers');
const {
  executeSyncSankhyaProductImagesModuleAction,
} = require('./src/billing/sankhya_product_images_sync_management_helpers');
const {
  buildSankhyaProductImageChunksSql,
  detectImageFormat,
  buildFirebaseDownloadUrl,
} = require('./src/billing/sankhya_product_images_data_helpers');
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
  authenticateInSankhya,
  readBearerToken,
  toCodeString,
  isZeroCode,
  toNumberOrNull,
  readInt,
  tryParseJson,
  readRowValueByAliases,
  normalizeOrigemMercadoriaCst,
  normalizeSankhyaNumericCodeList,
  createSankhyaDbExplorerQueryExecutor,
} = require('./src/billing/sankhya_runtime_helpers');
const {
  applyTaxGroupsToExistingProducts,
} = require('./src/billing/sankhya_tax_group_product_link_helpers');
const {
  createBillingProviderOrchestration,
} = require('./src/billing/billing_provider_orchestration_helpers');
const {
  verifyFirebaseAuthFromRequest: verifyFirebaseAuthFromRequestHelper,
  normalizeLaunchOrigin,
  resolveRequestIp,
  sha256Hex: sha256HexHelper,
  resolveUserDisplayLabel,
  assertImpersonationSessionConsumable,
  mapImpersonationConsumeError,
} = require('./src/billing/impersonation_auth_helpers');
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
const buildCloudFunctionUrl = (functionName) =>
  `${CLOUD_FUNCTIONS_BASE_URL}/${functionName}`;
const STRIPE_CHECKOUT_FUNCTION_URL =
  buildCloudFunctionUrl('createStripeCheckoutSession');
const STRIPE_PORTAL_FUNCTION_URL =
  buildCloudFunctionUrl('createStripePortalSession');
const STRIPE_LIST_PLANS_FUNCTION_URL =
  buildCloudFunctionUrl('listStripeCheckoutPlans');
const BILLING_PROVIDER_STRIPE = 'stripe';
const BILLING_PROVIDER_ASAAS = 'asaas';
const BILLING_PROVIDER_DEFAULT = BILLING_PROVIDER_STRIPE;
const TENANT_SEAT_OVER_LIMIT_GRACE_DAYS = 3;
const TENANT_SEAT_ENFORCEMENT_ACTOR_UID = 'system_seat_enforcement';

const executeSankhyaDbExplorerQuery = createSankhyaDbExplorerQueryExecutor({
  executeSankhyaDbExplorerQueryAction,
  endpointPaths: SANKHYA_DBEXPLORER_ENDPOINT_PATHS,
  fetchImpl: fetch,
  extractSankhyaXmlError,
  normalizeDbExplorerRows,
});

const {
  processBillingWebhookEvent,
  reconcileTenantBillingState,
  applyTenantBillingActionToProvider,
  applyTenantBillingSelfServiceActionToProvider,
  applyStripeSeatAddonDeltaToActiveSubscription,
  applyAsaasSeatAddonDeltaToActiveSubscription,
} = createBillingProviderOrchestration({
  dispatchProcessBillingWebhookEvent,
  processStripeWebhookEventHelper,
  processAsaasWebhookEvent,
  applyStripeWebhookEventToTenantHelper,
  applyAsaasWebhookEventToTenantHelper,
  dispatchReconcileTenantBillingState,
  reconcileTenantStripeState,
  reconcileTenantAsaasStateHelper,
  dispatchApplyTenantBillingActionToProvider,
  applyTenantBillingActionToStripe,
  applyTenantBillingActionToAsaas,
  dispatchApplyTenantBillingSelfServiceActionToProvider,
  applyTenantBillingSelfServiceActionToAsaas,
  applyStripeSeatAddonDeltaToActiveSubscriptionHelper,
  applyAsaasSeatAddonDeltaToActiveSubscriptionHelper,
  constants: {
    STRIPE_DEFAULT_WEBHOOK_EVENTS,
    ASAAS_DEFAULT_WEBHOOK_EVENTS,
    BILLING_PROVIDER_STRIPE,
    normalizeBillingPlanKey,
  },
  resolveTenantIdFromStripeReferences,
  readStripeSubscriptionLineItems,
  resolveStripePlanMappingByPriceId,
  buildTenantPatchFromStripeSubscription,
  reconcileTenantStripePeriodIfMissing,
  buildTenantPatchFromAsaasEvent,
  resolveTenantIdFromAsaasReferences,
  enforceTenantSeatAllowanceForTenant,
  readStripeSubscriptionPriceId,
  readStripeSubscriptionPeriodFromInvoices,
  fetchAsaasApiJson,
  sanitizeStripeMetadataValue,
  readNonNegativeInteger,
  loadStripePlanMapping,
  resolveStripeSeatAddonMappingForBasePlan,
  loadAsaasInternalPlanMapping,
  resolveAsaasSeatAddonMappingForBasePlan,
});

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

exports.expireBillingQuotesHourly = onSchedule(
  { region: 'us-central1', timeoutSeconds: 540, schedule: '37 * * * *' },
  async () => {
    return executeExpireBillingQuotesHourlyAction({
      firestore: admin.firestore(),
      nowDate: new Date(),
    });
  },
);

exports.expireLegacyOpenBillingQuotesDaily = onSchedule(
  { region: 'us-central1', timeoutSeconds: 540, schedule: '43 4 * * *' },
  async () => {
    return executeExpireLegacyOpenBillingQuotesDailyAction({
      firestore: admin.firestore(),
      nowDate: new Date(),
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

exports.createBillingQuote = onRequest(
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

    const result = await executeCreateBillingQuoteAction({
      firestore,
      payload,
      tenantId,
      authContext,
      assertTenantBillingActorPermission,
      readCheckoutApiConfig,
      resolveCheckoutApiProviderSelection,
      createAsaasBillingQuote,
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
      billingProviderAsaas: BILLING_PROVIDER_ASAAS,
    });

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
      applyAsaasSeatAddonDeltaToActiveSubscription,
      enforceTenantSeatAllowanceForTenant,
      billingProviderStripe: BILLING_PROVIDER_STRIPE,
      billingProviderAsaas: BILLING_PROVIDER_ASAAS,
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
    applyTaxGroupsToExistingProducts: (input) =>
      applyTaxGroupsToExistingProducts({
        ...input,
        normalizeDigits,
      }),
    updateTenantSyncState,
    loggerError: console.error,
  });
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
    lookupCepAddress: async (cep) =>
      lookupCepAddress(cep, {
        fetchImpl: fetch,
        loggerError: console.error,
      }),
    updateTenantSyncState,
    loggerError: console.error,
  });
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
    buildSankhyaProductImageChunksSql: (productCodes) =>
      buildSankhyaProductImageChunksSql(productCodes, {
        chunkSize: SANKHYA_IMAGE_CHUNK_BYTES,
        normalizeCodeList: normalizeSankhyaNumericCodeList,
      }),
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

async function verifyFirebaseAuthFromRequest(request) {
  return verifyFirebaseAuthFromRequestHelper({
    request,
    verifyIdToken: (idToken) => admin.auth().verifyIdToken(idToken),
  });
}

function sha256Hex(value) {
  return sha256HexHelper(value, { crypto });
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

async function createAsaasBillingQuote({
  firestore,
  tenantId,
  tenantData,
  payload,
  providerSelection,
}) {
  return createAsaasBillingQuoteHelper({
    firestore,
    tenantId,
    tenantData,
    payload,
    providerSelection,
    billingProviderAsaas: BILLING_PROVIDER_ASAAS,
    normalizeBillingPlanKey,
    readNonNegativeInteger,
    loadAsaasInternalPlanMapping,
    resolveAsaasSeatAddonMappingForBasePlan,
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