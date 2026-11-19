const test = require('node:test');
const assert = require('node:assert/strict');

const {
  reconcileTenantAsaasState,
} = require('../../src/billing/asaas_reconcile_helpers');

function createTenantFirestore(tenantById) {
  const tenantWrites = [];
  const providerRefWrites = [];
  const firestore = {
    collection(name) {
      if (name === 'tenants') {
        return {
          doc(id) {
            return {
              async get() {
                const data = tenantById[id];
                return {
                  exists: data !== undefined,
                  data: () => (data ? { ...data } : undefined),
                };
              },
              async set(patch, options) {
                tenantWrites.push({ id, patch, options });
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
  };
  return { firestore, tenantWrites, providerRefWrites };
}

test('reconcileTenantAsaasState validates tenant id and runtime', async () => {
  const { firestore } = createTenantFirestore({});

  await assert.rejects(
    () =>
      reconcileTenantAsaasState({
        firestore,
        asaasRuntime: { apiKey: 'k', apiBaseUrl: 'https://sandbox.asaas.com' },
        tenantId: '',
        fetchAsaasApiJson: async () => ({}),
        buildTenantPatchFromAsaasEvent: () => ({}),
      }),
    /tenantId invalido/,
  );

  await assert.rejects(
    () =>
      reconcileTenantAsaasState({
        firestore,
        asaasRuntime: {},
        tenantId: 'tenant_1',
        fetchAsaasApiJson: async () => ({}),
        buildTenantPatchFromAsaasEvent: () => ({}),
      }),
    /Runtime Asaas indisponivel/,
  );
});

test('reconcileTenantAsaasState reconciles from subscription id when available', async () => {
  const { firestore, tenantWrites, providerRefWrites } = createTenantFirestore({
    tenant_1: {
      billingStatus: 'past_due',
      asaasSubscriptionId: 'sub_1',
      asaasCustomerId: 'cus_1',
    },
  });

  const fetchCalls = [];
  const result = await reconcileTenantAsaasState({
    firestore,
    asaasRuntime: {
      apiKey: 'api_key_1',
      apiBaseUrl: 'https://sandbox.asaas.com',
      environment: 'sandbox',
    },
    tenantId: 'tenant_1',
    fetchAsaasApiJson: async (request) => {
      fetchCalls.push(request);
      return { id: 'sub_1', status: 'ACTIVE' };
    },
    buildTenantPatchFromAsaasEvent: ({ eventType, webhookEnvironment }) => {
      assert.equal(eventType, 'SUBSCRIPTION_UPDATED');
      assert.equal(webhookEnvironment, 'sandbox');
      return {
        asaasSubscriptionId: 'sub_1',
        asaasCustomerId: 'cus_1',
        billingStatus: 'active',
        billingUpdatedAt: '2026-01-01T00:00:00.000Z',
      };
    },
  });

  assert.equal(fetchCalls.length, 1);
  assert.equal(fetchCalls[0].path, '/subscriptions/sub_1');
  assert.equal(tenantWrites.length, 1);
  assert.deepEqual(tenantWrites[0].options, { merge: true });
  assert.equal(providerRefWrites.length, 1);
  assert.equal(providerRefWrites[0].id, 'tenant_1');
  assert.deepEqual(providerRefWrites[0].options, { merge: true });
  assert.equal(providerRefWrites[0].patch.billingProvider, 'asaas');
  assert.equal(providerRefWrites[0].patch.asaasSubscriptionId, 'sub_1');
  assert.equal(providerRefWrites[0].patch.asaasCustomerId, 'cus_1');
  assert.equal(providerRefWrites[0].patch.lastReconciledSource, 'asaas_reconcile');
  assert.equal(result.previousBillingStatus, 'past_due');
  assert.equal(result.currentBillingStatus, 'active');
});

test('reconcileTenantAsaasState falls back to customer last payment and throws without references', async () => {
  const {
    firestore: customerFirestore,
    tenantWrites,
    providerRefWrites,
  } = createTenantFirestore({
    tenant_customer: {
      billingStatus: 'trial',
      asaasCustomerId: 'cus_2',
    },
  });

  const fetchCalls = [];
  const result = await reconcileTenantAsaasState({
    firestore: customerFirestore,
    asaasRuntime: {
      apiKey: 'api_key_2',
      apiBaseUrl: 'https://sandbox.asaas.com',
      environment: 'sandbox',
    },
    tenantId: 'tenant_customer',
    fetchAsaasApiJson: async (request) => {
      fetchCalls.push(request);
      return {
        data: [{ id: 'pay_1', customer: 'cus_2' }],
      };
    },
    buildTenantPatchFromAsaasEvent: () => ({
      asaasCustomerId: 'cus_2',
      billingStatus: 'past_due',
      billingUpdatedAt: '2026-01-02T00:00:00.000Z',
    }),
  });

  assert.equal(fetchCalls.length, 1);
  assert.equal(fetchCalls[0].path, '/payments');
  assert.equal(fetchCalls[0].query.customer, 'cus_2');
  assert.equal(result.currentBillingStatus, 'past_due');
  assert.equal(tenantWrites.length, 1);
  assert.equal(providerRefWrites.length, 1);
  assert.equal(providerRefWrites[0].id, 'tenant_customer');
  assert.equal(providerRefWrites[0].patch.billingProvider, 'asaas');
  assert.equal(providerRefWrites[0].patch.asaasCustomerId, 'cus_2');
  assert.equal(providerRefWrites[0].patch.lastReconciledSource, 'asaas_reconcile');

  const { firestore: missingRefFirestore } = createTenantFirestore({
    tenant_missing: {
      billingStatus: 'no_plan',
    },
  });

  await assert.rejects(
    () =>
      reconcileTenantAsaasState({
        firestore: missingRefFirestore,
        asaasRuntime: {
          apiKey: 'api_key_3',
          apiBaseUrl: 'https://sandbox.asaas.com',
        },
        tenantId: 'tenant_missing',
        fetchAsaasApiJson: async () => ({}),
        buildTenantPatchFromAsaasEvent: () => ({}),
      }),
    /Tenant sem referencia suficiente no Asaas/,
  );
});
