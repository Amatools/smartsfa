async function executeReconcileStripeTenantAction({
  firestore,
  tenantId,
  reason,
  authContext,
  assertPlatformAdminActor,
  loadStripeIntegrationRuntime,
  reconcileTenantBillingState,
  timestampFromDate,
  billingProviderStripe,
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

  try {
    const result = await reconcileTenantBillingState({
      firestore,
      providerKey: billingProviderStripe,
      stripeClient: integrationReady.stripeClient,
      tenantId,
    });

    await firestore.collection('platform_admin_audit').add({
      action: 'billing_state_updated',
      actorUid: authContext.uid,
      actorEmail: authContext.email,
      actorLabel: authContext.email || authContext.uid,
      targetUid: authContext.uid,
      targetEmail: authContext.email,
      targetDisplayName: authContext.email || authContext.uid,
      details: {
        tenantId,
        reason,
        previousBillingStatus: result.previousBillingStatus,
        currentBillingStatus: result.currentBillingStatus,
        source: 'billing_reconcile_tenant',
        billingProvider: billingProviderStripe,
      },
      createdAt: timestampFromDate(new Date()),
    });

    return {
      status: 200,
      body: {
        tenantId,
        stripeSubscriptionId: result.stripeSubscriptionId,
        previousBillingStatus: result.previousBillingStatus,
        currentBillingStatus: result.currentBillingStatus,
        updatedAt: result.updatedAt,
      },
    };
  } catch (error) {
    return {
      status: 500,
      body: {
        error: 'reconcile_tenant_failed',
        message: error instanceof Error ? error.message : String(error),
      },
    };
  }
}

async function executeReconcileAsaasTenantAction({
  firestore,
  tenantId,
  reason,
  authContext,
  assertPlatformAdminActor,
  loadBillingProviderRuntime,
  reconcileTenantBillingState,
  timestampFromDate,
  billingProviderAsaas,
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

  const integrationReady = await loadBillingProviderRuntime({
    firestore,
    providerKey: billingProviderAsaas,
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

  try {
    const result = await reconcileTenantBillingState({
      firestore,
      providerKey: billingProviderAsaas,
      asaasRuntime: {
        environment: integrationReady.environment,
        apiKey: integrationReady.asaasApiKey,
        apiBaseUrl: integrationReady.asaasApiBaseUrl,
      },
      tenantId,
    });

    await firestore.collection('platform_admin_audit').add({
      action: 'billing_state_updated',
      actorUid: authContext.uid,
      actorEmail: authContext.email,
      actorLabel: authContext.email || authContext.uid,
      targetUid: authContext.uid,
      targetEmail: authContext.email,
      targetDisplayName: authContext.email || authContext.uid,
      details: {
        tenantId,
        reason,
        previousBillingStatus: result.previousBillingStatus,
        currentBillingStatus: result.currentBillingStatus,
        source: 'billing_reconcile_tenant_asaas',
        billingProvider: billingProviderAsaas,
      },
      createdAt: timestampFromDate(new Date()),
    });

    return {
      status: 200,
      body: {
        tenantId,
        asaasSubscriptionId: result.asaasSubscriptionId,
        asaasCustomerId: result.asaasCustomerId,
        previousBillingStatus: result.previousBillingStatus,
        currentBillingStatus: result.currentBillingStatus,
        updatedAt: result.updatedAt,
      },
    };
  } catch (error) {
    return {
      status: 500,
      body: {
        error: 'reconcile_tenant_failed',
        message: error instanceof Error ? error.message : String(error),
      },
    };
  }
}

module.exports = {
  executeReconcileStripeTenantAction,
  executeReconcileAsaasTenantAction,
};
