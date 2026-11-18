const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeListBillingCheckoutPlansAction,
} = require('../../src/billing/checkout_plan_listing_management_helpers');

function createFirestore({ tenantExists = true, tenantData = {} } = {}) {
  return {
    firestore: {
      collection(name) {
        if (name === 'tenants') {
          return {
            doc() {
              return {
                async get() {
                  return {
                    exists: tenantExists,
                    data: () => (tenantExists ? { ...tenantData } : undefined),
                  };
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

test('executeListBillingCheckoutPlansAction returns permission error when actor is not allowed', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeListBillingCheckoutPlansAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {},
    tenantId: 'tenant_1',
    authContext: { uid: 'uid_1', email: 'u1@example.com' },
    assertTenantBillingActorPermission: async () => ({
      allowed: false,
      status: 403,
      error: 'owner_required',
      message: 'not allowed',
    }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    resolveCheckoutApiProviderSelection: () => ({ provider: 'stripe' }),
    proxyBillingRequestToFunction: async () => {},
    stripeListPlansFunctionUrl: 'https://example.test/list',
    listAsaasCheckoutPlansForTenant: async () => ({ plans: [] }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'owner_required');
});

test('executeListBillingCheckoutPlansAction returns provider_disabled for inactive provider without linked contract', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeListBillingCheckoutPlansAction({
    firestore,
    request: { method: 'GET' },
    response: {},
    payload: {},
    tenantId: 'tenant_2',
    authContext: { uid: 'uid_2', email: 'u2@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'tenant_linked_contract',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripeListPlansFunctionUrl: 'https://example.test/list',
    listAsaasCheckoutPlansForTenant: async () => ({ plans: [] }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'provider_disabled');
});

test('executeListBillingCheckoutPlansAction delegates stripe requests to proxy', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: { workspaceType: 'brand_owner_workspace' },
  });
  const proxyCalls = [];

  const request = { method: 'POST' };
  const response = {};

  const result = await executeListBillingCheckoutPlansAction({
    firestore,
    request,
    response,
    payload: {},
    tenantId: 'tenant_3',
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe', 'asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async (input) => {
      proxyCalls.push(input);
    },
    stripeListPlansFunctionUrl: 'https://example.test/list',
    listAsaasCheckoutPlansForTenant: async () => ({ plans: [] }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, true);
  assert.equal(proxyCalls.length, 1);
  assert.equal(proxyCalls[0].targetUrl, 'https://example.test/list');
  assert.equal(proxyCalls[0].method, 'POST');
  assert.equal(proxyCalls[0].extraResponseFields.billingProvider, 'stripe');
  assert.equal(proxyCalls[0].extraResponseFields.providerSelectionSource, 'payload_provider');
});

test('executeListBillingCheckoutPlansAction returns listed plans for asaas provider', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: { workspaceType: 'revenda_workspace' },
  });

  const result = await executeListBillingCheckoutPlansAction({
    firestore,
    request: { method: 'GET' },
    response: {},
    payload: {},
    tenantId: 'tenant_4',
    authContext: { uid: 'uid_4', email: 'u4@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: true,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripeListPlansFunctionUrl: 'https://example.test/list',
    listAsaasCheckoutPlansForTenant: async () => ({
      workspaceType: 'revenda_workspace',
      requiredPrefix: 'revenda',
      plans: [{ billingPlanKey: 'revenda_pro' }],
    }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 200);
  assert.equal(result.body.tenantId, 'tenant_4');
  assert.equal(result.body.billingProvider, 'asaas');
  assert.equal(result.body.workspaceType, 'revenda_workspace');
  assert.equal(result.body.requiredPrefix, 'revenda');
  assert.equal(result.body.plans.length, 1);
  assert.equal(result.body.plans[0].billingPlanKey, 'revenda_pro');
});
