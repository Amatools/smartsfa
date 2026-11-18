async function executeCreateBillingPortalSessionAction({
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
  stripePortalFunctionUrl,
  readAsaasIntegrationConfig,
  resolveAsaasPortalFallbackUrl,
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
      targetUrl: stripePortalFunctionUrl,
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
    const asaasConfig = await readAsaasIntegrationConfig(firestore);
    const portalUrl = resolveAsaasPortalFallbackUrl({ tenantData });

    if (!portalUrl) {
      return {
        handledByProxy: false,
        status: 409,
        body: {
          error: 'portal_reference_not_found',
          message:
            'Nao ha referencia Asaas para autoatendimento deste tenant (invoice/checkouts). Inicie um checkout e confirme pagamento para habilitar o acesso rapido.',
          billingProvider,
          providerSelectionSource: providerSelection.source,
          hasLinkedContract: providerSelection.hasLinkedContract,
          activeEnvironment: asaasConfig.activeEnvironment,
        },
      };
    }

    return {
      handledByProxy: false,
      status: 200,
      body: {
        portalUrl,
        activeEnvironment: asaasConfig.activeEnvironment,
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
        message:
          'Asaas nao possui portal de assinatura equivalente ao Stripe Billing Portal. Retornando link operacional mais recente (invoice/checkout) para autoatendimento.',
      },
    };
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
  executeCreateBillingPortalSessionAction,
};
