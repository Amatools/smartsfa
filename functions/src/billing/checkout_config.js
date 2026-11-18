const { isValidHttpAbsoluteUrl } = require('./shared_helpers');
const { normalizeBillingProviderKey } = require('./provider_resolution');

const BILLING_PROVIDER_STRIPE = 'stripe';
const BILLING_PROVIDER_ASAAS = 'asaas';

async function readCheckoutApiConfig(firestore) {
  const doc = await firestore.collection('billing_integrations').doc('checkout_api').get();
  const data = doc.data() || {};

  const activeProvidersRaw = Array.isArray(data.activeProviders)
    ? data.activeProviders
    : [];
  const normalizedActiveProviders = new Set(
    activeProvidersRaw
      .map((value) => normalizeBillingProviderKey(value))
      .filter(
        (value) =>
          value === BILLING_PROVIDER_STRIPE || value === BILLING_PROVIDER_ASAAS,
      ),
  );

  if (normalizedActiveProviders.size === 0) {
    normalizedActiveProviders.add(BILLING_PROVIDER_STRIPE);
  }

  const preferredProviderCandidate = normalizeBillingProviderKey(
    data.preferredProvider,
  );
  const preferredProvider = normalizedActiveProviders.has(preferredProviderCandidate)
    ? preferredProviderCandidate
    : normalizedActiveProviders.has(BILLING_PROVIDER_STRIPE)
      ? BILLING_PROVIDER_STRIPE
      : [...normalizedActiveProviders][0];

  return {
    activeProviders: [...normalizedActiveProviders],
    preferredProvider,
  };
}

function resolveAsaasCallbackUrls({
  payload,
  tenantData,
  tenantId,
}) {
  const payloadSuccess = String(payload?.successUrl ?? '').trim();
  const payloadCancel = String(payload?.cancelUrl ?? '').trim();
  const payloadExpired = String(payload?.expiredUrl ?? '').trim();
  const tenantSuccess = String(tenantData?.billingCheckoutSuccessUrl ?? '').trim();
  const tenantCancel = String(tenantData?.billingCheckoutCancelUrl ?? '').trim();
  const tenantExpired = String(tenantData?.billingCheckoutExpiredUrl ?? '').trim();

  const fallbackBase =
    String(process.env.BILLING_CHECKOUT_CALLBACK_BASE_URL ?? '').trim() ||
    'https://portal.smartsfa.com.br';

  const normalizedFallbackBase = fallbackBase.endsWith('/')
    ? fallbackBase.slice(0, -1)
    : fallbackBase;

  const fallbackSuccess =
    `${normalizedFallbackBase}/billing/checkout/success` +
    `?tenantId=${encodeURIComponent(tenantId)}`;
  const fallbackCancel =
    `${normalizedFallbackBase}/billing/checkout/cancel` +
    `?tenantId=${encodeURIComponent(tenantId)}`;
  const fallbackExpired =
    `${normalizedFallbackBase}/billing/checkout/expired` +
    `?tenantId=${encodeURIComponent(tenantId)}`;

  const successUrl = payloadSuccess || tenantSuccess || fallbackSuccess;
  const cancelUrl = payloadCancel || tenantCancel || fallbackCancel;
  const expiredUrl = payloadExpired || tenantExpired || fallbackExpired;

  if (!isValidHttpAbsoluteUrl(successUrl) || !isValidHttpAbsoluteUrl(cancelUrl)) {
    return {
      ok: false,
      error: 'invalid_callback_url',
      message:
        'successUrl e cancelUrl devem ser URLs absolutas http(s).',
      callback: null,
    };
  }

  const callback = {
    successUrl,
    cancelUrl,
  };
  if (isValidHttpAbsoluteUrl(expiredUrl)) {
    callback.expiredUrl = expiredUrl;
  }

  return {
    ok: true,
    error: '',
    message: '',
    callback,
  };
}

module.exports = {
  readCheckoutApiConfig,
  resolveAsaasCallbackUrls,
};
