const test = require('node:test');
const assert = require('node:assert/strict');

const {
  reconcileTenantStripePeriodIfMissing,
} = require('../../src/billing/stripe_period_reconcile_helpers');

function createTenantsFirestore(tenantsById) {
  const docs = new Map(Object.entries(tenantsById));
  return {
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
          };
        },
      };
    },
  };
}

test('reconcileTenantStripePeriodIfMissing skips when stripe client is missing', async () => {
  const firestore = createTenantsFirestore({
    tenant_1: {
      billingStatus: 'active',
      stripeCustomerId: 'cus_1',
      billingCurrentPeriodStartAt: '',
      billingCurrentPeriodEndAt: '',
    },
  });

  let called = 0;
  await reconcileTenantStripePeriodIfMissing({
    firestore,
    stripeClient: null,
    tenantId: 'tenant_1',
    source: 'invoice.paid',
    stripeProviderKey: 'stripe',
    reconcileTenantBillingState: async () => {
      called += 1;
    },
  });

  assert.equal(called, 0);
});

test('reconcileTenantStripePeriodIfMissing skips when tenant is missing or conditions are not met', async () => {
  const firestoreMissing = createTenantsFirestore({});
  let called = 0;

  await reconcileTenantStripePeriodIfMissing({
    firestore: firestoreMissing,
    stripeClient: {},
    tenantId: 'tenant_missing',
    source: 'invoice.paid',
    stripeProviderKey: 'stripe',
    reconcileTenantBillingState: async () => {
      called += 1;
    },
  });

  const firestoreNoNeed = createTenantsFirestore({
    tenant_2: {
      billingStatus: 'active',
      stripeCustomerId: 'cus_2',
      billingCurrentPeriodStartAt: '2026-01-01T00:00:00.000Z',
      billingCurrentPeriodEndAt: '2026-02-01T00:00:00.000Z',
    },
  });

  await reconcileTenantStripePeriodIfMissing({
    firestore: firestoreNoNeed,
    stripeClient: {},
    tenantId: 'tenant_2',
    source: 'invoice.paid',
    stripeProviderKey: 'stripe',
    reconcileTenantBillingState: async () => {
      called += 1;
    },
  });

  assert.equal(called, 0);
});

test('reconcileTenantStripePeriodIfMissing triggers reconcile when conditions match', async () => {
  const firestore = createTenantsFirestore({
    tenant_3: {
      billingStatus: 'past_due',
      stripeSubscriptionId: 'sub_3',
      billingCurrentPeriodStartAt: '',
      billingCurrentPeriodEndAt: '2026-02-01T00:00:00.000Z',
    },
  });

  const calls = [];
  await reconcileTenantStripePeriodIfMissing({
    firestore,
    stripeClient: { marker: true },
    tenantId: 'tenant_3',
    source: 'invoice.payment_failed',
    stripeProviderKey: 'stripe',
    reconcileTenantBillingState: async (input) => {
      calls.push(input);
    },
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].providerKey, 'stripe');
  assert.equal(calls[0].tenantId, 'tenant_3');
  assert.ok(calls[0].stripeClient);
});

test('reconcileTenantStripePeriodIfMissing swallows reconcile errors', async () => {
  const firestore = createTenantsFirestore({
    tenant_4: {
      billingStatus: 'active',
      stripeCustomerId: 'cus_4',
      billingCurrentPeriodStartAt: '',
      billingCurrentPeriodEndAt: '',
    },
  });

  await assert.doesNotReject(async () => {
    await reconcileTenantStripePeriodIfMissing({
      firestore,
      stripeClient: { marker: true },
      tenantId: 'tenant_4',
      source: 'checkout.session.completed',
      stripeProviderKey: 'stripe',
      reconcileTenantBillingState: async () => {
        throw new Error('reconcile_failed');
      },
    });
  });
});
