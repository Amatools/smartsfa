async function executeCreateBillingCheckoutSessionAction({
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
  stripeCheckoutFunctionUrl,
  createAsaasCheckoutSession,
  billingProviderStripe,
  billingProviderAsaas,
}) {
  const actorPermission = await assertTenantBillingActorPermission({
    firestore,
    uid: authContext.uid,
    tenantId,
  });
  if (!actorPermission.allowed) {
    return {
      handledByProxy: false,
      status: actorPermission.status,
      body: {
        error: actorPermission.error,
        message: actorPermission.message,
      },
    };
  }

  const tenantDoc = await firestore.collection('tenants').doc(tenantId).get();
  if (!tenantDoc.exists) {
    return {
      handledByProxy: false,
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
      handledByProxy: false,
      status: 409,
      body: {
        error: 'provider_disabled',
        message: `Provider ${billingProvider} nao esta ativo na API Checkout.`,
      },
    };
  }

  if (billingProvider === billingProviderStripe) {
    await proxyBillingRequestToFunction({
      request,
      response,
      targetUrl: stripeCheckoutFunctionUrl,
      method: 'POST',
      extraResponseFields: {
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    });

    return {
      handledByProxy: true,
      status: 200,
      body: null,
    };
  }

  if (billingProvider === billingProviderAsaas) {
    try {
      const checkoutResult = await createAsaasCheckoutSession({
        firestore,
        tenantId,
        tenantData,
        payload,
        providerSelection,
      });

      if (!checkoutResult.ok) {
        return {
          handledByProxy: false,
          status: checkoutResult.status,
          body: {
            error: checkoutResult.error,
            message: checkoutResult.message,
            billingProvider,
            providerSelectionSource: providerSelection.source,
            hasLinkedContract: providerSelection.hasLinkedContract,
          },
        };
      }

      return {
        handledByProxy: false,
        status: checkoutResult.status,
        body: checkoutResult.body,
      };
    } catch (error) {
      return {
        handledByProxy: false,
        status: 502,
        body: {
          error: 'provider_checkout_failed',
          message: error instanceof Error ? error.message : String(error),
          billingProvider,
          providerSelectionSource: providerSelection.source,
          hasLinkedContract: providerSelection.hasLinkedContract,
        },
      };
    }
  }

  return {
    handledByProxy: false,
    status: 400,
    body: {
      error: 'provider_not_supported',
      message: `Provider de billing nao suportado: ${billingProvider}.`,
      billingProvider,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
      activeProviders: checkoutApiConfig.activeProviders,
      preferredProvider: checkoutApiConfig.preferredProvider,
    },
  };
}

module.exports = {
  executeCreateBillingCheckoutSessionAction,
};
