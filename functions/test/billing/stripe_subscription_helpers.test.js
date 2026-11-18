const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildTenantPatchFromStripeSubscription,
  mapStripeSubscriptionStatusToBillingStatus,
  readStripeInvoicePeriodBounds,
  readStripeSubscriptionLineItems,
  readStripeSubscriptionPeriodBounds,
  readStripeSubscriptionPeriodFromInvoices,
  readStripeSubscriptionPriceId,
} = require('../../src/billing/stripe_subscription_helpers');

test('readStripeSubscriptionPriceId and line items normalize payload', () => {
  const subscription = {
    items: {
      data: [
        { price: { id: 'price_base', recurring: { interval: 'month' } }, quantity: 1 },
        { price: { id: 'price_addon' }, quantity: '2.7' },
        { price: { id: '' }, quantity: 5 },
      ],
    },
  };

  assert.equal(readStripeSubscriptionPriceId(subscription), 'price_base');
  assert.deepEqual(readStripeSubscriptionLineItems(subscription), [
    { priceId: 'price_base', quantity: 1 },
    { priceId: 'price_addon', quantity: 2 },
  ]);
});

test('mapStripeSubscriptionStatusToBillingStatus keeps expected contract', () => {
  assert.equal(mapStripeSubscriptionStatusToBillingStatus('trialing'), 'trial');
  assert.equal(mapStripeSubscriptionStatusToBillingStatus('active'), 'active');
  assert.equal(mapStripeSubscriptionStatusToBillingStatus('unpaid'), 'past_due');
  assert.equal(mapStripeSubscriptionStatusToBillingStatus('paused'), 'suspended');
  assert.equal(mapStripeSubscriptionStatusToBillingStatus('canceled'), 'canceled');
  assert.equal(mapStripeSubscriptionStatusToBillingStatus('unknown'), 'active');
});

test('readStripeSubscriptionPeriodBounds reads direct and line item periods', () => {
  const withDirect = {
    current_period_start: 1700000000,
    current_period_end: 1702592000,
  };
  const direct = readStripeSubscriptionPeriodBounds(withDirect);
  assert.equal(direct.startIso, '2023-11-14T22:13:20.000Z');
  assert.equal(direct.endIso, '2023-12-14T22:13:20.000Z');

  const withItems = {
    items: {
      data: [
        {
          current_period: {
            start: 1700100000,
            end: 1702692000,
          },
        },
      ],
    },
  };
  const fromItems = readStripeSubscriptionPeriodBounds(withItems);
  assert.equal(fromItems.startIso, '2023-11-16T02:00:00.000Z');
  assert.equal(fromItems.endIso, '2023-12-16T02:00:00.000Z');
});

test('readStripeInvoicePeriodBounds computes min start and max end', () => {
  const invoice = {
    lines: {
      data: [
        { period: { start: 1700200000, end: 1701000000 } },
        { period: { start: 1700000000, end: 1702000000 } },
      ],
    },
  };

  assert.deepEqual(readStripeInvoicePeriodBounds(invoice), {
    startIso: '2023-11-14T22:13:20.000Z',
    endIso: '2023-12-08T01:46:40.000Z',
  });
});

test('readStripeSubscriptionPeriodFromInvoices returns first valid period', async () => {
  const stripeClient = {
    invoices: {
      list: async () => ({
        data: [
          { lines: { data: [] } },
          {
            lines: {
              data: [
                { period: { start: 1700000000, end: 1702592000 } },
              ],
            },
          },
        ],
      }),
    },
  };

  const bounds = await readStripeSubscriptionPeriodFromInvoices({
    stripeClient,
    subscriptionId: 'sub_123',
  });
  assert.deepEqual(bounds, {
    startIso: '2023-11-14T22:13:20.000Z',
    endIso: '2023-12-14T22:13:20.000Z',
  });
});

test('buildTenantPatchFromStripeSubscription normalizes billing fields', () => {
  const subscription = {
    id: 'sub_abc',
    customer: 'cus_abc',
    status: 'past_due',
    items: {
      data: [
        {
          price: {
            id: 'price_base',
            recurring: { interval: 'year' },
          },
        },
      ],
    },
    current_period_start: 1700000000,
    current_period_end: 1702592000,
  };

  const patch = buildTenantPatchFromStripeSubscription({
    subscription,
    billingPlanKey: ' Enterprise ',
  });

  assert.equal(patch.billingProvider, 'stripe');
  assert.equal(patch.billingContractProvider, 'stripe');
  assert.equal(patch.stripeCustomerId, 'cus_abc');
  assert.equal(patch.stripeSubscriptionId, 'sub_abc');
  assert.equal(patch.stripePriceId, 'price_base');
  assert.equal(patch.billingStatus, 'past_due');
  assert.equal(patch.billingCycle, 'year');
  assert.equal(patch.billingPlanKey, 'enterprise');
  assert.equal(patch.billingCurrentPeriodStartAt, '2023-11-14T22:13:20.000Z');
  assert.equal(patch.billingCurrentPeriodEndAt, '2023-12-14T22:13:20.000Z');
  assert.ok(patch.billingUpdatedAt);
  assert.ok(patch.billingContractLinkedAt);
  assert.equal(patch.billingPastDueSinceAt, patch.billingUpdatedAt);
});
