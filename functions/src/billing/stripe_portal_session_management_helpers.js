async function executeCreateStripePortalSessionAction({
  firestore,
  tenantId,
  returnUrl,
  authContext,
  assertTenantBillingActorPermission,
  readCheckoutApiConfig,
  loadStripeIntegrationRuntime,
  billingProviderStripe,
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

  const checkoutApiConfig = await readCheckoutApiConfig(firestore);
  if (!checkoutApiConfig.activeProviders.includes(billingProviderStripe)) {
    return {
      status: 409,
      body: {
        error: 'provider_disabled',
        message:
          'Stripe esta desativado na API Checkout. Habilite Stripe ou use provider Asaas conforme configuracao.',
      },
    };
  }

  const integrationReady = await loadStripeIntegrationRuntime({
    firestore,
    requireWebhookSecret: false,
  });
  if (!integrationReady.ok) {
    return {
      status: integrationReady.status,
      body: {
        error: integrationReady.error,
        message: integrationReady.message,
      },
    };
  }

  const tenantDoc = await firestore.collection('tenants').doc(tenantId).get();
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
  const stripeCustomerId = String(tenantData.stripeCustomerId ?? '').trim();
  if (!stripeCustomerId) {
    return {
      status: 404,
      body: {
        error: 'stripe_customer_missing',
        message: 'Tenant ainda nao possui stripeCustomerId.',
      },
    };
  }

  const portalSession =
    await integrationReady.stripeClient.billingPortal.sessions.create({
      customer: stripeCustomerId,
      return_url: returnUrl,
    });

  return {
    status: 200,
    body: {
      portalUrl: String(portalSession.url ?? '').trim(),
      activeEnvironment: integrationReady.environment,
    },
  };
}

module.exports = {
  executeCreateStripePortalSessionAction,
};
