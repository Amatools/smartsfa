async function executeListBillingCheckoutPlansAction({
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
  stripeListPlansFunctionUrl,
  listAsaasCheckoutPlansForTenant,
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
      targetUrl: stripeListPlansFunctionUrl,
      method: request.method,
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
    const listed = await listAsaasCheckoutPlansForTenant({
      firestore,
      tenantData,
    });

    return {
      handledByProxy: false,
      status: 200,
      body: {
        tenantId,
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
        workspaceType: listed.workspaceType,
        requiredPrefix: listed.requiredPrefix,
        plans: listed.plans,
      },
    };
  }

  return {
    handledByProxy: false,
    status: 200,
    body: {
      tenantId,
      billingProvider,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
      workspaceType: '',
      requiredPrefix: '',
      plans: [],
      message: `Provider de billing nao suportado: ${billingProvider}.`,
    },
  };
}

module.exports = {
  executeListBillingCheckoutPlansAction,
};
