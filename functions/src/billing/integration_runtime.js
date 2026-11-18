const { normalizeBillingProviderKey } = require('./provider_resolution');
const {
  getAsaasApiBaseUrlForEnvironment,
  getAsaasApiKeyForEnvironment,
  getAsaasWebhookTokenForEnvironment,
  getStripeClient,
  getStripeSecretForEnvironment,
  getStripeWebhookSecretForEnvironment,
} = require('./runtime_secrets');

const BILLING_PROVIDER_STRIPE = 'stripe';
const BILLING_PROVIDER_ASAAS = 'asaas';

const STRIPE_DEFAULT_WEBHOOK_EVENTS = [
  'checkout.session.completed',
  'customer.subscription.created',
  'customer.subscription.updated',
  'customer.subscription.deleted',
  'invoice.finalized',
  'invoice.paid',
  'invoice.payment_failed',
];

const ASAAS_DEFAULT_WEBHOOK_EVENTS = [
  'CHECKOUT_CREATED',
  'CHECKOUT_PAID',
  'CHECKOUT_CANCELED',
  'CHECKOUT_EXPIRED',
  'SUBSCRIPTION_CREATED',
  'SUBSCRIPTION_UPDATED',
  'SUBSCRIPTION_INACTIVATED',
  'SUBSCRIPTION_DELETED',
  'PAYMENT_CREATED',
  'PAYMENT_UPDATED',
  'PAYMENT_CONFIRMED',
  'PAYMENT_RECEIVED',
  'PAYMENT_OVERDUE',
  'PAYMENT_DELETED',
  'PAYMENT_RESTORED',
  'PAYMENT_CREDIT_CARD_CAPTURE_REFUSED',
  'PAYMENT_REFUNDED',
  'PAYMENT_PARTIALLY_REFUNDED',
  'PAYMENT_REFUND_IN_PROGRESS',
  'PAYMENT_REFUND_DENIED',
  'PAYMENT_RECEIVED_IN_CASH_UNDONE',
  'PAYMENT_CHARGEBACK_REQUESTED',
  'PAYMENT_CHARGEBACK_DISPUTE',
  'PAYMENT_AWAITING_CHARGEBACK_REVERSAL',
  'INVOICE_CREATED',
  'INVOICE_UPDATED',
  'INVOICE_SYNCHRONIZED',
  'INVOICE_AUTHORIZED',
  'INVOICE_PROCESSING_CANCELLATION',
  'INVOICE_CANCELED',
  'INVOICE_CANCELLATION_DENIED',
  'INVOICE_ERROR',
];

async function readStripeIntegrationConfig(firestore) {
  const doc = await firestore.collection('billing_integrations').doc('stripe').get();
  const data = doc.data() || {};
  const envFromDoc = String(data.activeEnvironment ?? '').trim().toLowerCase();
  const envFromProcess = String(process.env.STRIPE_ACTIVE_ENVIRONMENT ?? '')
    .trim()
    .toLowerCase();

  const activeEnvironment = ['test', 'live'].includes(envFromDoc)
    ? envFromDoc
    : ['test', 'live'].includes(envFromProcess)
      ? envFromProcess
      : 'test';

  const webhookEvents = Array.isArray(data.webhookEvents)
    ? data.webhookEvents
      .map((value) => String(value ?? '').trim())
      .filter((value) => value)
    : [];

  return {
    activeEnvironment,
    webhookEvents:
      webhookEvents.length > 0 ? webhookEvents : STRIPE_DEFAULT_WEBHOOK_EVENTS,
  };
}

async function readAsaasIntegrationConfig(firestore) {
  const doc = await firestore.collection('billing_integrations').doc('asaas').get();
  const data = doc.data() || {};

  const environment =
    String(data.activeEnvironment ?? '').trim().toLowerCase() === 'production'
      ? 'production'
      : 'sandbox';

  const webhookEvents = Array.isArray(data.webhookEvents)
    ? data.webhookEvents
      .map((value) => String(value ?? '').trim())
      .filter((value) => value)
    : [];

  return {
    activeEnvironment: environment,
    webhookEvents:
      webhookEvents.length > 0 ? webhookEvents : ASAAS_DEFAULT_WEBHOOK_EVENTS,
  };
}

