const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeCreateStripePortalSessionAction,
} = require('../../src/billing/stripe_portal_session_management_helpers');

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

test('executeCreateStripePortalSessionAction returns permission error when actor is not allowed', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateStripePortalSessionAction({
    firestore,
    tenantId: 'tenant_1',
    returnUrl: 'https://app.example/return',
    authContext: { uid: 'uid_1', email: 'u1@example.com' },
    assertTenantBillingActorPermission: async () => ({
      allowed: false,
      status: 403,
      error: 'owner_required',
      message: 'not allowed',
    }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    loadStripeIntegrationRuntime: async () => ({ ok: true }),
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'owner_required');
});

test('executeCreateStripePortalSessionAction returns provider disabled when stripe is inactive', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateStripePortalSessionAction({
    firestore,
    tenantId: 'tenant_2',
    returnUrl: 'https://app.example/return',
    authContext: { uid: 'uid_2', email: 'u2@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    loadStripeIntegrationRuntime: async () => ({ ok: true }),
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'provider_disabled');
});

test('executeCreateStripePortalSessionAction returns missing customer error for tenant without stripeCustomerId', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateStripePortalSessionAction({
    firestore,
    tenantId: 'tenant_3',
    returnUrl: 'https://app.example/return',
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      environment: 'sandbox',
      stripeClient: {
        billingPortal: {
          sessions: {
            create: async () => ({ url: 'https://stripe.example/portal/abc' }),
          },
        },
      },
    }),
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 404);
  assert.equal(result.body.error, 'stripe_customer_missing');
});

test('executeCreateStripePortalSessionAction returns portal URL on success', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {
      stripeCustomerId: 'cus_123',
    },
  });

  const calls = [];
  const result = await executeCreateStripePortalSessionAction({
    firestore,
    tenantId: 'tenant_4',
    returnUrl: 'https://app.example/return',
    authContext: { uid: 'uid_4', email: 'u4@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      environment: 'production',
      stripeClient: {
        billingPortal: {
          sessions: {
            create: async (payload) => {
              calls.push(payload);
              return { url: 'https://stripe.example/portal/xyz' };
            },
          },
        },
      },
    }),
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.portalUrl, 'https://stripe.example/portal/xyz');
  assert.equal(result.body.activeEnvironment, 'production');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].customer, 'cus_123');
  assert.equal(calls[0].return_url, 'https://app.example/return');
});
