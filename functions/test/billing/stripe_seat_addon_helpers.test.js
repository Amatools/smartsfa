const test = require('node:test');
const assert = require('node:assert/strict');

const {
  applyStripeSeatAddonDeltaToActiveSubscription,
} = require('../../src/billing/stripe_seat_addon_helpers');

function normalizePlanKey(value) {
  return String(value ?? '').trim().toLowerCase();
}

function readInt(value, fallback) {
  const num = Number(value);
  if (!Number.isFinite(num)) {
    return fallback;
  }
  return Math.max(0, Math.floor(num));
}

function sanitize(value) {
  return String(value ?? '').trim();
}

test('applyStripeSeatAddonDeltaToActiveSubscription validates tenant and delta', async () => {
  const baseInput = {
    firestore: {},
    stripeClient: {
      subscriptions: {
        retrieve: async () => ({}),
        update: async () => ({}),
      },
    },
    tenantData: {},
    actorUid: 'uid_1',
    normalizeBillingPlanKey: normalizePlanKey,
    readNonNegativeInteger: readInt,
    resolveStripePlanMappingByPriceId: async () => null,
    loadStripePlanMapping: async () => null,
    resolveStripeSeatAddonMappingForBasePlan: async () => null,
    sanitizeStripeMetadataValue: sanitize,
    reconcileTenantStripeState: async () => {},
  };

  const invalidTenant = await applyStripeSeatAddonDeltaToActiveSubscription({
    ...baseInput,
    tenantId: '',
    addonSeatsDelta: 1,
  });
  assert.equal(invalidTenant.error, 'invalid_tenant_id');

  const invalidDelta = await applyStripeSeatAddonDeltaToActiveSubscription({
    ...baseInput,
    tenantId: 'tenant_1',
    addonSeatsDelta: 0,
  });
  assert.equal(invalidDelta.error, 'invalid_addon_seats_delta');
});

test('applyStripeSeatAddonDeltaToActiveSubscription detects plan mismatch', async () => {
  const result = await applyStripeSeatAddonDeltaToActiveSubscription({
    firestore: {},
    stripeClient: {
      subscriptions: {
        retrieve: async () => ({
          status: 'active',
          items: {
            data: [{ price: { id: 'price_base' }, quantity: 1 }],
          },
        }),
        update: async () => ({}),
      },
    },
    tenantId: 'tenant_2',
    tenantData: {
      stripeSubscriptionId: 'sub_2',
      billingPlanKey: 'enterprise',
    },
    billingPlanKey: 'pro',
    addonSeatsDelta: 1,
    actorUid: 'uid_2',
    normalizeBillingPlanKey: normalizePlanKey,
    readNonNegativeInteger: readInt,
    resolveStripePlanMappingByPriceId: async () => ({
      mappingType: 'base',
      billingPlanKey: 'enterprise',
    }),
    loadStripePlanMapping: async () => null,
    resolveStripeSeatAddonMappingForBasePlan: async () => null,
    sanitizeStripeMetadataValue: sanitize,
    reconcileTenantStripeState: async () => {},
  });

  assert.equal(result.error, 'plan_mismatch_with_active_subscription');
});

test('applyStripeSeatAddonDeltaToActiveSubscription updates addon quantity and reconciles tenant', async () => {
  const reconcileCalls = [];
  const updatedPayloads = [];

  const result = await applyStripeSeatAddonDeltaToActiveSubscription({
    firestore: {},
    stripeClient: {
      subscriptions: {
        retrieve: async () => ({
          status: 'active',
          metadata: { tenantId: 'tenant_3' },
          items: {
            data: [
              { id: 'si_base', price: { id: 'price_base' }, quantity: 1 },
              { id: 'si_addon', price: { id: 'price_addon' }, quantity: 2 },
            ],
          },
        }),
        update: async (_id, payload) => {
          updatedPayloads.push(payload);
          return {
            latest_invoice: {
              id: 'in_1',
              status: 'open',
              hosted_invoice_url: 'https://stripe.example/in_1',
            },
          };
        },
      },
    },
    tenantId: 'tenant_3',
    tenantData: {
      stripeSubscriptionId: 'sub_3',
      billingPlanKey: 'enterprise',
    },
    billingPlanKey: 'enterprise',
    addonSeatsDelta: 3,
    actorUid: 'uid_3',
    normalizeBillingPlanKey: normalizePlanKey,
    readNonNegativeInteger: readInt,
    resolveStripePlanMappingByPriceId: async ({ stripePriceId }) => {
      if (stripePriceId === 'price_base') {
        return {
          mappingType: 'base',
          billingPlanKey: 'enterprise',
        };
      }
      if (stripePriceId === 'price_addon') {
        return {
          mappingType: 'overage',
          overageMetric: 'extra_usuario',
          billingPlanKey: 'enterprise-seat-addon',
        };
      }
      return null;
    },
    loadStripePlanMapping: async () => null,
    resolveStripeSeatAddonMappingForBasePlan: async () => ({
      mappingType: 'overage',
      overageMetric: 'extra_usuario',
      stripePriceId: 'price_addon',
    }),
    sanitizeStripeMetadataValue: sanitize,
    reconcileTenantStripeState: async (input) => {
      reconcileCalls.push(input);
    },
  });

  assert.equal(result.applied, true);
  assert.equal(result.previousAddonSeats, 2);
  assert.equal(result.currentAddonSeats, 5);
  assert.equal(result.invoiceId, 'in_1');
  assert.equal(updatedPayloads.length, 1);
  assert.equal(updatedPayloads[0].items[0].id, 'si_addon');
  assert.equal(updatedPayloads[0].items[0].quantity, 5);
  assert.equal(reconcileCalls.length, 1);
  assert.equal(reconcileCalls[0].tenantId, 'tenant_3');
});
