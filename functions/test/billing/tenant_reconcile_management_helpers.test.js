const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeReconcileStripeTenantAction,
  executeReconcileAsaasTenantAction,
} = require('../../src/billing/tenant_reconcile_management_helpers');

function createFirestore() {
  const auditWrites = [];

  return {
    firestore: {
      collection(name) {
        if (name === 'platform_admin_audit') {
          return {
            async add(payload) {
              auditWrites.push(payload);
            },
          };
        }

        throw new Error(`Unexpected collection ${name}`);
      },
    },
    auditWrites,
  };
}

test('executeReconcileStripeTenantAction returns platform access errors', async () => {
  const { firestore, auditWrites } = createFirestore();

  const result = await executeReconcileStripeTenantAction({
    firestore,
    tenantId: 'tenant_1',
    reason: 'manual check',
    authContext: { uid: 'uid_1', email: 'u1@example.com' },
    assertPlatformAdminActor: async () => ({
      allowed: false,
      status: 403,
      error: 'forbidden',
      message: 'not allowed',
    }),
    loadStripeIntegrationRuntime: async () => ({ ok: true }),
    reconcileTenantBillingState: async () => ({}),
    timestampFromDate: (d) => d.toISOString(),
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'forbidden');
  assert.equal(auditWrites.length, 0);
});

test('executeReconcileStripeTenantAction returns success and writes platform audit', async () => {
  const { firestore, auditWrites } = createFirestore();
  const reconcileCalls = [];

  const result = await executeReconcileStripeTenantAction({
    firestore,
    tenantId: 'tenant_2',
    reason: 'manual reconcile',
    authContext: { uid: 'uid_2', email: 'u2@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      stripeClient: { id: 'stripe_client' },
    }),
    reconcileTenantBillingState: async (input) => {
      reconcileCalls.push(input);
      return {
        stripeSubscriptionId: 'sub_2',
        previousBillingStatus: 'past_due',
        currentBillingStatus: 'active',
        updatedAt: '2026-11-18T00:00:00.000Z',
      };
    },
    timestampFromDate: (d) => `ts:${d.toISOString()}`,
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.tenantId, 'tenant_2');
  assert.equal(result.body.stripeSubscriptionId, 'sub_2');
  assert.equal(result.body.previousBillingStatus, 'past_due');
  assert.equal(result.body.currentBillingStatus, 'active');
  assert.equal(reconcileCalls.length, 1);
  assert.equal(reconcileCalls[0].providerKey, 'stripe');
  assert.equal(reconcileCalls[0].tenantId, 'tenant_2');

  assert.equal(auditWrites.length, 1);
  assert.equal(auditWrites[0].action, 'billing_state_updated');
  assert.equal(auditWrites[0].details.source, 'billing_reconcile_tenant');
  assert.equal(auditWrites[0].details.billingProvider, 'stripe');
  assert.match(String(auditWrites[0].createdAt), /^ts:/);
});

test('executeReconcileAsaasTenant returns integration errors', async () => {
  const { firestore, auditWrites } = createFirestore();

  const result = await executeReconcileAsaasTenantAction({
    firestore,
    tenantId: 'tenant_3',
    reason: 'manual',
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadBillingProviderRuntime: async () => ({
      ok: false,
      status: 503,
      error: 'integration_not_ready',
      message: 'runtime unavailable',
    }),
    reconcileTenantBillingState: async () => ({}),
    timestampFromDate: (d) => d.toISOString(),
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 503);
  assert.equal(result.body.error, 'integration_not_ready');
  assert.equal(auditWrites.length, 0);
});

test('executeReconcileAsaasTenant returns success and writes asaas audit', async () => {
  const { firestore, auditWrites } = createFirestore();
  const reconcileCalls = [];

  const result = await executeReconcileAsaasTenantAction({
    firestore,
    tenantId: 'tenant_4',
    reason: 'manual reconcile asaas',
    authContext: { uid: 'uid_4', email: 'u4@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadBillingProviderRuntime: async () => ({
      ok: true,
      environment: 'production',
      asaasApiKey: 'key',
      asaasApiBaseUrl: 'https://api.asaas.com',
    }),
    reconcileTenantBillingState: async (input) => {
      reconcileCalls.push(input);
      return {
        asaasSubscriptionId: 'asaas_sub_4',
        asaasCustomerId: 'asaas_cus_4',
        previousBillingStatus: 'pending',
        currentBillingStatus: 'active',
        updatedAt: '2026-11-18T00:00:00.000Z',
      };
    },
    timestampFromDate: (d) => `ts:${d.toISOString()}`,
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.tenantId, 'tenant_4');
  assert.equal(result.body.asaasSubscriptionId, 'asaas_sub_4');
  assert.equal(result.body.asaasCustomerId, 'asaas_cus_4');
  assert.equal(result.body.previousBillingStatus, 'pending');
  assert.equal(result.body.currentBillingStatus, 'active');
  assert.equal(reconcileCalls.length, 1);
  assert.equal(reconcileCalls[0].providerKey, 'asaas');
  assert.equal(reconcileCalls[0].tenantId, 'tenant_4');
  assert.equal(reconcileCalls[0].asaasRuntime.environment, 'production');

  assert.equal(auditWrites.length, 1);
  assert.equal(auditWrites[0].details.source, 'billing_reconcile_tenant_asaas');
  assert.equal(auditWrites[0].details.billingProvider, 'asaas');
  assert.match(String(auditWrites[0].createdAt), /^ts:/);
});
