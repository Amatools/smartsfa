const test = require('node:test');
const assert = require('node:assert/strict');

const {
  reconcileTenantStripeState,
} = require('../../src/billing/stripe_reconcile_helpers');

function createTenantsFirestore(tenantsById) {
  const writes = [];
  const docs = new Map(Object.entries(tenantsById));
  const firestore = {
    collection(name) {
      assert.equal(name, 'tenants');
      return {
        doc(id) {
          return {
            async get() {
              const data = docs.get(id);
              return {
                exists: data !== undefined,
                data: () => (data ? { ...data } : undefined),
              };
            },
            async set(patch, options) {
              writes.push({ id, patch, options });
            },
          };
        },
      };
    },
  };
  return { firestore, writes };
}

test('reconcileTenantStripeState rejects missing tenant and missing references', async () => {
  const missing = createTenantsFirestore({});
  await assert.rejects(
    () =>
      reconcileTenantStripeState({
        firestore: missing.firestore,
        stripeClient: { subscriptions: {} },
        tenantId: 'tenant_missing',
        billingProviderStripe: 'stripe',
        readStripeSubscriptionPriceId: () => '',
        resolveStripePlanMappingByPriceId: async () => null,
        buildTenantPatchFromStripeSubscription: () => ({}),
        readStripeSubscriptionPeriodFromInvoices: async () => ({ startIso: '', endIso: '' }),
      }),
    /Tenant nao encontrado para reconciliacao/,
  );

  const noRefs = createTenantsFirestore({
    tenant_1: {
      billingStatus: 'active',
    },
  });

  await assert.rejects(
    () =>
      reconcileTenantStripeState({
        firestore: noRefs.firestore,
        stripeClient: { subscriptions: {} },
        tenantId: 'tenant_1',
        billingProviderStripe: 'stripe',
        readStripeSubscriptionPriceId: () => '',
        resolveStripePlanMappingByPriceId: async () => null,
        buildTenantPatchFromStripeSubscription: () => ({}),
        readStripeSubscriptionPeriodFromInvoices: async () => ({ startIso: '', endIso: '' }),
      }),
    /Tenant sem stripeCustomerId\/stripeSubscriptionId para reconciliar/,
  );
});

test('reconcileTenantStripeState patches from active subscription and fills missing period', async () => {
  const { firestore, writes } = createTenantsFirestore({
    tenant_2: {
      billingStatus: 'past_due',
      stripeCustomerId: 'cus_2',
      stripeSubscriptionId: 'sub_2',
      billingPlanKey: 'legacy',
    },
  });

  const stripeClient = {
    subscriptions: {
      retrieve: async () => ({ id: 'sub_2', status: 'active' }),
      list: async () => ({ data: [] }),
    },
  };

  const result = await reconcileTenantStripeState({
    firestore,
    stripeClient,
    tenantId: 'tenant_2',
    billingProviderStripe: 'stripe',
    readStripeSubscriptionPriceId: () => 'price_2',
    resolveStripePlanMappingByPriceId: async () => ({ billingPlanKey: 'enterprise' }),
    buildTenantPatchFromStripeSubscription: () => ({
      stripeSubscriptionId: 'sub_2',
      billingStatus: 'active',
      billingUpdatedAt: '2026-01-01T00:00:00.000Z',
      billingCurrentPeriodStartAt: '',
      billingCurrentPeriodEndAt: '',
    }),
    readStripeSubscriptionPeriodFromInvoices: async () => ({
      startIso: '2026-01-01T00:00:00.000Z',
      endIso: '2026-02-01T00:00:00.000Z',
    }),
  });

  assert.equal(writes.length, 1);
  assert.equal(writes[0].id, 'tenant_2');
  assert.equal(writes[0].options.merge, true);
  assert.equal(writes[0].patch.billingStatus, 'active');
  assert.equal(writes[0].patch.billingCurrentPeriodStartAt, '2026-01-01T00:00:00.000Z');
  assert.equal(writes[0].patch.billingCurrentPeriodEndAt, '2026-02-01T00:00:00.000Z');
  assert.equal(result.currentBillingStatus, 'active');
});

test('reconcileTenantStripeState falls back to customer list and canceled patch when no subscription found', async () => {
  const { firestore, writes } = createTenantsFirestore({
    tenant_3: {
      billingStatus: 'active',
      stripeCustomerId: 'cus_3',
      stripeSubscriptionId: 'sub_legacy',
    },
  });

  const stripeClient = {
    subscriptions: {
      retrieve: async () => {
        throw new Error('not_found');
      },
      list: async () => ({ data: [] }),
    },
  };

  const result = await reconcileTenantStripeState({
    firestore,
    stripeClient,
    tenantId: 'tenant_3',
    billingProviderStripe: 'stripe',
    readStripeSubscriptionPriceId: () => '',
    resolveStripePlanMappingByPriceId: async () => null,
    buildTenantPatchFromStripeSubscription: () => ({}),
    readStripeSubscriptionPeriodFromInvoices: async () => ({ startIso: '', endIso: '' }),
  });

  assert.equal(writes.length, 1);
  assert.equal(writes[0].patch.billingProvider, 'stripe');
  assert.equal(writes[0].patch.billingContractProvider, 'stripe');
  assert.equal(writes[0].patch.billingStatus, 'canceled');
  assert.equal(result.currentBillingStatus, 'canceled');
});
