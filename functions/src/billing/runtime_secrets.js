const crypto = require('node:crypto');
const Stripe = require('stripe');

const ASAAS_SANDBOX_API_BASE_URL = 'https://sandbox.asaas.com/api/v3';
const ASAAS_PRODUCTION_API_BASE_URL = 'https://api.asaas.com/v3';
const STRIPE_CLIENT_CACHE = new Map();

function getAsaasWebhookTokenForEnvironment(environment) {
  if (environment === 'production') {
    return String(process.env.ASAAS_WEBHOOK_TOKEN_PRODUCTION ?? '').trim();
  }
  return String(process.env.ASAAS_WEBHOOK_TOKEN_SANDBOX ?? '').trim();
}

function getAsaasApiKeyForEnvironment(environment) {
  if (environment === 'production') {
    return String(process.env.ASAAS_API_KEY_PRODUCTION ?? '').trim();
  }
  return String(process.env.ASAAS_API_KEY_SANDBOX ?? '').trim();
}

function getAsaasApiBaseUrlForEnvironment(environment) {
  return environment === 'production'
    ? ASAAS_PRODUCTION_API_BASE_URL
    : ASAAS_SANDBOX_API_BASE_URL;
}

function createAsaasWebhookFallbackEventId(payload) {
  const serializedPayload = JSON.stringify(payload ?? {});
  const hash = crypto
    .createHash('sha256')
    .update(serializedPayload)
    .digest('hex')
    .slice(0, 24);
  return `asaas_${Date.now()}_${hash}`;
}

function getStripeSecretForEnvironment(environment) {
  if (environment === 'live') {
    return String(process.env.STRIPE_SK_LIVE ?? '').trim();
  }
  return String(process.env.STRIPE_SK_TEST ?? '').trim();
}

function getStripeWebhookSecretForEnvironment(environment) {
  if (environment === 'live') {
    return String(process.env.STRIPE_WHSEC_LIVE ?? '').trim();
  }
  return String(process.env.STRIPE_WHSEC_TEST ?? '').trim();
}

function getStripeClient(secretKey) {
  const normalizedSecret = String(secretKey ?? '').trim();
  if (!normalizedSecret) {
    throw new Error('Missing Stripe secret key.');
  }

  if (!STRIPE_CLIENT_CACHE.has(normalizedSecret)) {
    STRIPE_CLIENT_CACHE.set(normalizedSecret, new Stripe(normalizedSecret));
  }
  return STRIPE_CLIENT_CACHE.get(normalizedSecret);
}

module.exports = {
  createAsaasWebhookFallbackEventId,
  getAsaasApiBaseUrlForEnvironment,
  getAsaasApiKeyForEnvironment,
  getAsaasWebhookTokenForEnvironment,
  getStripeClient,
  getStripeSecretForEnvironment,
  getStripeWebhookSecretForEnvironment,
};
