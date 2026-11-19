const test = require('node:test');
const assert = require('node:assert/strict');

const {
  applyAsaasWebhookEventToTenant,
} = require('../../src/billing/asaas_webhook_application_helpers');

function createTenantsFirestore(tenantsById) {
  const docs = new Map(Object.entries(tenantsById));
  const writes = [];
  const providerRefWrites = [];

  const firestore = {
    writes,
    providerRefWrites,
    collection(name) {
      if (name === 'tenants') {
        return {
          doc(id) {
            return {
              id,
              async get() {
                const data = docs.get(id);
                return {
                  exists: data !== undefined,
                  data: () => (data ? { ...data } : undefined),
                };
              },
              async set(patch, options) {
                writes.push({ id, patch: { ...patch }, options: { ...options } });
                const current = docs.get(id) || {};
                docs.set(id, { ...current, ...patch });
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
                providerRefWrites.push({
                  id,
                  patch: { ...patch },
                  options: { ...options },
                });
              },
            };
          },
        };
      }

      throw new Error(`Unexpected collection ${name}`);
    },
  };

  return firestore;
}

test('applyAsaasWebhookEventToTenant returns empty when resolver finds no tenant', async () => {
  const firestore = createTenantsFirestore({});

  const result = await applyAsaasWebhookEventToTenant({
    firestore,
    eventPayload: { id: 'evt_1' },
    eventType: 'PAYMENT_RECEIVED',
    asaasRuntime: { environment: 'sandbox' },
    resolveTenantIdFromAsaasReferences: async () => '',
    buildTenantPatchFromAsaasEvent: () => {
      throw new Error('should_not_build_patch');
    },
  });

  assert.deepEqual(result, {
    tenantId: '',
    billingStatus: '',
  });
  assert.equal(firestore.writes.length, 0);
  assert.equal(firestore.providerRefWrites.length, 0);
});

test('applyAsaasWebhookEventToTenant applies patch and returns billing status', async () => {
  const firestore = createTenantsFirestore({
    tenant_1: {
      billingStatus: 'active',
    },
  });

  let enforceCalls = 0;
  const result = await applyAsaasWebhookEventToTenant({
    firestore,
    eventPayload: { id: 'evt_2' },
    eventType: 'PAYMENT_OVERDUE',
    asaasRuntime: { environment: 'production' },
    resolveTenantIdFromAsaasReferences: async () => 'tenant_1',
    buildTenantPatchFromAsaasEvent: ({ webhookEnvironment, currentTenantData }) => {
      assert.equal(webhookEnvironment, 'production');
      assert.equal(currentTenantData.billingStatus, 'active');
      return {
        billingStatus: 'past_due',
        billingUpdatedAt: '2026-01-10T00:00:00.000Z',
      };
    },
    enforceTenantSeatAllowanceForTenant: async ({ tenantId }) => {
      assert.equal(tenantId, 'tenant_1');
      enforceCalls += 1;
    },
  });

  assert.deepEqual(result, {
    tenantId: 'tenant_1',
    billingStatus: 'past_due',
  });
  assert.equal(enforceCalls, 1);
  assert.equal(firestore.writes.length, 1);
  assert.equal(firestore.writes[0].id, 'tenant_1');
  assert.equal(firestore.writes[0].options.merge, true);
  assert.equal(firestore.writes[0].patch.billingStatus, 'past_due');
  assert.equal(firestore.providerRefWrites.length, 1);
  assert.equal(firestore.providerRefWrites[0].id, 'tenant_1');
  assert.equal(firestore.providerRefWrites[0].options.merge, true);
  assert.equal(firestore.providerRefWrites[0].patch.billingProvider, 'asaas');
  assert.equal(firestore.providerRefWrites[0].patch.lastWebhookEventId, 'evt_2');
  assert.equal(
    firestore.providerRefWrites[0].patch.lastWebhookEventType,
    'PAYMENT_OVERDUE',
  );
});

test('applyAsaasWebhookEventToTenant tolerates seat enforcement failures', async () => {
  const firestore = createTenantsFirestore({
    tenant_2: {
      billingStatus: 'active',
    },
  });

  const result = await applyAsaasWebhookEventToTenant({
    firestore,
    eventPayload: { id: 'evt_3' },
    eventType: 'PAYMENT_RECEIVED',
    asaasRuntime: { environment: 'sandbox' },
    resolveTenantIdFromAsaasReferences: async () => 'tenant_2',
    buildTenantPatchFromAsaasEvent: () => ({
      billingStatus: 'active',
      billingUpdatedAt: '2026-01-10T00:00:00.000Z',
    }),
    enforceTenantSeatAllowanceForTenant: async () => {
      throw new Error('seat_enforcement_failed');
    },
  });

  assert.deepEqual(result, {
    tenantId: 'tenant_2',
    billingStatus: 'active',
  });
  assert.equal(firestore.writes.length, 1);
  assert.equal(firestore.providerRefWrites.length, 1);
});
