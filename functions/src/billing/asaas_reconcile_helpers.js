async function reconcileTenantAsaasState({
  firestore,
  asaasRuntime,
  tenantId,
  fetchAsaasApiJson,
  buildTenantPatchFromAsaasEvent,
}) {
  const normalizedTenantId = String(tenantId ?? '').trim();
  if (!normalizedTenantId) {
    throw new Error('tenantId invalido para reconciliacao Asaas.');
  }

  const apiKey = String(asaasRuntime?.apiKey ?? '').trim();
  const apiBaseUrl = String(asaasRuntime?.apiBaseUrl ?? '').trim();
  if (!apiKey || !apiBaseUrl) {
    throw new Error('Runtime Asaas indisponivel para reconciliacao.');
  }

  const tenantRef = firestore.collection('tenants').doc(normalizedTenantId);
  const tenantDoc = await tenantRef.get();
  if (!tenantDoc.exists) {
    throw new Error('Tenant nao encontrado para reconciliacao.');
  }

  const tenantData = tenantDoc.data() || {};
  const previousBillingStatus = String(tenantData.billingStatus ?? '').trim();
  const asaasSubscriptionId = String(tenantData.asaasSubscriptionId ?? '').trim();
  const asaasPaymentId = String(tenantData.asaasPaymentId ?? '').trim();
  const asaasCustomerId = String(tenantData.asaasCustomerId ?? '').trim();

  let eventPayload = null;
  if (asaasSubscriptionId) {
    const subscription = await fetchAsaasApiJson({
      apiBaseUrl,
      apiKey,
      path: `/subscriptions/${encodeURIComponent(asaasSubscriptionId)}`,
    });
    eventPayload = {
      id: `reconcile_sub_${Date.now()}`,
      event: 'SUBSCRIPTION_UPDATED',
      dateCreated: new Date().toISOString(),
      subscription,
    };
  } else if (asaasPaymentId) {
    const payment = await fetchAsaasApiJson({
      apiBaseUrl,
      apiKey,
      path: `/payments/${encodeURIComponent(asaasPaymentId)}`,
    });
    eventPayload = {
      id: `reconcile_pay_${Date.now()}`,
      event: 'PAYMENT_UPDATED',
      dateCreated: new Date().toISOString(),
      payment,
    };
  } else if (asaasCustomerId) {
    const paymentsList = await fetchAsaasApiJson({
      apiBaseUrl,
      apiKey,
      path: '/payments',
      query: {
        customer: asaasCustomerId,
        limit: '1',
        offset: '0',
      },
    });

    const payment = Array.isArray(paymentsList?.data) ? paymentsList.data[0] : null;
    if (payment && typeof payment === 'object') {
      eventPayload = {
        id: `reconcile_pay_${Date.now()}`,
        event: 'PAYMENT_UPDATED',
        dateCreated: new Date().toISOString(),
        payment,
      };
    }
  }

  if (!eventPayload) {
    throw new Error(
      'Tenant sem referencia suficiente no Asaas (asaasSubscriptionId, asaasPaymentId ou asaasCustomerId).',
    );
  }

  const patch = buildTenantPatchFromAsaasEvent({
    eventPayload,
    eventType: String(eventPayload.event ?? '').trim(),
    currentTenantData: tenantData,
    webhookEnvironment: String(asaasRuntime?.environment ?? '').trim(),
  });

  await tenantRef.set(patch, { merge: true });

  try {
    const nowIso = new Date().toISOString();
    await firestore.collection('billing_provider_refs').doc(normalizedTenantId).set(
      {
        tenantId: normalizedTenantId,
        billingProvider: 'asaas',
        asaasCustomerId: String(
          patch.asaasCustomerId ?? asaasCustomerId ?? '',
        ).trim(),
        asaasSubscriptionId: String(
          patch.asaasSubscriptionId ?? asaasSubscriptionId ?? '',
        ).trim(),
        asaasPaymentId: String(patch.asaasPaymentId ?? asaasPaymentId ?? '').trim(),
        lastReconciledAt: nowIso,
        lastReconciledSource: 'asaas_reconcile',
        updatedAt: nowIso,
      },
      { merge: true },
    );
  } catch (error) {
    console.error('asaas reconcile provider refs persistence failed', {
      tenantId: normalizedTenantId,
      error: error instanceof Error ? error.message : String(error),
    });
  }

  return {
    asaasSubscriptionId: String(patch.asaasSubscriptionId ?? asaasSubscriptionId).trim(),
    asaasCustomerId: String(patch.asaasCustomerId ?? asaasCustomerId).trim(),
    previousBillingStatus,
    currentBillingStatus: String(patch.billingStatus ?? '').trim(),
    updatedAt: String(patch.billingUpdatedAt ?? '').trim(),
  };
}

module.exports = {
  reconcileTenantAsaasState,
};
