const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeCreateBillingCheckoutSessionAction,
} = require('../../src/billing/checkout_session_management_helpers');

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

test('executeCreateBillingCheckoutSessionAction returns permission error when actor is not allowed', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateBillingCheckoutSessionAction({
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
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({ ok: true }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'owner_required');
});

test('executeCreateBillingCheckoutSessionAction delegates stripe requests to proxy', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: { workspaceType: 'brand_owner_workspace' },
  });
  const proxyCalls = [];

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {},
    tenantId: 'tenant_2',
    authContext: { uid: 'uid_2', email: 'u2@example.com' },
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
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({ ok: true }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, true);
  assert.equal(proxyCalls.length, 1);
  assert.equal(proxyCalls[0].targetUrl, 'https://example.test/checkout');
  assert.equal(proxyCalls[0].method, 'POST');
  assert.equal(proxyCalls[0].extraResponseFields.billingProvider, 'stripe');
});

test('executeCreateBillingCheckoutSessionAction returns provider_disabled for inactive provider without linked contract', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {},
    tenantId: 'tenant_3',
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'tenant_linked_contract',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({ ok: true }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'provider_disabled');
});

test('executeCreateBillingCheckoutSessionAction returns asaas provider result when checkout helper succeeds', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: { workspaceType: 'revenda_workspace' },
  });

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: { billingPlanKey: 'revenda_pro' },
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
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({
      ok: true,
      status: 200,
      body: {
        checkoutUrl: 'https://asaas.example/checkout/abc',
      },
    }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 200);
  assert.equal(result.body.checkoutUrl, 'https://asaas.example/checkout/abc');
});

test('executeCreateBillingCheckoutSessionAction maps asaas exceptions to provider_checkout_failed', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {},
    tenantId: 'tenant_5',
    authContext: { uid: 'uid_5', email: 'u5@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => {
      throw new Error('checkout failed');
    },
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 502);
  assert.equal(result.body.error, 'provider_checkout_failed');
  assert.match(result.body.message, /checkout failed/);
});
