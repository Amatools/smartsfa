function normalizeQuoteId(rawValue) {
  return String(rawValue ?? '').trim();
}

function normalizeAsIsoDate(rawValue) {
  const value = String(rawValue ?? '').trim();
  if (!value) {
    return '';
  }

  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) {
    return '';
  }
  return parsed.toISOString();
}

async function loadAsaasQuoteForCheckout({
  firestore,
  quoteId,
  tenantId,
  billingProviderAsaas,
  normalizedBillingPlanKey,
}) {
  const normalizedQuoteId = normalizeQuoteId(quoteId);
  if (!normalizedQuoteId) {
    return {
      ok: false,
      status: 400,
      error: 'invalid_quote',
      message: 'quoteId invalido.',
      quote: null,
    };
  }

  const quoteDoc = await firestore.collection('billing_quotes').doc(normalizedQuoteId).get();
  if (!quoteDoc.exists) {
    return {
      ok: false,
      status: 404,
      error: 'quote_not_found',
      message: 'Quote nao encontrada para este tenant.',
      quote: null,
    };
  }

  const quoteData = quoteDoc.data() || {};
  const quoteTenantId = String(quoteData.tenantId ?? '').trim();
  const quoteProvider = String(quoteData.billingProvider ?? '').trim().toLowerCase();
  const quotePlanKey = String(
    quoteData.billingPlanKey ?? quoteData.planKey ?? '',
  )
    .trim()
    .toLowerCase();
  const quoteStatus = String(quoteData.status ?? '').trim().toLowerCase();

  if (
    quoteTenantId !== String(tenantId ?? '').trim() ||
    quoteProvider !== String(billingProviderAsaas ?? '').trim().toLowerCase()
  ) {
    return {
      ok: false,
      status: 409,
      error: 'invalid_quote_scope',
      message: 'Quote nao pertence a este tenant/provider.',
      quote: null,
    };
  }

  if (quotePlanKey !== normalizedBillingPlanKey) {
    return {
      ok: false,
      status: 409,
      error: 'invalid_quote_plan',
      message: 'Quote nao corresponde ao billingPlanKey informado.',
      quote: null,
    };
  }

  if (quoteStatus !== 'open') {
    return {
      ok: false,
      status: 409,
      error: 'quote_not_open',
      message: 'Quote nao esta aberta para checkout.',
      quote: null,
    };
  }

  const expiresAtIso = normalizeAsIsoDate(quoteData.expiresAt);
  if (!expiresAtIso) {
    return {
      ok: false,
      status: 409,
      error: 'invalid_quote_expiration',
      message: 'Quote sem expiracao valida.',
      quote: null,
    };
  }

  const nowMs = Date.now();
  if (new Date(expiresAtIso).getTime() <= nowMs) {
    return {
      ok: false,
      status: 409,
      error: 'quote_expired',
      message: 'Quote expirada. Gere uma nova cotacao antes do checkout.',
      quote: null,
    };
  }

  const totalAmountCents = Number(quoteData.totalAmountCents ?? 0);
  if (!Number.isFinite(totalAmountCents) || totalAmountCents <= 0) {
    return {
      ok: false,
      status: 409,
      error: 'invalid_quote_amount',
      message: 'Quote com valor total invalido para checkout.',
      quote: null,
    };
  }

  return {
    ok: true,
    status: 200,
    error: '',
    message: '',
    quote: {
      quoteId: normalizedQuoteId,
      totalAmountCents: Math.floor(totalAmountCents),
      expiresAt: expiresAtIso,
    },
  };
}

async function markAsaasQuoteUsed({
  firestore,
  quoteId,
  checkoutSessionId,
  nowIso,
}) {
  const normalizedQuoteId = normalizeQuoteId(quoteId);
  if (!normalizedQuoteId) {
    return;
  }

  await firestore.collection('billing_quotes').doc(normalizedQuoteId).set(
    {
      status: 'used',
      usedAt: nowIso,
      usedByCheckoutId: String(checkoutSessionId ?? '').trim(),
      updatedAt: nowIso,
    },
    { merge: true },
  );
}

async function persistAsaasProviderCheckoutRef({
  firestore,
  tenantId,
  checkoutSessionId,
  checkoutResponse,
  quoteId,
  nowIso,
  billingProviderAsaas,
}) {
  const normalizedTenantId = String(tenantId ?? '').trim();
  if (!normalizedTenantId) {
    return;
  }

  const normalizedCheckoutId = String(checkoutSessionId ?? '').trim();
  if (!normalizedCheckoutId) {
    return;
  }

  const normalizedSubscriptionId = String(
    checkoutResponse?.subscription ?? checkoutResponse?.subscriptionId ?? '',
  ).trim();

  await firestore.collection('billing_provider_refs').doc(normalizedTenantId).set(
    {
      tenantId: normalizedTenantId,
      billingProvider: billingProviderAsaas,
      asaasCheckoutId: normalizedCheckoutId,
      asaasSubscriptionId: normalizedSubscriptionId,
      asaasLastCheckoutStatus: String(checkoutResponse?.status ?? '').trim(),
      asaasLastCheckoutQuoteId: String(quoteId ?? '').trim(),
      asaasLastCheckoutAt: nowIso,
      updatedAt: nowIso,
    },
    { merge: true },
  );
}

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

  const quoteId = normalizeQuoteId(payload?.quoteId);
  if (!quoteId) {
    return {
      ok: false,
      status: 400,
      error: 'invalid_payload',
      message: 'quoteId e obrigatorio para checkout Asaas.',
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

  const quoteResolution = await loadAsaasQuoteForCheckout({
    firestore,
    quoteId,
    tenantId,
    billingProviderAsaas,
    normalizedBillingPlanKey: billingPlanKey,
  });
  if (!quoteResolution.ok) {
    return {
      ok: false,
      status: quoteResolution.status,
      error: quoteResolution.error,
      message: quoteResolution.message,
      body: null,
    };
  }
  const quoteForCheckout = quoteResolution.quote;

  const effectiveResolvedPlan = {
    ...resolvedPlan,
    mapping: {
      ...resolvedPlan.mapping,
      amount: Number((quoteForCheckout.totalAmountCents / 100).toFixed(2)),
    },
  };

  const requestPayload = buildAsaasCheckoutPayload({
    payload,
    tenantId,
    tenantData,
    resolvedPlan: effectiveResolvedPlan,
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
  await markAsaasQuoteUsed({
    firestore,
    quoteId: quoteForCheckout.quoteId,
    checkoutSessionId,
    nowIso,
  });

  await persistAsaasProviderCheckoutRef({
    firestore,
    tenantId,
    checkoutSessionId,
    checkoutResponse,
    quoteId: quoteForCheckout.quoteId,
    nowIso,
    billingProviderAsaas,
  });

  await firestore.collection('tenants').doc(tenantId).set(
    {
      billingProvider: billingProviderAsaas,
      billingPlanKey: resolvedPlan.mapping.billingPlanKey,
      billingQuoteId: quoteForCheckout.quoteId,
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
      quoteId: quoteForCheckout.quoteId,
    },
  };
}

module.exports = {
  createAsaasCheckoutSession,
};
