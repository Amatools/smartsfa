function createBillingProviderOrchestration({
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
  constants,
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
}) {
  const {
    STRIPE_DEFAULT_WEBHOOK_EVENTS,
    ASAAS_DEFAULT_WEBHOOK_EVENTS,
    BILLING_PROVIDER_STRIPE,
  } = constants;

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

  async function reconcileTenantAsaasState({
    firestore,
    asaasRuntime,
    tenantId,
  }) {
    return reconcileTenantAsaasStateHelper({
      firestore,
      asaasRuntime,
      tenantId,
      fetchAsaasApiJson,
      buildTenantPatchFromAsaasEvent,
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
          normalizeBillingPlanKey: constants.normalizeBillingPlanKey,
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
      normalizeBillingPlanKey: constants.normalizeBillingPlanKey,
      readNonNegativeInteger,
      resolveStripePlanMappingByPriceId,
      loadStripePlanMapping,
      resolveStripeSeatAddonMappingForBasePlan,
      sanitizeStripeMetadataValue,
      reconcileTenantStripeState: reconcileTenantStripeStateWrapper,
    });
  }

  async function applyAsaasSeatAddonDeltaToActiveSubscription({
    firestore,
    asaasRuntime,
    tenantId,
    tenantData,
    billingPlanKey,
    addonSeatsDelta,
    actorUid,
  }) {
    return applyAsaasSeatAddonDeltaToActiveSubscriptionHelper({
      firestore,
      asaasRuntime,
      tenantId,
      tenantData,
      billingPlanKey,
      addonSeatsDelta,
      actorUid,
      normalizeBillingPlanKey: constants.normalizeBillingPlanKey,
      readNonNegativeInteger,
      loadAsaasInternalPlanMapping,
      resolveAsaasSeatAddonMappingForBasePlan,
      fetchAsaasApiJson,
    });
  }

  return {
    processBillingWebhookEvent,
    reconcileTenantBillingState,
    applyTenantBillingActionToProvider,
    applyTenantBillingSelfServiceActionToProvider,
    applyStripeSeatAddonDeltaToActiveSubscription,
    applyAsaasSeatAddonDeltaToActiveSubscription,
    reconcileTenantAsaasState,
    reconcileTenantStripeStateWrapper,
  };
}

module.exports = {
  createBillingProviderOrchestration,
};
