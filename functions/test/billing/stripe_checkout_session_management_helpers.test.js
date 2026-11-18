const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeCreateStripeCheckoutSessionAction,
} = require('../../src/billing/stripe_checkout_session_management_helpers');

function createFirestore({ tenantExists = true, tenantData = {} } = {}) {
  const tenantWrites = [];
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

        throw new Error(`Unexpected collection ${name}`);
      },
    },
    tenantWrites,
  };
}

test('executeCreateStripeCheckoutSessionAction returns permission error when actor is not allowed', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateStripeCheckoutSessionAction({
    firestore,
    payload: {},
    tenantId: 'tenant_1',
    billingPlanKey: 'starter',
    successUrl: 'https://app.example/success',
    cancelUrl: 'https://app.example/cancel',
    authContext: { uid: 'uid_1', email: 'u1@example.com' },
    assertTenantBillingActorPermission: async () => ({
      allowed: false,
      status: 403,
      error: 'owner_required',
      message: 'not allowed',
    }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    loadStripeIntegrationRuntime: async () => ({ ok: true }),
    loadStripePlanMapping: async () => null,
    resolveStripeSeatAddonMappingForBasePlan: async () => null,
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'owner_required');
});

test('executeCreateStripeCheckoutSessionAction returns provider disabled when stripe is inactive', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateStripeCheckoutSessionAction({
    firestore,
    payload: {},
    tenantId: 'tenant_2',
    billingPlanKey: 'starter',
    successUrl: 'https://app.example/success',
    cancelUrl: 'https://app.example/cancel',
    authContext: { uid: 'uid_2', email: 'u2@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    loadStripeIntegrationRuntime: async () => ({ ok: true }),
    loadStripePlanMapping: async () => null,
    resolveStripeSeatAddonMappingForBasePlan: async () => null,
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'provider_disabled');
});

test('executeCreateStripeCheckoutSessionAction returns plan mapping errors', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const missingMapping = await executeCreateStripeCheckoutSessionAction({
    firestore,
    payload: {},
    tenantId: 'tenant_3',
    billingPlanKey: 'starter',
    successUrl: 'https://app.example/success',
    cancelUrl: 'https://app.example/cancel',
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      environment: 'sandbox',
      stripeClient: {
        customers: { create: async () => ({ id: 'cus_3' }) },
        checkout: { sessions: { create: async () => ({ id: 'cs_3', url: 'https://stripe.example/cs_3' }) } },
      },
    }),
    loadStripePlanMapping: async () => null,
    resolveStripeSeatAddonMappingForBasePlan: async () => null,
    billingProviderStripe: 'stripe',
  });

  assert.equal(missingMapping.status, 404);
  assert.equal(missingMapping.body.error, 'plan_mapping_not_found');

  const invalidType = await executeCreateStripeCheckoutSessionAction({
    firestore,
    payload: {},
    tenantId: 'tenant_3',
    billingPlanKey: 'starter',
    successUrl: 'https://app.example/success',
    cancelUrl: 'https://app.example/cancel',
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      environment: 'sandbox',
      stripeClient: {
        customers: { create: async () => ({ id: 'cus_3' }) },
        checkout: { sessions: { create: async () => ({ id: 'cs_3', url: 'https://stripe.example/cs_3' }) } },
      },
    }),
    loadStripePlanMapping: async () => ({ mappingType: 'overage' }),
    resolveStripeSeatAddonMappingForBasePlan: async () => null,
    billingProviderStripe: 'stripe',
  });

  assert.equal(invalidType.status, 400);
  assert.equal(invalidType.body.error, 'invalid_plan_mapping_type');
});

test('executeCreateStripeCheckoutSessionAction creates checkout session and persists tenant patch', async () => {
  const { firestore, tenantWrites } = createFirestore({
    tenantExists: true,
    tenantData: {
      stripeCustomerId: '',
      billingSeatsAddon: 0,
      razaoSocial: 'Acme LTDA',
    },
  });

  const customerCreates = [];
  const sessionCreates = [];

  const result = await executeCreateStripeCheckoutSessionAction({
    firestore,
    payload: { addonSeats: 2 },
    tenantId: 'tenant_4',
    billingPlanKey: 'pro',
    successUrl: 'https://app.example/success',
    cancelUrl: 'https://app.example/cancel',
    authContext: { uid: 'uid_4', email: 'u4@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      environment: 'production',
      stripeClient: {
        customers: {
          create: async (payload) => {
            customerCreates.push(payload);
            return { id: 'cus_new' };
          },
        },
        checkout: {
          sessions: {
            create: async (payload) => {
              sessionCreates.push(payload);
              return { id: 'cs_new', url: 'https://stripe.example/cs_new' };
            },
          },
        },
      },
    }),
    loadStripePlanMapping: async () => ({
      mappingType: 'base',
      stripePriceId: 'price_base',
      includedSeats: 10,
      seatAddonPlanKey: 'pro_addon',
    }),
    resolveStripeSeatAddonMappingForBasePlan: async () => ({
      stripePriceId: 'price_addon',
      billingPlanKey: 'pro_addon',
      stripeUnitAmount: 990,
    }),
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.checkoutSessionId, 'cs_new');
  assert.equal(result.body.stripeCustomerId, 'cus_new');
  assert.equal(result.body.activeEnvironment, 'production');
  assert.equal(result.body.billingSeatsAddon, 2);

  assert.equal(customerCreates.length, 1);
  assert.equal(customerCreates[0].metadata.tenantId, 'tenant_4');

  assert.equal(sessionCreates.length, 1);
  assert.equal(sessionCreates[0].line_items.length, 2);
  assert.equal(sessionCreates[0].line_items[0].price, 'price_base');
  assert.equal(sessionCreates[0].line_items[1].price, 'price_addon');
  assert.equal(sessionCreates[0].line_items[1].quantity, 2);

  assert.equal(tenantWrites.length, 1);
  assert.equal(tenantWrites[0].id, 'tenant_4');
  assert.equal(tenantWrites[0].options.merge, true);
  assert.equal(tenantWrites[0].patch.stripeCustomerId, 'cus_new');
  assert.equal(tenantWrites[0].patch.billingProvider, 'stripe');
  assert.equal(tenantWrites[0].patch.billingPlanKey, 'pro');
  assert.equal(tenantWrites[0].patch.billingSeatsAddon, 2);
  assert.equal(tenantWrites[0].patch.billingSeatAddonPlanKey, 'pro_addon');
  assert.equal(tenantWrites[0].patch.billingSeatAddonUnitPriceCents, 990);
});
