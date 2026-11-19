const test = require('node:test');
const assert = require('node:assert/strict');

const {
  applyStripeWebhookEventToTenant,
} = require('../../src/billing/stripe_webhook_application_helpers');

function createTenantsFirestore({ initialTenants = {} } = {}) {
  const writes = [];
  const docs = new Map(
    Object.entries(initialTenants).map(([id, data]) => [id, { ...data }]),
  );

  return {
    writes,
    docs,
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
            id,
            async set(patch, options) {
              writes.push({ id, patch: { ...patch }, options: { ...options } });
              const current = docs.get(id) || {};
              docs.set(id, { ...current, ...patch });
            },
          };
        },
      };
    },
  };
}

function normalizePlanKey(value) {
  return String(value ?? '').trim().toLowerCase();
}

test('applyStripeWebhookEventToTenant throws when checkout tenant cannot be resolved', async () => {
  const firestore = createTenantsFirestore();

  await assert.rejects(
    () =>
      applyStripeWebhookEventToTenant({
        firestore,
        event: {
          type: 'checkout.session.completed',
          data: { object: { id: 'cs_1', customer: 'cus_1', subscription: 'sub_1' } },
        },
        stripeClient: {},
        normalizeBillingPlanKey: normalizePlanKey,
        resolveTenantIdFromStripeReferences: async () => '',
        readStripeSubscriptionLineItems: () => [],
        resolveStripePlanMappingByPriceId: async () => null,
        buildTenantPatchFromStripeSubscription: () => ({}),
        reconcileTenantStripePeriodIfMissing: async () => {},
        reconcileTenantBillingState: async () => {},
        enforceTenantSeatAllowanceForTenant: async () => {},
        billingProviderStripe: 'stripe',
      }),
    /checkout\.session\.completed sem tenantId resolvido/,
  );
});

test('applyStripeWebhookEventToTenant updates tenant on checkout completion', async () => {
  const firestore = createTenantsFirestore();
  const reconcileCalls = [];
  const enforcementCalls = [];

  const tenantId = await applyStripeWebhookEventToTenant({
    firestore,
    event: {
      type: 'checkout.session.completed',
      data: {
        object: {
          id: 'cs_1',
          customer: 'cus_1',
          subscription: 'sub_1',
          metadata: {
            tenantId: 'tenant_1',
            billingPlanKey: 'Enterprise',
          },
        },
      },
    },
    stripeClient: {},
    normalizeBillingPlanKey: normalizePlanKey,
    resolveTenantIdFromStripeReferences: async () => 'tenant_1',
    readStripeSubscriptionLineItems: () => [],
    resolveStripePlanMappingByPriceId: async () => null,
    buildTenantPatchFromStripeSubscription: () => ({}),
    reconcileTenantStripePeriodIfMissing: async (input) => {
      reconcileCalls.push(input);
    },
    reconcileTenantBillingState: async () => {},
    enforceTenantSeatAllowanceForTenant: async (input) => {
      enforcementCalls.push(input);
    },
    billingProviderStripe: 'stripe',
  });

  assert.equal(tenantId, 'tenant_1');
  assert.equal(firestore.writes.length, 1);
  assert.equal(firestore.writes[0].id, 'tenant_1');
  assert.equal(firestore.writes[0].options.merge, true);
  assert.equal(firestore.writes[0].patch.billingProvider, 'stripe');
  assert.equal(firestore.writes[0].patch.billingPlanKey, 'enterprise');
  assert.equal(firestore.writes[0].patch.stripeCheckoutSessionId, 'cs_1');
  assert.equal(firestore.writes[0].patch.billingContractProvider, 'stripe');

  assert.equal(reconcileCalls.length, 1);
  assert.equal(reconcileCalls[0].tenantId, 'tenant_1');
  assert.equal(reconcileCalls[0].stripeProviderKey, 'stripe');
  assert.equal(enforcementCalls.length, 1);
  assert.equal(enforcementCalls[0].tenantId, 'tenant_1');
});

test('applyStripeWebhookEventToTenant handles subscription updates and seat add-ons', async () => {
  const firestore = createTenantsFirestore();

  const tenantId = await applyStripeWebhookEventToTenant({
    firestore,
    event: {
      type: 'customer.subscription.updated',
      data: {
        object: {
          id: 'sub_123',
          customer: 'cus_123',
          metadata: {
            tenantId: 'tenant_sub',
            billingPlanKey: 'enterprise',
          },
        },
      },
    },
    stripeClient: {
      subscriptions: {
        retrieve: async () => ({
          id: 'sub_123',
          customer: 'cus_123',
          metadata: {
            tenantId: 'tenant_sub',
            billingPlanKey: 'enterprise',
          },
        }),
      },
    },
    normalizeBillingPlanKey: normalizePlanKey,
    resolveTenantIdFromStripeReferences: async () => 'tenant_sub',
    readStripeSubscriptionLineItems: () => [
      { priceId: 'price_base', quantity: 1 },
      { priceId: 'price_addon', quantity: 3 },
    ],
    resolveStripePlanMappingByPriceId: async ({ stripePriceId }) => {
      if (stripePriceId === 'price_base') {
        return {
          mappingType: 'base',
          billingPlanKey: 'enterprise',
          stripePriceId: 'price_base',
          includedSeats: 2,
          seatAddonPlanKey: '',
        };
      }
      if (stripePriceId === 'price_addon') {
        return {
          mappingType: 'overage',
          overageMetric: 'extra_usuario',
          linkedBasePlanKey: 'enterprise',
          billingPlanKey: 'enterprise_addon',
          stripeUnitAmount: 700,
        };
      }
      return null;
    },
    buildTenantPatchFromStripeSubscription: () => ({
      billingStatus: 'active',
      billingUpdatedAt: '2026-01-01T00:00:00.000Z',
    }),
    reconcileTenantStripePeriodIfMissing: async () => {},
    reconcileTenantBillingState: async () => {},
    enforceTenantSeatAllowanceForTenant: async () => {},
    billingProviderStripe: 'stripe',
  });

  assert.equal(tenantId, 'tenant_sub');
  assert.equal(firestore.writes.length, 1);
  const patch = firestore.writes[0].patch;
  assert.equal(patch.billingSeatsIncluded, 2);
  assert.equal(patch.billingSeatsAddon, 3);
  assert.equal(patch.billingSeatAddonPlanKey, 'enterprise_addon');
  assert.equal(patch.billingSeatAddonUnitPriceCents, 700);
  assert.equal(patch.stripePriceId, 'price_base');
});

