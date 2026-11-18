const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeCreateBillingPortalSessionAction,
} = require('../../src/billing/portal_session_management_helpers');

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

test('executeCreateBillingPortalSessionAction returns permission error when actor is not allowed', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateBillingPortalSessionAction({
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
    stripePortalFunctionUrl: 'https://example.test/portal',
    readAsaasIntegrationConfig: async () => ({ activeEnvironment: 'sandbox' }),
    resolveAsaasPortalFallbackUrl: () => '',
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'owner_required');
});

test('executeCreateBillingPortalSessionAction delegates stripe provider to proxy', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: { stripeCustomerId: 'cus_1' },
  });
  const proxyCalls = [];

  const result = await executeCreateBillingPortalSessionAction({
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
    stripePortalFunctionUrl: 'https://example.test/portal',
    readAsaasIntegrationConfig: async () => ({ activeEnvironment: 'sandbox' }),
    resolveAsaasPortalFallbackUrl: () => '',
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, true);
  assert.equal(proxyCalls.length, 1);
  assert.equal(proxyCalls[0].targetUrl, 'https://example.test/portal');
  assert.equal(proxyCalls[0].method, 'POST');
  assert.equal(proxyCalls[0].extraResponseFields.billingProvider, 'stripe');
});

test('executeCreateBillingPortalSessionAction returns portal reference not found for asaas without URL', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateBillingPortalSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {},
    tenantId: 'tenant_3',
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripePortalFunctionUrl: 'https://example.test/portal',
    readAsaasIntegrationConfig: async () => ({ activeEnvironment: 'production' }),
    resolveAsaasPortalFallbackUrl: () => '',
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'portal_reference_not_found');
  assert.equal(result.body.activeEnvironment, 'production');
});

test('executeCreateBillingPortalSessionAction returns asaas fallback portal URL when available', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: { asaasInvoiceUrl: 'https://asaas.example/i/1' },
  });

  const result = await executeCreateBillingPortalSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {},
    tenantId: 'tenant_4',
    authContext: { uid: 'uid_4', email: 'u4@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'tenant_linked_contract',
      hasLinkedContract: true,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripePortalFunctionUrl: 'https://example.test/portal',
    readAsaasIntegrationConfig: async () => ({ activeEnvironment: 'sandbox' }),
    resolveAsaasPortalFallbackUrl: () => 'https://asaas.example/i/1',
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 200);
  assert.equal(result.body.portalUrl, 'https://asaas.example/i/1');
  assert.equal(result.body.billingProvider, 'asaas');
});
