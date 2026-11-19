const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createAsaasCheckoutSession,
} = require('../../src/billing/asaas_checkout_session_helpers');

function createTenantFirestore() {
  const writes = [];
  return {
    writes,
    firestore: {
      collection(name) {
        assert.equal(name, 'tenants');
        return {
          doc(id) {
            return {
              async set(patch, options) {
                writes.push({ id, patch, options });
              },
            };
          },
        };
      },
    },
  };
}

function createCheckoutFirestoreWithQuotes() {
  const tenantWrites = [];
  const quoteWrites = [];
  const providerRefWrites = [];
  const now = Date.now();

  return {
    tenantWrites,
    quoteWrites,
    providerRefWrites,
    firestore: {
      collection(name) {
        if (name === 'tenants') {
          return {
            doc(id) {
              return {
                async set(patch, options) {
                  tenantWrites.push({ id, patch, options });
                },
              };
            },
          };
        }

        if (name === 'billing_quotes') {
          return {
            doc(id) {
              return {
                async get() {
                  if (id === 'quote_open') {
                    return {
                      exists: true,
                      data: () => ({
                        tenantId: 'tenant_3',
                        billingProvider: 'asaas',
                        billingPlanKey: 'enterprise',
                        status: 'open',
                        totalAmountCents: 4590,
                        expiresAt: new Date(now + 15 * 60 * 1000).toISOString(),
                      }),
                    };
                  }

                  if (id === 'quote_expired') {
                    return {
                      exists: true,
                      data: () => ({
                        tenantId: 'tenant_3',
                        billingProvider: 'asaas',
                        billingPlanKey: 'enterprise',
                        status: 'open',
                        totalAmountCents: 4590,
                        expiresAt: new Date(now - 15 * 60 * 1000).toISOString(),
                      }),
                    };
                  }

                  return {
                    exists: false,
                    data: () => undefined,
                  };
                },
                async set(patch, options) {
                  quoteWrites.push({ id, patch, options });
                },
              };
            },
          };
        }

        if (name === 'billing_provider_refs') {
          return {
            doc(id) {
              return {
                async set(patch, options) {
                  providerRefWrites.push({ id, patch, options });
                },
              };
            },
          };
        }

        throw new Error(`Unexpected collection ${name}`);
      },
    },
  };
}

test('createAsaasCheckoutSession validates missing billing plan key and callback errors', async () => {
  const { firestore } = createTenantFirestore();

  const missingPlanResult = await createAsaasCheckoutSession({
    firestore,
    tenantId: 'tenant_1',
    tenantData: {},
    payload: {},
    providerSelection: { source: 'x', hasLinkedContract: false },
    billingProviderAsaas: 'asaas',
    normalizeBillingPlanKey: () => '',
    resolveAsaasCallbackUrls: () => ({ ok: true, callback: {} }),
    loadAsaasIntegrationRuntime: async () => ({ ok: true }),
    resolveAsaasPlanMapping: async () => ({ ok: true, mapping: { billingPlanKey: 'x' } }),
    buildAsaasCheckoutPayload: () => ({}),
    fetchAsaasApiJson: async () => ({}),
  });

  assert.equal(missingPlanResult.ok, false);
  assert.equal(missingPlanResult.error, 'invalid_payload');

  const missingQuoteResult = await createAsaasCheckoutSession({
    firestore,
    tenantId: 'tenant_1',
    tenantData: {},
    payload: { billingPlanKey: 'enterprise' },
    providerSelection: { source: 'x', hasLinkedContract: false },
    billingProviderAsaas: 'asaas',
    normalizeBillingPlanKey: (v) => String(v ?? '').trim().toLowerCase(),
    resolveAsaasCallbackUrls: () => ({ ok: true, callback: {} }),
    loadAsaasIntegrationRuntime: async () => ({ ok: true }),
    resolveAsaasPlanMapping: async () => ({ ok: true, mapping: { billingPlanKey: 'x' } }),
    buildAsaasCheckoutPayload: () => ({}),
    fetchAsaasApiJson: async () => ({}),
  });

  assert.equal(missingQuoteResult.ok, false);
  assert.equal(missingQuoteResult.error, 'invalid_payload');

  const callbackErrorResult = await createAsaasCheckoutSession({
    firestore,
    tenantId: 'tenant_1',
    tenantData: {},
    payload: {
      billingPlanKey: 'enterprise',
      quoteId: 'quote_any_value',
    },
    providerSelection: { source: 'x', hasLinkedContract: false },
    billingProviderAsaas: 'asaas',
    normalizeBillingPlanKey: (v) => String(v ?? '').trim().toLowerCase(),
    resolveAsaasCallbackUrls: () => ({
      ok: false,
      error: 'invalid_callback_urls',
      message: 'URL invalida',
    }),
    loadAsaasIntegrationRuntime: async () => ({ ok: true }),
    resolveAsaasPlanMapping: async () => ({ ok: true, mapping: { billingPlanKey: 'x' } }),
    buildAsaasCheckoutPayload: () => ({}),
    fetchAsaasApiJson: async () => ({}),
  });

  assert.equal(callbackErrorResult.ok, false);
  assert.equal(callbackErrorResult.error, 'invalid_callback_urls');
});

