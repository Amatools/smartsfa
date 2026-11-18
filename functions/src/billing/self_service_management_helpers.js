async function executeTenantBillingSelfServiceAction({
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
  timestampFromDate,
  billingProviderAsaas,
  logError = console.error,
}) {
  const actorPermission = await assertTenantBillingActorPermission({
    firestore,
    uid: authContext.uid,
    tenantId,
  });
  if (!actorPermission.allowed) {
    return {
      status: actorPermission.status,
      body: {
        error: actorPermission.error,
        message: actorPermission.message,
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
  const checkoutApiConfig = await readCheckoutApiConfig(firestore);
  const providerSelection = resolveCheckoutApiProviderSelection({
    payload,
    checkoutApiConfig,
    tenantData,
  });
  const billingProvider = providerSelection.provider;

  if (
    !providerSelection.hasLinkedContract &&
    !checkoutApiConfig.activeProviders.includes(billingProvider)
  ) {
    return {
      status: 409,
      body: {
        error: 'provider_disabled',
        message: `Provider ${billingProvider} nao esta ativo na API Checkout.`,
      },
    };
  }

  if (billingProvider !== billingProviderAsaas) {
    return {
      status: 409,
      body: {
        error: 'self_service_action_not_supported_for_provider',
        message:
          'Acoes self-service de cancelamento/interrupcao estao disponiveis apenas para Asaas. Para Stripe, utilize o portal de billing.',
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  const runtime = await loadBillingProviderRuntime({
    firestore,
    providerKey: billingProvider,
    requireWebhookSecret: false,
  });
  if (!runtime.ok) {
    return {
      status: runtime.status,
      body: {
        error: runtime.error,
        message: runtime.message,
        billingProvider,
      },
    };
  }

  const nowDate = new Date();
  const nowIso = nowDate.toISOString();

  let actionResult;
  try {
    actionResult = await applyTenantBillingSelfServiceActionToProvider({
      providerKey: billingProvider,
      asaasRuntime: {
        environment: runtime.environment,
        apiKey: runtime.asaasApiKey,
        apiBaseUrl: runtime.asaasApiBaseUrl,
      },
      tenantData,
      action,
    });
  } catch (error) {
    return {
      status: 502,
      body: {
        error: 'provider_action_failed',
        message: error instanceof Error ? error.message : String(error),
        billingProvider,
      },
    };
  }

  if (!actionResult.applied) {
    return {
      status: 409,
      body: {
        error: 'provider_action_not_applied',
        message: actionResult.message,
        billingProvider,
        requestedAction: action,
        providerAction: actionResult.action,
      },
    };
  }

  const nextBillingStatus = String(
    actionResult.billingStatus ||
      (action === 'cancel_now' ? 'canceled' : 'suspended'),
  )
    .trim()
    .toLowerCase();

  const patch = {
    billingProvider,
    billingUpdatedAt: nowIso,
    billingStatus: nextBillingStatus,
    billingAccountState: mapBillingStatusToAccountState(nextBillingStatus),
    billingPastDueSinceAt: '',
    billingSuspendedAt:
      nextBillingStatus === 'active' || nextBillingStatus === 'trial'
        ? ''
        : nowIso,
    billingLastSelfServiceAction: action,
    billingLastSelfServiceReason: reason,
    billingLastSelfServiceActorUid: authContext.uid,
    billingLastSelfServiceActorEmail: authContext.email,
    billingLastSelfServiceAt: nowIso,
  };

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
    logError('manageTenantBillingSelfService seat enforcement failed', {
      tenantId,
      action,
      error: seatEnforcementError,
    });
  }

  await firestore.collection('tenant_billing_audit').add({
    action: `self_service_${action}`,
    tenantId,
    actorUid: authContext.uid,
    actorEmail: authContext.email,
    actorLabel: authContext.email || authContext.uid,
    details: {
      reason,
      billingProvider,
      providerAction: actionResult.action,
      providerMessage: actionResult.message,
      billingStatus: patch.billingStatus,
      billingAccountState: patch.billingAccountState,
      seatEnforcementSummary,
      seatEnforcementError,
    },
    createdAt: timestampFromDate(nowDate),
  });

  return {
    status: 200,
    body: {
      tenantId,
      billingProvider,
      requestedAction: action,
      providerAction: actionResult.action,
      message: actionResult.message,
      billingStatus: patch.billingStatus,
      billingAccountState: patch.billingAccountState,
      updatedAt: patch.billingUpdatedAt,
      seatEnforcementSummary,
      seatEnforcementError,
    },
  };
}

module.exports = {
  executeTenantBillingSelfServiceAction,
};
