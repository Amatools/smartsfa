const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeListStripeCatalogAction,
  executeCreateStripeCatalogPlanAction,
} = require('../../src/billing/stripe_catalog_management_helpers');

function createFirestoreWithAudit() {
  const auditWrites = [];

  return {
    firestore: {
      collection(name) {
        if (name !== 'platform_admin_audit') {
          throw new Error(`Unexpected collection ${name}`);
        }

        return {
          async add(payload) {
            auditWrites.push(payload);
          },
        };
      },
    },
    auditWrites,
  };
}

test('executeListStripeCatalogAction returns platform access errors', async () => {
  const result = await executeListStripeCatalogAction({
    firestore: {},
    payload: {},
    authContext: { uid: 'uid_1', email: 'u1@example.com' },
    assertPlatformAdminActor: async () => ({
      allowed: false,
      status: 403,
      error: 'forbidden',
      message: 'not allowed',
    }),
    loadStripeIntegrationRuntime: async () => ({ ok: true }),
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'forbidden');
});

test('executeListStripeCatalogAction lists products and prices with normalized limits', async () => {
  const productsArgs = [];
  const pricesArgs = [];

  const result = await executeListStripeCatalogAction({
    firestore: {},
    payload: {
      limitProducts: 300,
      limitPricesPerProduct: 0,
      activeOnly: false,
    },
    authContext: { uid: 'uid_2', email: 'u2@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      environment: 'test',
      stripeClient: {
        accounts: {
          async retrieve() {
            return { id: 'acct_1' };
          },
        },
        products: {
          async list(args) {
            productsArgs.push(args);
            return {
              has_more: false,
              data: [
                {
                  id: 'prod_1',
                  name: 'Plano Base',
                  description: 'Descricao',
                  active: true,
                  default_price: 'price_default',
                },
              ],
            };
          },
        },
        prices: {
          async list(args) {
            pricesArgs.push(args);
            return {
              data: [
                {
                  id: 'price_1',
                  lookup_key: 'plan_base_monthly',
                  nickname: 'Mensal',
                  active: true,
                  currency: 'brl',
                  type: 'recurring',
                  recurring: { interval: 'month', interval_count: 1 },
                  unit_amount: 9900,
                  unit_amount_decimal: '9900',
                  tax_behavior: 'exclusive',
                },
              ],
            };
          },
        },
      },
    }),
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.activeEnvironment, 'test');
  assert.equal(result.body.stripeAccountId, 'acct_1');
  assert.equal(result.body.totalProducts, 1);
  assert.equal(result.body.products[0].productId, 'prod_1');
  assert.equal(result.body.products[0].prices[0].priceId, 'price_1');

  assert.equal(productsArgs.length, 1);
  assert.equal(productsArgs[0].limit, 100);
  assert.equal(productsArgs[0].active, undefined);

  assert.equal(pricesArgs.length, 1);
  assert.equal(pricesArgs[0].limit, 1);
  assert.equal(pricesArgs[0].active, undefined);
});

test('executeListStripeCatalogAction maps internal errors to stripe_catalog_list_failed', async () => {
  const result = await executeListStripeCatalogAction({
    firestore: {},
    payload: {},
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      stripeClient: {
        accounts: {
          async retrieve() {
            throw new Error('stripe_down');
          },
        },
      },
    }),
  });

  assert.equal(result.status, 500);
  assert.equal(result.body.error, 'stripe_catalog_list_failed');
  assert.equal(result.body.message, 'stripe_down');
});

test('executeCreateStripeCatalogPlanAction validates required payload fields', async () => {
  const result = await executeCreateStripeCatalogPlanAction({
    firestore: {},
    payload: {
      billingPlanKey: 'enterprise_plus',
      amountMinorUnits: 1000,
    },
    authContext: { uid: 'uid_4', email: 'u4@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadStripeIntegrationRuntime: async () => ({ ok: true }),
    normalizeBillingPlanKey: (value) => String(value || '').trim().toLowerCase(),
    buildStripeRecommendedLookupKey: () => 'recommended_key',
    buildStripeCatalogPlanMetadata: () => ({}),
    timestampFromDate: (d) => d.toISOString(),
  });

  assert.equal(result.status, 400);
  assert.equal(result.body.error, 'invalid_payload');
  assert.equal(result.body.message, 'productName e obrigatorio.');
});

test('executeCreateStripeCatalogPlanAction returns integration errors', async () => {
  const result = await executeCreateStripeCatalogPlanAction({
    firestore: {},
    payload: {
      productName: 'Plano Plus',
      billingPlanKey: 'enterprise_plus',
      amountMinorUnits: 1000,
    },
    authContext: { uid: 'uid_5', email: 'u5@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadStripeIntegrationRuntime: async () => ({
      ok: false,
      status: 503,
      error: 'integration_not_ready',
      message: 'runtime unavailable',
    }),
    normalizeBillingPlanKey: (value) => String(value || '').trim().toLowerCase(),
    buildStripeRecommendedLookupKey: () => 'recommended_key',
    buildStripeCatalogPlanMetadata: () => ({}),
    timestampFromDate: (d) => d.toISOString(),
  });

  assert.equal(result.status, 503);
  assert.equal(result.body.error, 'integration_not_ready');
});

