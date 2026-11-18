async function createAsaasCheckoutSession({
  firestore,
  tenantId,
  tenantData,
  payload,
  providerSelection,
  billingProviderAsaas,
  normalizeBillingPlanKey,
  resolveAsaasCallbackUrls,
  loadAsaasIntegrationRuntime,
  resolveAsaasPlanMapping,
  buildAsaasCheckoutPayload,
  fetchAsaasApiJson,
}) {
  const billingPlanKey = normalizeBillingPlanKey(payload?.billingPlanKey);
  if (!billingPlanKey) {
    return {
      ok: false,
      status: 400,
      error: 'invalid_payload',
      message: 'billingPlanKey e obrigatorio.',
      body: null,
    };
  }

  const callbackResolution = resolveAsaasCallbackUrls({
    payload,
    tenantData,
    tenantId,
  });
  if (!callbackResolution.ok) {
    return {
      ok: false,
      status: 400,
      error: callbackResolution.error,
      message: callbackResolution.message,
      body: null,
    };
  }

  const runtime = await loadAsaasIntegrationRuntime({
    firestore,
    requireWebhookSecret: false,
  });
  if (!runtime.ok) {
    return {
      ok: false,
      status: runtime.status,
      error: runtime.error,
      message: runtime.message,
      body: null,
    };
  }

  const resolvedPlan = await resolveAsaasPlanMapping({
    firestore,
    tenantData,
    billingPlanKey,
  });
  if (!resolvedPlan.ok) {
    return {
      ok: false,
      status: resolvedPlan.status,
      error: resolvedPlan.error,
      message: resolvedPlan.message,
      body: null,
    };
  }

  const requestPayload = buildAsaasCheckoutPayload({
    payload,
    tenantId,
    tenantData,
    resolvedPlan,
    callback: callbackResolution.callback,
  });

  const checkoutResponse = await fetchAsaasApiJson({
    apiBaseUrl: runtime.asaasApiBaseUrl,
    apiKey: runtime.asaasApiKey,
    path: '/checkouts',
    method: 'POST',
    body: requestPayload,
  });

  const checkoutSessionId = String(checkoutResponse?.id ?? '').trim();
  const checkoutUrl = String(checkoutResponse?.link ?? '').trim() ||
    (checkoutSessionId
      ? `https://asaas.com/checkoutSession/show?id=${encodeURIComponent(checkoutSessionId)}`
      : '');

  if (!checkoutSessionId || !checkoutUrl) {
    return {
      ok: false,
      status: 502,
      error: 'provider_invalid_response',
      message: 'Asaas retornou resposta invalida ao criar checkout.',
      body: null,
    };
  }

  const nowIso = new Date().toISOString();
  await firestore.collection('tenants').doc(tenantId).set(
    {
      billingProvider: billingProviderAsaas,
      billingPlanKey: resolvedPlan.mapping.billingPlanKey,
      billingUpdatedAt: nowIso,
      asaasCheckoutId: checkoutSessionId,
      asaasCheckoutLink: checkoutUrl,
      asaasCheckoutStatus: String(checkoutResponse?.status ?? '').trim(),
      asaasCheckoutExternalReference: String(
        checkoutResponse?.externalReference || requestPayload.externalReference || '',
      ).trim(),
      asaasCheckoutLastCreatedAt: nowIso,
      billingLastCheckoutProvider: billingProviderAsaas,
      billingLastCheckoutCreatedAt: nowIso,
    },
    { merge: true },
  );

  return {
    ok: true,
    status: 200,
    error: '',
    message: '',
    body: {
      tenantId,
      billingProvider: billingProviderAsaas,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
      activeEnvironment: runtime.environment,
      checkoutSessionId,
      checkoutUrl,
      asaasCheckoutId: checkoutSessionId,
      asaasCheckoutUrl: checkoutUrl,
      asaasCheckoutStatus: String(checkoutResponse?.status ?? '').trim(),
      billingPlanKey: resolvedPlan.mapping.billingPlanKey,
    },
  };
}

module.exports = {
  createAsaasCheckoutSession,
};
