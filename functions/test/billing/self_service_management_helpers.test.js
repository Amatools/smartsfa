const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeTenantBillingSelfServiceAction,
} = require('../../src/billing/self_service_management_helpers');

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

        if (name === 'tenant_billing_audit') {
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

test('executeTenantBillingSelfServiceAction returns permission error when actor is not allowed', async () => {
  const { firestore, tenantWrites, auditWrites } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeTenantBillingSelfServiceAction({
    firestore,
    payload: {},
    tenantId: 'tenant_1',
    action: 'stop_renewal',
    reason: 'x',
    authContext: { uid: 'uid_1', email: 'u1@example.com' },
    assertTenantBillingActorPermission: async () => ({
      allowed: false,
      status: 403,
      error: 'owner_required',
      message: 'not allowed',
    }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({ provider: 'asaas', hasLinkedContract: true }),
    loadBillingProviderRuntime: async () => ({ ok: true }),
    applyTenantBillingSelfServiceActionToProvider: async () => ({ applied: true }),
    mapBillingStatusToAccountState: () => 'active',
    enforceTenantSeatAllowanceForTenant: async () => ({}),
    timestampFromDate: (d) => d.toISOString(),
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'owner_required');
  assert.equal(tenantWrites.length, 0);
  assert.equal(auditWrites.length, 0);
});

test('executeTenantBillingSelfServiceAction rejects providers other than asaas', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeTenantBillingSelfServiceAction({
    firestore,
    payload: {},
    tenantId: 'tenant_2',
    action: 'cancel_now',
    reason: '',
    authContext: { uid: 'uid_2', email: 'u2@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe', 'asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'tenant_linked_contract',
      hasLinkedContract: true,
    }),
    loadBillingProviderRuntime: async () => ({ ok: true }),
    applyTenantBillingSelfServiceActionToProvider: async () => ({ applied: true }),
    mapBillingStatusToAccountState: () => 'active',
    enforceTenantSeatAllowanceForTenant: async () => ({}),
    timestampFromDate: (d) => d.toISOString(),
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'self_service_action_not_supported_for_provider');
  assert.equal(result.body.billingProvider, 'stripe');
});

test('executeTenantBillingSelfServiceAction applies action, persists patch and writes audit', async () => {
  const { firestore, tenantWrites, auditWrites } = createFirestore({
    tenantExists: true,
    tenantData: {
      asaasSubscriptionId: 'sub_1',
    },
  });

  const seatCalls = [];
  const result = await executeTenantBillingSelfServiceAction({
    firestore,
    payload: {},
    tenantId: 'tenant_3',
    action: 'stop_renewal',
    reason: 'owner request',
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    loadBillingProviderRuntime: async () => ({
      ok: true,
      environment: 'sandbox',
      asaasApiKey: 'key',
      asaasApiBaseUrl: 'https://sandbox.asaas.com',
    }),
    applyTenantBillingSelfServiceActionToProvider: async () => ({
      applied: true,
      action: 'subscription_inactivated',
      message: 'done',
      billingStatus: 'suspended',
    }),
    mapBillingStatusToAccountState: (status) => (status === 'suspended' ? 'suspended' : 'active'),
    enforceTenantSeatAllowanceForTenant: async (input) => {
      seatCalls.push(input);
      return { state: 'over_limit_grace' };
    },
    timestampFromDate: (d) => `ts:${d.toISOString()}`,
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.billingProvider, 'asaas');
  assert.equal(result.body.providerAction, 'subscription_inactivated');
  assert.equal(result.body.billingStatus, 'suspended');
  assert.equal(seatCalls.length, 1);
  assert.equal(seatCalls[0].tenantId, 'tenant_3');

  assert.equal(tenantWrites.length, 1);
  assert.equal(tenantWrites[0].id, 'tenant_3');
  assert.equal(tenantWrites[0].options.merge, true);
  assert.equal(tenantWrites[0].patch.billingStatus, 'suspended');
  assert.equal(tenantWrites[0].patch.billingAccountState, 'suspended');

  assert.equal(auditWrites.length, 1);
  assert.equal(auditWrites[0].action, 'self_service_stop_renewal');
  assert.equal(auditWrites[0].tenantId, 'tenant_3');
  assert.equal(auditWrites[0].actorUid, 'uid_3');
  assert.equal(auditWrites[0].details.providerAction, 'subscription_inactivated');
  assert.equal(auditWrites[0].details.seatEnforcementSummary.state, 'over_limit_grace');
  assert.match(String(auditWrites[0].createdAt), /^ts:/);
});
