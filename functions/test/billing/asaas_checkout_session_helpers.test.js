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

  const callbackErrorResult = await createAsaasCheckoutSession({
    firestore,
    tenantId: 'tenant_1',
    tenantData: {},
    payload: { billingPlanKey: 'enterprise' },
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

test('createAsaasCheckoutSession creates checkout and stores tenant patch', async () => {
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

  assert.equal(result.ok, true);
  assert.equal(result.body.checkoutSessionId, 'chk_1');
  assert.equal(result.body.billingProvider, 'asaas');

  assert.equal(writes.length, 1);
  assert.equal(writes[0].id, 'tenant_2');
  assert.equal(writes[0].options.merge, true);
  assert.equal(writes[0].patch.billingProvider, 'asaas');
  assert.equal(writes[0].patch.billingPlanKey, 'enterprise');
  assert.equal(writes[0].patch.asaasCheckoutId, 'chk_1');
});
