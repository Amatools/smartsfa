const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeManageTenantBillingStateAction,
} = require('../../src/billing/tenant_billing_state_management_helpers');

function createFirestore({ tenantExists = true, tenantData = {} } = {}) {
  const tenantWrites = [];
  const auditWrites = [];

  return {
    firestore: {
      collection(name) {
        if (name === 'tenants') {
          return {
            doc(id) {
              return {
                async get() {
                  return {
                    exists: tenantExists,
                    data: () => (tenantExists ? { ...tenantData } : undefined),
                  };
                },
                async set(patch, options) {
                  tenantWrites.push({ id, patch, options });
                },
              };
            },
          };
        }

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
    tenantWrites,
    auditWrites,
  };
}

test('executeManageTenantBillingStateAction returns platform access errors', async () => {
  const { firestore, tenantWrites, auditWrites } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeManageTenantBillingStateAction({
    firestore,
    tenantId: 'tenant_1',
    action: 'grant_7_days',
    reason: '',
    providerHint: '',
    authContext: { uid: 'uid_1', email: 'u1@example.com' },
    assertPlatformAdminActor: async () => ({
      allowed: false,
      status: 403,
      error: 'forbidden',
      message: 'no access',
    }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'], preferredProvider: 'stripe' }),
    resolveTenantBillingProviderKey: () => 'stripe',
    loadBillingProviderRuntime: async () => ({ ok: true }),
    applyTenantBillingActionToProvider: async () => ({ applied: true }),
    enforceTenantSeatAllowanceForTenant: async () => ({}),
    timestampFromDate: (d) => d.toISOString(),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'forbidden');
  assert.equal(tenantWrites.length, 0);
  assert.equal(auditWrites.length, 0);
});

test('executeManageTenantBillingStateAction returns 502 when provider reflection fails', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {
      billingStatus: 'active',
    },
  });

  const result = await executeManageTenantBillingStateAction({
    firestore,
    tenantId: 'tenant_2',
    action: 'normalize_billing',
    reason: 'manual',
    providerHint: 'stripe',
    authContext: { uid: 'uid_2', email: 'u2@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'], preferredProvider: 'stripe' }),
    resolveTenantBillingProviderKey: () => 'stripe',
    loadBillingProviderRuntime: async () => ({
      ok: true,
      stripeClient: {},
      environment: 'sandbox',
      asaasApiKey: '',
      asaasApiBaseUrl: '',
    }),
    applyTenantBillingActionToProvider: async () => {
      throw new Error('provider down');
    },
    enforceTenantSeatAllowanceForTenant: async () => ({}),
    timestampFromDate: (d) => d.toISOString(),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 502);
  assert.equal(result.body.error, 'provider_action_failed');
  assert.match(result.body.message, /provider down/);
});

test('executeManageTenantBillingStateAction updates tenant and writes audit on grant action', async () => {
  const { firestore, tenantWrites, auditWrites } = createFirestore({
    tenantExists: true,
    tenantData: {
      billingStatus: 'past_due',
    },
  });
  const seatCalls = [];

  const result = await executeManageTenantBillingStateAction({
    firestore,
    tenantId: 'tenant_3',
    action: 'grant_7_days',
    reason: 'support',
    providerHint: '',
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'], preferredProvider: 'stripe' }),
    resolveTenantBillingProviderKey: () => 'stripe',
    loadBillingProviderRuntime: async () => ({
      ok: false,
      message: 'runtime not ready',
    }),
    applyTenantBillingActionToProvider: async () => ({
      applied: true,
      action: 'ok',
      message: 'ok',
    }),
    enforceTenantSeatAllowanceForTenant: async (input) => {
      seatCalls.push(input);
      return { state: 'within_limit' };
    },
    timestampFromDate: (d) => `ts:${d.toISOString()}`,
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.tenantId, 'tenant_3');
  assert.equal(result.body.currentBillingStatus, 'grace');
  assert.equal(result.body.currentBillingAccountState, 'grace');
  assert.equal(result.body.billingProvider, 'stripe');
  assert.equal(result.body.providerAction, 'integration_not_ready');

  assert.equal(tenantWrites.length, 1);
  assert.equal(tenantWrites[0].id, 'tenant_3');
  assert.equal(tenantWrites[0].options.merge, true);
  assert.equal(tenantWrites[0].patch.billingStatus, 'grace');
  assert.equal(tenantWrites[0].patch.billingLastManualAction, 'grant_7_days');

  assert.equal(seatCalls.length, 1);
  assert.equal(seatCalls[0].tenantId, 'tenant_3');

  assert.equal(auditWrites.length, 1);
  assert.equal(auditWrites[0].action, 'billing_grace_set');
  assert.equal(auditWrites[0].details.previousBillingStatus, 'past_due');
  assert.equal(auditWrites[0].details.currentBillingStatus, 'grace');
  assert.equal(auditWrites[0].details.providerAction, 'integration_not_ready');
  assert.match(String(auditWrites[0].createdAt), /^ts:/);
});