async function loadStripeIntegrationRuntime({ firestore, requireWebhookSecret }) {
  const config = await readStripeIntegrationConfig(firestore);
  const environment = config.activeEnvironment;
  const secretKey = getStripeSecretForEnvironment(environment);
  if (!secretKey) {
    return {
      ok: false,
      status: 503,
      error: 'integration_not_ready',
      message: `Secret Stripe ausente para ambiente ${environment}. Configure STRIPE_SK_${environment.toUpperCase()}.`,
      environment,
      webhookSecret: '',
      enabledEvents: config.webhookEvents,
      stripeClient: null,
    };
  }

  const webhookSecret = getStripeWebhookSecretForEnvironment(environment);
  if (requireWebhookSecret && !webhookSecret) {
    return {
      ok: false,
      status: 503,
      error: 'integration_not_ready',
      message: `Webhook secret ausente para ambiente ${environment}. Configure STRIPE_WHSEC_${environment.toUpperCase()}.`,
      environment,
      webhookSecret: '',
      enabledEvents: config.webhookEvents,
      stripeClient: null,
    };
  }

  return {
    ok: true,
    status: 200,
    error: '',
    message: '',
    environment,
    webhookSecret,
    enabledEvents: config.webhookEvents,
    stripeClient: getStripeClient(secretKey),
  };
}

async function loadAsaasIntegrationRuntime({ firestore, requireWebhookSecret }) {
  const config = await readAsaasIntegrationConfig(firestore);
  const environment = config.activeEnvironment;
  const apiKey = getAsaasApiKeyForEnvironment(environment);

  if (!apiKey) {
    return {
      ok: false,
      status: 503,
      error: 'integration_not_ready',
      message: `API key Asaas ausente para ambiente ${environment}. Configure ASAAS_API_KEY_${environment === 'production' ? 'PRODUCTION' : 'SANDBOX'}.`,
      environment,
      webhookSecret: '',
      enabledEvents: config.webhookEvents,
      stripeClient: null,
      asaasApiKey: '',
      asaasApiBaseUrl: '',
    };
  }

  const webhookToken = getAsaasWebhookTokenForEnvironment(environment);
  if (requireWebhookSecret && !webhookToken) {
    return {
      ok: false,
      status: 503,
      error: 'integration_not_ready',
      message: `Webhook token Asaas ausente para ambiente ${environment}. Configure ASAAS_WEBHOOK_TOKEN_${environment === 'production' ? 'PRODUCTION' : 'SANDBOX'}.`,
      environment,
      webhookSecret: '',
      enabledEvents: config.webhookEvents,
      stripeClient: null,
      asaasApiKey: '',
      asaasApiBaseUrl: '',
    };
  }

  return {
    ok: true,
    status: 200,
    error: '',
    message: '',
    environment,
    webhookSecret: webhookToken,
    enabledEvents:
      config.webhookEvents.length > 0
        ? config.webhookEvents
        : ASAAS_DEFAULT_WEBHOOK_EVENTS,
    stripeClient: null,
    asaasApiKey: apiKey,
    asaasApiBaseUrl: getAsaasApiBaseUrlForEnvironment(environment),
  };
}

async function loadBillingProviderRuntime({
  firestore,
  providerKey,
  requireWebhookSecret,
}) {
  const normalizedProvider = normalizeBillingProviderKey(providerKey);
  if (normalizedProvider === BILLING_PROVIDER_STRIPE) {
    return loadStripeIntegrationRuntime({
      firestore,
      requireWebhookSecret,
    });
  }

  if (normalizedProvider === BILLING_PROVIDER_ASAAS) {
    return loadAsaasIntegrationRuntime({
      firestore,
      requireWebhookSecret,
    });
  }

  return {
    ok: false,
    status: 400,
    error: 'provider_not_supported',
    message: `Provider de billing nao suportado: ${normalizedProvider}.`,
    environment: '',
    webhookSecret: '',
    enabledEvents: [],
    stripeClient: null,
    asaasApiKey: '',
    asaasApiBaseUrl: '',
  };
}

module.exports = {
  ASAAS_DEFAULT_WEBHOOK_EVENTS,
  STRIPE_DEFAULT_WEBHOOK_EVENTS,
  loadBillingProviderRuntime,
  loadStripeIntegrationRuntime,
  readAsaasIntegrationConfig,
  readStripeIntegrationConfig,
};
