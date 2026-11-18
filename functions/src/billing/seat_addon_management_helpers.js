async function executeUpdateBillingSeatAddonsAction({
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
  billingProviderStripe,
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

  if (billingProvider !== billingProviderStripe) {
    return {
      status: 409,
      body: {
        error: 'seat_addon_update_not_supported_for_provider',
        message:
          'Ajuste self-service de seats extras esta disponivel apenas para Stripe neste fluxo.',
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

  let updateResult;
  try {
    updateResult = await applyStripeSeatAddonDeltaToActiveSubscription({
      firestore,
      stripeClient: runtime.stripeClient,
      tenantId,
      tenantData,
      billingPlanKey,
      addonSeatsDelta,
      actorUid: authContext.uid,
    });
  } catch (error) {
    return {
      status: 502,
      body: {
        error: 'seat_addon_update_failed',
        message: error instanceof Error ? error.message : String(error),
        billingProvider,
      },
    };
  }

  if (!updateResult.applied) {
    return {
      status: updateResult.status || 409,
      body: {
        error: updateResult.error,
        message: updateResult.message,
        billingProvider,
        action: updateResult.action,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  let seatEnforcementSummary = null;
  let seatEnforcementError = '';
  try {
    seatEnforcementSummary = await enforceTenantSeatAllowanceForTenant({
      firestore,
      tenantId,
      nowDate: new Date(),
    });
  } catch (error) {
    seatEnforcementError =
      error instanceof Error ? error.message : String(error);
    logError('updateBillingSeatAddons seat enforcement failed', {
      tenantId,
      addonSeatsDelta,
      error: seatEnforcementError,
    });
  }

  return {
    status: 200,
    body: {
      tenantId,
      billingProvider,
      billingPlanKey: updateResult.billingPlanKey,
      addedSeats: updateResult.addedSeats,
      previousAddonSeats: updateResult.previousAddonSeats,
      currentAddonSeats: updateResult.currentAddonSeats,
      stripeSubscriptionId: updateResult.stripeSubscriptionId,
      stripeAddonPriceId: updateResult.stripeAddonPriceId,
      invoiceId: updateResult.invoiceId,
      invoiceStatus: updateResult.invoiceStatus,
      invoiceUrl: updateResult.invoiceUrl,
      message: updateResult.message,
      seatEnforcementSummary,
      seatEnforcementError,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
    },
  };
}

module.exports = {
  executeUpdateBillingSeatAddonsAction,
};