test('createAsaasCheckoutSession requires quoteId for Asaas checkout', async () => {
  const { firestore, writes } = createTenantFirestore();

  const result = await createAsaasCheckoutSession({
    firestore,
    tenantId: 'tenant_2',
    tenantData: {},
    payload: {
      billingPlanKey: 'Enterprise',
    },
    providerSelection: {
      source: 'payload_provider',
      hasLinkedContract: false,
    },
    billingProviderAsaas: 'asaas',
    normalizeBillingPlanKey: (v) => String(v ?? '').trim().toLowerCase(),
    resolveAsaasCallbackUrls: () => ({
      ok: true,
      callback: {
        successUrl: 'https://portal.example/success',
      },
    }),
    loadAsaasIntegrationRuntime: async () => ({
      ok: true,
      environment: 'sandbox',
      asaasApiBaseUrl: 'https://sandbox.asaas.com',
      asaasApiKey: 'api_key_1',
    }),
    resolveAsaasPlanMapping: async () => ({
      ok: true,
      mapping: {
        billingPlanKey: 'enterprise',
      },
    }),
    buildAsaasCheckoutPayload: () => ({
      externalReference: 'smartsfa:tenant_2:enterprise:123',
    }),
    fetchAsaasApiJson: async () => ({
      id: 'chk_1',
      link: 'https://asaas.com/checkout/chk_1',
      status: 'PENDING',
      externalReference: 'smartsfa:tenant_2:enterprise:123',
    }),
  });

  assert.equal(result.ok, false);
  assert.equal(result.status, 400);
  assert.equal(result.error, 'invalid_payload');
  assert.equal(writes.length, 0);
});

test('createAsaasCheckoutSession rejects expired quote for quote-based checkout', async () => {
  const { firestore } = createCheckoutFirestoreWithQuotes();

  const result = await createAsaasCheckoutSession({
    firestore,
    tenantId: 'tenant_3',
    tenantData: {},
    payload: {
      billingPlanKey: 'Enterprise',
      quoteId: 'quote_expired',
    },
    providerSelection: {
      source: 'payload_provider',
      hasLinkedContract: false,
    },
    billingProviderAsaas: 'asaas',
    normalizeBillingPlanKey: (v) => String(v ?? '').trim().toLowerCase(),
    resolveAsaasCallbackUrls: () => ({
      ok: true,
      callback: {
        successUrl: 'https://portal.example/success',
      },
    }),
    loadAsaasIntegrationRuntime: async () => ({
      ok: true,
      environment: 'sandbox',
      asaasApiBaseUrl: 'https://sandbox.asaas.com',
      asaasApiKey: 'api_key_1',
    }),
    resolveAsaasPlanMapping: async () => ({
      ok: true,
      mapping: {
        billingPlanKey: 'enterprise',
      },
    }),
    buildAsaasCheckoutPayload: () => ({
      externalReference: 'smartsfa:tenant_3:enterprise:123',
    }),
    fetchAsaasApiJson: async () => ({
      id: 'chk_expired',
      link: 'https://asaas.com/checkout/chk_expired',
      status: 'PENDING',
    }),
  });

  assert.equal(result.ok, false);
  assert.equal(result.status, 409);
  assert.equal(result.error, 'quote_expired');
});

test('createAsaasCheckoutSession consumes open quote and uses quote amount', async () => {
  const { firestore, tenantWrites, quoteWrites, providerRefWrites } = createCheckoutFirestoreWithQuotes();
  const capture = {
    amount: null,
  };

  const result = await createAsaasCheckoutSession({
    firestore,
    tenantId: 'tenant_3',
    tenantData: {},
    payload: {
      billingPlanKey: 'Enterprise',
      quoteId: 'quote_open',
    },
    providerSelection: {
      source: 'payload_provider',
      hasLinkedContract: false,
    },
    billingProviderAsaas: 'asaas',
    normalizeBillingPlanKey: (v) => String(v ?? '').trim().toLowerCase(),
    resolveAsaasCallbackUrls: () => ({
      ok: true,
      callback: {
        successUrl: 'https://portal.example/success',
      },
    }),
    loadAsaasIntegrationRuntime: async () => ({
      ok: true,
      environment: 'sandbox',
      asaasApiBaseUrl: 'https://sandbox.asaas.com',
      asaasApiKey: 'api_key_1',
    }),
    resolveAsaasPlanMapping: async () => ({
      ok: true,
      mapping: {
        billingPlanKey: 'enterprise',
        amount: 35.9,
      },
    }),
    buildAsaasCheckoutPayload: ({ resolvedPlan }) => {
      capture.amount = resolvedPlan?.mapping?.amount ?? null;
      return {
        externalReference: 'smartsfa:tenant_3:enterprise:124',
      };
    },
    fetchAsaasApiJson: async () => ({
      id: 'chk_quote_1',
      link: 'https://asaas.com/checkout/chk_quote_1',
      status: 'PENDING',
      subscription: 'sub_quote_1',
    }),
  });

  assert.equal(result.ok, true);
  assert.equal(result.status, 200);
  assert.equal(capture.amount, 45.9);
  assert.equal(result.body.quoteId, 'quote_open');

  assert.equal(tenantWrites.length, 1);
  assert.equal(tenantWrites[0].patch.billingQuoteId, 'quote_open');

  assert.equal(quoteWrites.length, 1);
  assert.equal(quoteWrites[0].id, 'quote_open');
  assert.equal(quoteWrites[0].options.merge, true);
  assert.equal(quoteWrites[0].patch.status, 'used');
  assert.equal(quoteWrites[0].patch.usedByCheckoutId, 'chk_quote_1');

  assert.equal(providerRefWrites.length, 1);
  assert.equal(providerRefWrites[0].id, 'tenant_3');
  assert.equal(providerRefWrites[0].options.merge, true);
  assert.equal(providerRefWrites[0].patch.tenantId, 'tenant_3');
  assert.equal(providerRefWrites[0].patch.billingProvider, 'asaas');
  assert.equal(providerRefWrites[0].patch.asaasCheckoutId, 'chk_quote_1');
  assert.equal(providerRefWrites[0].patch.asaasSubscriptionId, 'sub_quote_1');
  assert.equal(providerRefWrites[0].patch.asaasLastCheckoutQuoteId, 'quote_open');
});
