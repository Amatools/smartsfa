const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeReconcileStripeTenantAction,
  executeReconcileAsaasTenantAction,
  executeReconcileAllStripeTenantsAction,
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

function createFirestoreWithTenants(tenants) {
  return {
    collection(name) {
      if (name !== 'tenants') {
        throw new Error(`Unexpected collection ${name}`);
      }

      return {
        limit(value) {
          return {
            async get() {
              return {
                docs: tenants.slice(0, value).map((tenant) => ({
                  id: tenant.id,
                  data() {
                    return tenant.data;
                  },
                })),
              };
            },
          };
        },
      };
    },
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

test('executeReconcileAllStripeTenantsAction returns platform access errors', async () => {
  const firestore = createFirestoreWithTenants([]);

  const result = await executeReconcileAllStripeTenantsAction({
    firestore,
    dryRun: false,
    limit: 50,
    authContext: { uid: 'uid_5', email: 'u5@example.com' },
    assertPlatformAdminActor: async () => ({
      allowed: false,
      status: 403,
      error: 'forbidden',
      message: 'not allowed',
    }),
    loadStripeIntegrationRuntime: async () => ({ ok: true }),
    reconcileTenantBillingState: async () => ({}),
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'forbidden');
});

test('executeReconcileAllStripeTenantsAction returns integration errors', async () => {
  const firestore = createFirestoreWithTenants([]);

  const result = await executeReconcileAllStripeTenantsAction({
    firestore,
    dryRun: false,
    limit: 50,
    authContext: { uid: 'uid_6', email: 'u6@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadStripeIntegrationRuntime: async () => ({
      ok: false,
      status: 503,
      error: 'integration_not_ready',
      message: 'runtime unavailable',
    }),
    reconcileTenantBillingState: async () => ({}),
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 503);
  assert.equal(result.body.error, 'integration_not_ready');
});

test('executeReconcileAllStripeTenantsAction dryRun counts candidates without reconcile calls', async () => {
  const firestore = createFirestoreWithTenants([
    { id: 'tenant_a', data: { stripeCustomerId: 'cus_a' } },
    { id: 'tenant_b', data: { stripeSubscriptionId: 'sub_b' } },
    { id: 'tenant_c', data: {} },
  ]);
  let reconcileCalls = 0;

  const result = await executeReconcileAllStripeTenantsAction({
    firestore,
    dryRun: true,
    limit: 50,
    authContext: { uid: 'uid_7', email: 'u7@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      stripeClient: { id: 'stripe_client' },
    }),
    reconcileTenantBillingState: async () => {
      reconcileCalls += 1;
    },
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.totalProcessed, 2);
  assert.equal(result.body.totalUpdated, 2);
  assert.equal(result.body.totalFailed, 0);
  assert.equal(result.body.dryRun, true);
  assert.equal(reconcileCalls, 0);
});

test('executeReconcileAllStripeTenantsAction tracks failures per tenant', async () => {
  const firestore = createFirestoreWithTenants([
    { id: 'tenant_ok', data: { stripeCustomerId: 'cus_ok' } },
    { id: 'tenant_fail', data: { stripeSubscriptionId: 'sub_fail' } },
  ]);

  const result = await executeReconcileAllStripeTenantsAction({
    firestore,
    dryRun: false,
    limit: 50,
    authContext: { uid: 'uid_8', email: 'u8@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      stripeClient: { id: 'stripe_client' },
    }),
    reconcileTenantBillingState: async ({ tenantId }) => {
      if (tenantId === 'tenant_fail') {
        throw new Error('reconcile_failed');
      }
    },
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.totalProcessed, 2);
  assert.equal(result.body.totalUpdated, 1);
  assert.equal(result.body.totalFailed, 1);
  assert.equal(result.body.failures.length, 1);
  assert.equal(result.body.failures[0].tenantId, 'tenant_fail');
  assert.equal(result.body.failures[0].message, 'reconcile_failed');
});