test('executeCreateStripeCatalogPlanAction creates product and price and writes audit', async () => {
  const { firestore, auditWrites } = createFirestoreWithAudit();
  const pricePayloads = [];

  const result = await executeCreateStripeCatalogPlanAction({
    firestore,
    payload: {
      productName: 'Plano Plus',
      productDescription: 'Plano pago',
      billingPlanKey: 'enterprise_plus',
      currency: 'BRL',
      recurringInterval: 'month',
      recurringIntervalCount: 1,
      amountMinorUnits: 19900,
      priceNickname: 'Mensal Plus',
      lookupKey: 'enterprise_plus_monthly',
      taxBehavior: 'exclusive',
      active: true,
    },
    authContext: { uid: 'uid_6', email: 'u6@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      environment: 'production',
      stripeClient: {
        accounts: {
          async retrieve() {
            return { id: 'acct_live' };
          },
        },
        products: {
          async create(payload) {
            return {
              id: 'prod_live',
              name: payload.name,
              description: payload.description,
            };
          },
        },
        prices: {
          async create(payload) {
            pricePayloads.push(payload);
            return {
              id: 'price_live',
              nickname: payload.nickname,
              lookup_key: payload.lookup_key,
              currency: payload.currency,
              unit_amount: payload.unit_amount,
              recurring: payload.recurring,
            };
          },
        },
      },
    }),
    normalizeBillingPlanKey: (value) => String(value || '').trim().toLowerCase(),
    buildStripeRecommendedLookupKey: () => 'recommended_key',
    buildStripeCatalogPlanMetadata: ({ billingPlanKey }) => ({
      billing_plan_key: billingPlanKey,
    }),
    timestampFromDate: (d) => `ts:${d.toISOString()}`,
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.activeEnvironment, 'production');
  assert.equal(result.body.stripeAccountId, 'acct_live');
  assert.equal(result.body.productId, 'prod_live');
  assert.equal(result.body.priceId, 'price_live');
  assert.equal(result.body.lookupKey, 'enterprise_plus_monthly');

  assert.equal(pricePayloads.length, 1);
  assert.equal(pricePayloads[0].tax_behavior, 'exclusive');

  assert.equal(auditWrites.length, 1);
  assert.equal(auditWrites[0].action, 'stripe_catalog_plan_created');
  assert.equal(auditWrites[0].details.billingPlanKey, 'enterprise_plus');
  assert.match(String(auditWrites[0].createdAt), /^ts:/);
});

test('executeCreateStripeCatalogPlanAction maps stripe API error payload', async () => {
  const result = await executeCreateStripeCatalogPlanAction({
    firestore: {},
    payload: {
      productName: 'Plano Plus',
      billingPlanKey: 'enterprise_plus',
      amountMinorUnits: 19900,
    },
    authContext: { uid: 'uid_7', email: 'u7@example.com' },
    assertPlatformAdminActor: async () => ({ allowed: true }),
    loadStripeIntegrationRuntime: async () => ({
      ok: true,
      environment: 'test',
      stripeClient: {
        accounts: {
          async retrieve() {
            return { id: 'acct_test' };
          },
        },
        products: {
          async create() {
            const error = new Error('generic');
            error.statusCode = 409;
            error.raw = { message: 'lookup key already exists' };
            throw error;
          },
        },
      },
    }),
    normalizeBillingPlanKey: (value) => String(value || '').trim().toLowerCase(),
    buildStripeRecommendedLookupKey: () => 'recommended_key',
    buildStripeCatalogPlanMetadata: () => ({}),
    timestampFromDate: (d) => d.toISOString(),
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'stripe_catalog_create_plan_failed');
  assert.equal(result.body.message, 'lookup key already exists');
});
