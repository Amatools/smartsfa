async function executeManageTenantBillingStateAction({
  firestore,
  tenantId,
  action,
  reason,
  providerHint,
  authContext,
  assertPlatformAdminActor,
  readCheckoutApiConfig,
  resolveTenantBillingProviderKey,
  loadBillingProviderRuntime,
  applyTenantBillingActionToProvider,
  enforceTenantSeatAllowanceForTenant,
  timestampFromDate,
  billingProviderStripe,
  billingProviderAsaas,
  logError = console.error,
}) {
  const platformAccess = await assertPlatformAdminActor({
    firestore,
    uid: authContext.uid,
  });
  if (!platformAccess.allowed) {
    return {
      status: platformAccess.status,
      body: {
        error: platformAccess.error,
        message: platformAccess.message,
      },
    };
  }

  const tenantRef = firestore.collection('tenants').doc(tenantId);
  const tenantDoc = await tenantRef.get();
  if (!tenantDoc.exists) {
    return {
      status: 404,
      body: {
        error: 'tenant_not_found',
        message: 'Tenant nao encontrado.',
      },
    };
  }

  const tenantData = tenantDoc.data() || {};
  const nowDate = new Date();
  const nowIso = nowDate.toISOString();
  const previousBillingStatus = String(tenantData.billingStatus ?? '').trim();
  const checkoutApiConfig = await readCheckoutApiConfig(firestore);
  const billingProvider = resolveTenantBillingProviderKey({
    tenantData,
    providerHint,
  });

  const effectiveBillingProvider =
    billingProvider === billingProviderStripe ||
    billingProvider === billingProviderAsaas
      ? billingProvider
      : checkoutApiConfig.preferredProvider;

  if (!checkoutApiConfig.activeProviders.includes(effectiveBillingProvider)) {
    return {
      status: 409,
      body: {
        error: 'provider_disabled',
        message: `Provider ${effectiveBillingProvider} nao esta ativo na API Checkout.`,
      },
    };
  }

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
  } else if (action === 'clear_plan_link') {
    patch.billingStatus = 'no_plan';
    patch.billingAccountState = 'inactive';
    patch.billingProvider = '';
    patch.billingContractProvider = '';
    patch.billingContractLinkedAt = '';
    patch.billingPlanKey = '';
    patch.billingCycle = '';
    patch.stripePriceId = '';
    patch.stripeCustomerId = '';
    patch.stripeSubscriptionId = '';
    patch.stripeCheckoutSessionId = '';
    patch.stripeInvoiceId = '';
    patch.stripePaymentIntentId = '';
    patch.asaasCustomerId = '';
    patch.asaasSubscriptionId = '';
    patch.asaasCheckoutId = '';
    patch.asaasPaymentId = '';
    patch.asaasInvoiceUrl = '';
    patch.asaasBankSlipUrl = '';
    patch.asaasInvoiceNumber = '';
    patch.asaasInvoiceStatus = '';
    patch.asaasBillingType = '';
    patch.asaasLastEventId = '';
    patch.asaasLastEventType = '';
    patch.asaasWebhookEnvironment = '';
    patch.billingCurrentPeriodStartAt = '';
    patch.billingCurrentPeriodEndAt = '';
    patch.billingSuspendedAt = nowIso;
    patch.billingSeatsIncluded = '';
    patch.billingSeatsAddon = '';
    patch.billingSeatAddons = '';
    patch.billingSeatAddonPlanKey = '';
    patch.billingSeatAddonUnitPriceCents = '';
    patch.billingDelinquencyStage = 'none';
    auditAction = 'billing_plan_unlinked_and_blocked';
  }

  let stripeApplied = false;
  let stripeAction = 'not_attempted';
  let stripeMessage = '';
  let providerApplied = false;
  let providerAction = 'not_attempted';
  let providerMessage = '';

  const integrationReady = await loadBillingProviderRuntime({
    firestore,
    providerKey: effectiveBillingProvider,
    requireWebhookSecret: false,
  });
  if (integrationReady.ok) {
    try {
      const reflection = await applyTenantBillingActionToProvider({
        providerKey: effectiveBillingProvider,
        stripeClient: integrationReady.stripeClient,
        asaasRuntime: {
          environment: integrationReady.environment,
          apiKey: integrationReady.asaasApiKey,
          apiBaseUrl: integrationReady.asaasApiBaseUrl,
        },
        tenantId,
        tenantData,
        action,
        reason,
        actorUid: authContext.uid,
      });
      providerApplied = reflection.applied;
      providerAction = reflection.action;
      providerMessage = reflection.message;
      stripeApplied = reflection.applied;
      stripeAction = reflection.action;
      stripeMessage = reflection.message;
    } catch (error) {
      return {
        status: 502,
        body: {
          error: 'provider_action_failed',
          message: error instanceof Error ? error.message : String(error),
        },
      };
    }
  } else {
    providerAction = 'integration_not_ready';
    providerMessage = integrationReady.message;
    stripeAction = 'integration_not_ready';
    stripeMessage = integrationReady.message;
  }

  await tenantRef.set(patch, { merge: true });

  let seatEnforcementSummary = null;
  let seatEnforcementError = '';
  try {
    seatEnforcementSummary = await enforceTenantSeatAllowanceForTenant({
      firestore,
      tenantId,
      nowDate,
    });
  } catch (error) {
    seatEnforcementError =
      error instanceof Error ? error.message : String(error);
    logError('manageTenantBillingState seat enforcement failed', {
      tenantId,
      action,
      error: seatEnforcementError,
    });
  }

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
      billingProvider: effectiveBillingProvider,
      providerApplied,
      providerAction,
      providerMessage,
      stripeApplied,
      stripeAction,
      stripeMessage,
      seatEnforcementSummary,
      seatEnforcementError,
    },
    createdAt: timestampFromDate(nowDate),
  });

  return {
    status: 200,
    body: {
      tenantId,
      previousBillingStatus,
      currentBillingStatus: patch.billingStatus,
      currentBillingAccountState: patch.billingAccountState,
      billingStatus: patch.billingStatus,
      billingGraceUntilAt: patch.billingGraceUntilAt,
      billingSuspendedAt: patch.billingSuspendedAt,
      updatedAt: patch.billingUpdatedAt,
      billingProvider: effectiveBillingProvider,
      providerApplied,
      providerAction,
      providerMessage,
      stripeApplied,
      stripeAction,
      stripeMessage,
      seatEnforcementSummary,
      seatEnforcementError,
    },
  };
}

module.exports = {
  executeManageTenantBillingStateAction,
};