test('applyStripeWebhookEventToTenant handles invoice payment failure and unknown events', async () => {
  const firestore = createTenantsFirestore();

  const invoiceTenantId = await applyStripeWebhookEventToTenant({
    firestore,
    event: {
      type: 'invoice.payment_failed',
      data: {
        object: {
          id: 'in_1',
          customer: 'cus_inv',
          subscription: 'sub_inv',
          payment_intent: 'pi_1',
          metadata: {
            tenantId: 'tenant_inv',
          },
        },
      },
    },
    stripeClient: {},
    normalizeBillingPlanKey: normalizePlanKey,
    resolveTenantIdFromStripeReferences: async () => 'tenant_inv',
    readStripeSubscriptionLineItems: () => [],
    resolveStripePlanMappingByPriceId: async () => null,
    buildTenantPatchFromStripeSubscription: () => ({}),
    reconcileTenantStripePeriodIfMissing: async () => {},
    reconcileTenantBillingState: async () => {},
    enforceTenantSeatAllowanceForTenant: async () => {
      throw new Error('seat_enforcement_failed');
    },
    billingProviderStripe: 'stripe',
  });

  assert.equal(invoiceTenantId, 'tenant_inv');
  assert.equal(firestore.writes.length, 1);
  const patch = firestore.writes[0].patch;
  assert.equal(patch.billingStatus, 'past_due');
  assert.ok(patch.billingPastDueSinceAt);
  assert.equal(patch.stripeInvoiceId, 'in_1');
  assert.equal(patch.stripePaymentIntentId, 'pi_1');

  const unknown = await applyStripeWebhookEventToTenant({
    firestore,
    event: { type: 'unknown.event', data: { object: {} } },
    stripeClient: {},
    normalizeBillingPlanKey: normalizePlanKey,
    resolveTenantIdFromStripeReferences: async () => 'tenant_any',
    readStripeSubscriptionLineItems: () => [],
    resolveStripePlanMappingByPriceId: async () => null,
    buildTenantPatchFromStripeSubscription: () => ({}),
    reconcileTenantStripePeriodIfMissing: async () => {},
    reconcileTenantBillingState: async () => {},
    enforceTenantSeatAllowanceForTenant: async () => {},
    billingProviderStripe: 'stripe',
  });
  assert.equal(unknown, '');
});

test('applyStripeWebhookEventToTenant ignores stale subscription events after manual clear_plan_link', async () => {
  const firestore = createTenantsFirestore({
    initialTenants: {
      tenant_unlinked: {
        billingStatus: 'no_plan',
        billingLastManualAction: 'clear_plan_link',
        billingProvider: '',
        stripeCustomerId: '',
        stripeSubscriptionId: '',
      },
    },
  });

  let reconcileCalled = false;
  let enforcementCalled = false;

  const tenantId = await applyStripeWebhookEventToTenant({
    firestore,
    event: {
      type: 'customer.subscription.deleted',
      data: {
        object: {
          id: 'sub_old_1',
          customer: 'cus_old_1',
          metadata: {
            tenantId: 'tenant_unlinked',
            billingPlanKey: 'legacy',
          },
        },
      },
    },
    stripeClient: {
      subscriptions: {
        retrieve: async () => ({
          id: 'sub_old_1',
          customer: 'cus_old_1',
          status: 'canceled',
          metadata: {
            tenantId: 'tenant_unlinked',
            billingPlanKey: 'legacy',
          },
          items: { data: [] },
        }),
      },
    },
    normalizeBillingPlanKey: normalizePlanKey,
    resolveTenantIdFromStripeReferences: async () => 'tenant_unlinked',
    readStripeSubscriptionLineItems: () => [],
    resolveStripePlanMappingByPriceId: async () => null,
    buildTenantPatchFromStripeSubscription: () => ({
      billingStatus: 'canceled',
      billingCurrentPeriodStartAt: '2026-01-01T00:00:00.000Z',
      billingCurrentPeriodEndAt: '2026-02-01T00:00:00.000Z',
    }),
    reconcileTenantStripePeriodIfMissing: async () => {
      reconcileCalled = true;
    },
    reconcileTenantBillingState: async () => {},
    enforceTenantSeatAllowanceForTenant: async () => {
      enforcementCalled = true;
    },
    billingProviderStripe: 'stripe',
  });

  assert.equal(tenantId, 'tenant_unlinked');
  assert.equal(firestore.writes.length, 0);
  assert.equal(reconcileCalled, false);
  assert.equal(enforcementCalled, false);
  assert.equal(
    firestore.docs.get('tenant_unlinked')?.billingStatus,
    'no_plan',
  );
});
