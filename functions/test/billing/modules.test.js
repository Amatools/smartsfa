const test = require('node:test');
const assert = require('node:assert/strict');

const sharedHelpers = require('../../src/billing/shared_helpers');
const providerResolution = require('../../src/billing/provider_resolution');
const providerDispatch = require('../../src/billing/provider_dispatch');
const checkoutConfig = require('../../src/billing/checkout_config');
const runtimeSecrets = require('../../src/billing/runtime_secrets');
const integrationRuntime = require('../../src/billing/integration_runtime');
const asaasWebhookHelpers = require('../../src/billing/asaas_webhook_helpers');
const asaasCheckoutHelpers = require('../../src/billing/asaas_checkout_helpers');

function createBillingIntegrationsFirestore(docsById) {
  return {
    collection(name) {
      assert.equal(name, 'billing_integrations');
      return {
        doc(id) {
          return {
            async get() {
              const data = docsById[id] || {};
              return {
                data: () => data,
              };
            },
          };
        },
      };
    },
  };
}

async function withEnv(overrides, callback) {
  const keys = Object.keys(overrides);
  const previous = new Map(keys.map((key) => [key, process.env[key]]));
  try {
    for (const [key, value] of Object.entries(overrides)) {
      if (value === undefined || value === null) {
        delete process.env[key];
      } else {
        process.env[key] = String(value);
      }
    }
    return await callback();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

test('shared helpers normalize/parse/format', () => {
  assert.equal(sharedHelpers.normalizeBillingPlanKey(' Enterprise Plus '), 'enterprise_plus');
  assert.equal(sharedHelpers.normalizeBillingSelfServiceAction('suspend'), 'stop_renewal');
  assert.equal(sharedHelpers.normalizeBillingSelfServiceAction('cancel_plan'), 'cancel_now');
  assert.equal(sharedHelpers.normalizeBillingSelfServiceAction('unknown'), '');

  assert.deepEqual(sharedHelpers.parseBillingPlanKeyParts('enterprise_plus'), {
    prefix: 'enterprise',
    slug: 'plus',
  });
  assert.deepEqual(sharedHelpers.parseBillingPlanKeyParts('singletoken'), {
    prefix: 'singletoken',
    slug: 'singletoken',
  });

  assert.equal(sharedHelpers.sanitizeStripeMetadataValue('  abc  ', 10), 'abc');
  assert.equal(sharedHelpers.sanitizeStripeMetadataValue('123456', 4), '1234');

  assert.equal(
    sharedHelpers.resolveStripePlanPrefixByWorkspaceType('brand_owner_workspace'),
    'enterprise',
  );
  assert.equal(
    sharedHelpers.resolveStripePlanPrefixByWorkspaceType('seller_solo_workspace'),
    'individual',
  );

  assert.equal(
    sharedHelpers.formatPlanAmountLabel({
      amountMinorUnits: 2590,
      currency: 'brl',
      recurringInterval: 'month',
      recurringIntervalCount: 1,
    }),
    'R$ 25.90 / month x1',
  );

  assert.equal(sharedHelpers.isValidHttpAbsoluteUrl('https://example.com'), true);
  assert.equal(sharedHelpers.isValidHttpAbsoluteUrl('ftp://example.com'), false);
  assert.equal(sharedHelpers.readNonNegativeInteger('-2', 3), 0);
  assert.equal(sharedHelpers.readNonNegativeInteger('abc', 3), 3);
});

test('provider resolution selection logic', () => {
  assert.equal(providerResolution.normalizeBillingProviderKey(''), 'stripe');
  assert.equal(providerResolution.normalizeBillingProviderKey('AsaaS'), 'asaas');

  const linkedStripe = providerResolution.resolveTenantLinkedBillingProvider({
    stripeSubscriptionId: 'sub_1',
  });
  assert.equal(linkedStripe, 'stripe');

  const resolvedFromHint = providerResolution.resolveTenantBillingProviderKey({
    tenantData: {},
    providerHint: 'asaas',
  });
  assert.equal(resolvedFromHint, 'asaas');

  const selectionWithPayloadProvider =
    providerResolution.resolveCheckoutApiProviderSelection({
      payload: { provider: 'asaas' },
      checkoutApiConfig: {
        activeProviders: ['stripe', 'asaas'],
        preferredProvider: 'stripe',
      },
      tenantData: {},
    });

  assert.deepEqual(selectionWithPayloadProvider, {
    provider: 'asaas',
    hasLinkedContract: false,
    source: 'payload_provider',
  });

  const selectionWithPreferredProvider =
    providerResolution.resolveCheckoutApiProviderSelection({
      payload: {},
      checkoutApiConfig: {
        activeProviders: ['stripe', 'asaas'],
        preferredProvider: 'asaas',
      },
      tenantData: {},
    });

  assert.deepEqual(selectionWithPreferredProvider, {
    provider: 'asaas',
    hasLinkedContract: false,
    source: 'preferred_provider',
  });

  const selectionWithExistingContract =
    providerResolution.resolveCheckoutApiProviderSelection({
      payload: { provider: 'asaas' },
      checkoutApiConfig: {
        activeProviders: ['stripe', 'asaas'],
        preferredProvider: 'asaas',
      },
      tenantData: {
        stripeSubscriptionId: 'sub_existing_1',
      },
    });

  assert.deepEqual(selectionWithExistingContract, {
    provider: 'stripe',
    hasLinkedContract: true,
    source: 'existing_contract',
  });

  const selection = providerResolution.resolveCheckoutApiProviderSelection({
    payload: { provider: 'asaas' },
    checkoutApiConfig: {
      activeProviders: ['stripe', 'asaas'],
      preferredProvider: 'stripe',
    },
    tenantData: { billingContractProvider: 'custom_provider' },
  });

  assert.deepEqual(selection, {
    provider: 'asaas',
    hasLinkedContract: false,
    source: 'payload_provider',
  });
});

test('provider dispatch routes calls to injected handlers', async () => {
  const marker = { ok: true };

  const webhookResult = await providerDispatch.processBillingWebhookEvent({
    firestore: {},
    providerKey: 'stripe',
    event: { type: 'x' },
    enabledEvents: [],
    stripeClient: {},
    asaasRuntime: {},
    processStripeWebhookEvent: async () => marker,
    processAsaasWebhookEvent: async () => ({ ok: false }),
  });
  assert.equal(webhookResult, marker);

  const reconcileResult = await providerDispatch.reconcileTenantBillingState({
    firestore: {},
    providerKey: 'asaas',
    tenantId: 't1',
    stripeClient: {},
    asaasRuntime: {},
    reconcileTenantStripeState: async () => ({ source: 'stripe' }),
    reconcileTenantAsaasState: async () => ({ source: 'asaas' }),
  });
  assert.deepEqual(reconcileResult, { source: 'asaas' });

  const unsupported = await providerDispatch.applyTenantBillingSelfServiceActionToProvider({
    providerKey: 'stripe',
    asaasRuntime: {},
    tenantData: {},
    action: 'cancel_now',
    applyTenantBillingSelfServiceActionToAsaas: async () => ({ applied: true }),
  });
  assert.equal(unsupported.applied, false);
  assert.equal(unsupported.action, 'provider_not_supported');
});

test('checkout config defaults and callback URL validation', async () => {
  const firestore = createBillingIntegrationsFirestore({
    checkout_api: {
      activeProviders: ['asaas'],
      preferredProvider: 'asaas',
    },
  });

  const config = await checkoutConfig.readCheckoutApiConfig(firestore);
  assert.deepEqual(config, {
    activeProviders: ['asaas'],
    preferredProvider: 'asaas',
  });

  const resolved = checkoutConfig.resolveAsaasCallbackUrls({
    payload: {
      successUrl: 'https://portal.example/success',
      cancelUrl: 'https://portal.example/cancel',
    },
    tenantData: {},
    tenantId: 'tenant_1',
  });
  assert.equal(resolved.ok, true);
  assert.equal(resolved.callback.successUrl, 'https://portal.example/success');

  const invalid = checkoutConfig.resolveAsaasCallbackUrls({
    payload: {
      successUrl: 'notaurl',
      cancelUrl: 'https://portal.example/cancel',
    },
    tenantData: {},
    tenantId: 'tenant_1',
  });
  assert.equal(invalid.ok, false);
  assert.equal(invalid.error, 'invalid_callback_url');
});

test('runtime secrets env resolution and stripe cache', async () => {
  await withEnv(
    {
      ASAAS_WEBHOOK_TOKEN_SANDBOX: 'sandbox-token',
      ASAAS_WEBHOOK_TOKEN_PRODUCTION: 'prod-token',
      ASAAS_API_KEY_SANDBOX: 'sandbox-api',
      ASAAS_API_KEY_PRODUCTION: 'prod-api',
      STRIPE_SK_TEST: 'sk_test_123',
      STRIPE_SK_LIVE: 'sk_live_123',
      STRIPE_WHSEC_TEST: 'whsec_test',
      STRIPE_WHSEC_LIVE: 'whsec_live',
    },
    async () => {
      assert.equal(runtimeSecrets.getAsaasWebhookTokenForEnvironment('sandbox'), 'sandbox-token');
      assert.equal(runtimeSecrets.getAsaasWebhookTokenForEnvironment('production'), 'prod-token');
      assert.equal(runtimeSecrets.getAsaasApiKeyForEnvironment('sandbox'), 'sandbox-api');
      assert.equal(runtimeSecrets.getAsaasApiKeyForEnvironment('production'), 'prod-api');
      assert.equal(
        runtimeSecrets.getAsaasApiBaseUrlForEnvironment('production'),
        'https://api.asaas.com/v3',
      );

      assert.equal(runtimeSecrets.getStripeSecretForEnvironment('live'), 'sk_live_123');
      assert.equal(runtimeSecrets.getStripeSecretForEnvironment('test'), 'sk_test_123');
      assert.equal(runtimeSecrets.getStripeWebhookSecretForEnvironment('live'), 'whsec_live');
      assert.equal(runtimeSecrets.getStripeWebhookSecretForEnvironment('test'), 'whsec_test');

      const c1 = runtimeSecrets.getStripeClient('sk_test_123');
      const c2 = runtimeSecrets.getStripeClient('sk_test_123');
      assert.equal(c1, c2);

      const fallbackEventId = runtimeSecrets.createAsaasWebhookFallbackEventId({ id: 1 });
      assert.match(fallbackEventId, /^asaas_\d+_[a-f0-9]{24}$/);
    },
  );

  assert.throws(() => runtimeSecrets.getStripeClient(''), /Missing Stripe secret key/);
});

test('integration runtime config and not-ready responses', async () => {
  const firestore = createBillingIntegrationsFirestore({
    stripe: {
      activeEnvironment: 'live',
      webhookEvents: ['invoice.paid'],
    },
    asaas: {
      activeEnvironment: 'production',
      webhookEvents: ['PAYMENT_RECEIVED'],
    },
  });

  await withEnv(
    {
      STRIPE_SK_LIVE: '',
      STRIPE_WHSEC_LIVE: '',
      STRIPE_ACTIVE_ENVIRONMENT: 'test',
      ASAAS_API_KEY_PRODUCTION: '',
      ASAAS_WEBHOOK_TOKEN_PRODUCTION: '',
    },
    async () => {
      const stripeConfig = await integrationRuntime.readStripeIntegrationConfig(firestore);
      assert.equal(stripeConfig.activeEnvironment, 'live');
      assert.deepEqual(stripeConfig.webhookEvents, ['invoice.paid']);

      const asaasConfig = await integrationRuntime.readAsaasIntegrationConfig(firestore);
      assert.equal(asaasConfig.activeEnvironment, 'production');
      assert.deepEqual(asaasConfig.webhookEvents, ['PAYMENT_RECEIVED']);

      const stripeRuntime = await integrationRuntime.loadStripeIntegrationRuntime({
        firestore,
        requireWebhookSecret: true,
      });
      assert.equal(stripeRuntime.ok, false);
      assert.equal(stripeRuntime.error, 'integration_not_ready');

      const unsupported = await integrationRuntime.loadBillingProviderRuntime({
        firestore,
        providerKey: 'custom_gateway',
        requireWebhookSecret: false,
      });
      assert.equal(unsupported.ok, false);
      assert.equal(unsupported.status, 400);
    },
  );
});

test('asaas helpers normalize values and parse references', () => {
  assert.equal(
    asaasWebhookHelpers.mapAsaasSubscriptionStatusToBillingStatus('ACTIVE'),
    'active',
  );
  assert.equal(asaasWebhookHelpers.mapBillingStatusToAccountState('grace'), 'grace');
  assert.equal(asaasWebhookHelpers.mapAsaasCycleToBillingCycle('MONTHLY'), 'month');
  assert.equal(
    asaasWebhookHelpers.normalizeAsaasDateToIso('2026-01-10').startsWith('2026-01-10'),
    true,
  );

  const refFromJson = asaasWebhookHelpers.extractAsaasReferenceInfo(
    '{"tenantId":"t1","billingPlanKey":"Enterprise Plus"}',
  );
  assert.deepEqual(refFromJson, {
    tenantId: 't1',
    billingPlanKey: 'enterprise_plus',
  });

  const refFromQuery = asaasWebhookHelpers.extractAsaasReferenceInfo(
    'tenantId=t2&billingPlanKey=Solo',
  );
  assert.deepEqual(refFromQuery, {
    tenantId: 't2',
    billingPlanKey: 'solo',
  });

  assert.equal(asaasCheckoutHelpers.mapStripeIntervalToAsaasCycle('month', 3), 'QUARTERLY');
  assert.deepEqual(asaasCheckoutHelpers.normalizeAsaasBillingTypes(['pix', 'CREDIT_CARD', 'pix']), [
    'PIX',
    'CREDIT_CARD',
  ]);
  assert.equal(asaasCheckoutHelpers.normalizeAsaasChargeType('detached'), 'DETACHED');
  assert.equal(asaasCheckoutHelpers.normalizeAsaasMinutesToExpire(2), 10);
  assert.match(
    asaasCheckoutHelpers.buildAsaasCheckoutExternalReference({
      tenantId: 'tenant_1',
      billingPlanKey: 'enterprise',
    }),
    /^smartsfa:tenant_1:enterprise:/,
  );
});
