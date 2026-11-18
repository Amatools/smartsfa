const test = require('node:test');
const assert = require('node:assert/strict');

const {
  applyTenantBillingActionToStripe,
} = require('../../src/billing/stripe_actions_helpers');

function sanitize(value) {
  return String(value ?? '').trim();
}

test('applyTenantBillingActionToStripe returns no_stripe_reference when tenant has no ids', async () => {
  const result = await applyTenantBillingActionToStripe({
    stripeClient: {
      customers: { update: async () => {} },
      subscriptions: { update: async () => {}, list: async () => ({ data: [], has_more: false }), cancel: async () => {} },
    },
    tenantId: 'tenant_1',
    tenantData: {},
    action: 'suspend_billing',
    reason: 'manual',
    actorUid: 'uid_1',
    sanitizeStripeMetadataValue: sanitize,
  });

  assert.equal(result.applied, false);
  assert.equal(result.action, 'no_stripe_reference');
});

test('applyTenantBillingActionToStripe updates customer metadata when subscription is absent', async () => {
  const customerUpdates = [];
  const result = await applyTenantBillingActionToStripe({
    stripeClient: {
      customers: {
        update: async (id, payload) => {
          customerUpdates.push({ id, payload });
        },
      },
      subscriptions: {
        update: async () => {},
        list: async () => ({ data: [], has_more: false }),
        cancel: async () => {},
      },
    },
    tenantId: 'tenant_2',
    tenantData: {
      stripeCustomerId: 'cus_2',
    },
    action: 'grant_30_days',
    reason: 'migration',
    actorUid: 'uid_admin',
    sanitizeStripeMetadataValue: sanitize,
  });

  assert.equal(customerUpdates.length, 1);
  assert.equal(customerUpdates[0].id, 'cus_2');
  assert.equal(customerUpdates[0].payload.metadata.smartsfaGraceDays, '30');
  assert.equal(result.applied, true);
  assert.equal(result.action, 'customer_metadata_updated');
});

test('applyTenantBillingActionToStripe handles suspend and normalize actions', async () => {
  const subscriptionUpdates = [];
  const stripeClient = {
    customers: {
      update: async () => {},
    },
    subscriptions: {
      update: async (id, payload) => {
        subscriptionUpdates.push({ id, payload });
      },
      list: async () => ({ data: [], has_more: false }),
      cancel: async () => {},
    },
  };

  const suspendResult = await applyTenantBillingActionToStripe({
    stripeClient,
    tenantId: 'tenant_3',
    tenantData: {
      stripeSubscriptionId: 'sub_3',
    },
    action: 'suspend_billing',
    reason: 'manual',
    actorUid: 'uid_admin',
    sanitizeStripeMetadataValue: sanitize,
  });

  const normalizeResult = await applyTenantBillingActionToStripe({
    stripeClient,
    tenantId: 'tenant_3',
    tenantData: {
      stripeSubscriptionId: 'sub_3',
    },
    action: 'normalize_billing',
    reason: 'manual',
    actorUid: 'uid_admin',
    sanitizeStripeMetadataValue: sanitize,
  });

  assert.equal(suspendResult.action, 'subscription_paused_collection_void');
  assert.equal(normalizeResult.action, 'subscription_resumed_collection');
  assert.equal(subscriptionUpdates.length, 2);
  assert.deepEqual(subscriptionUpdates[0].payload.pause_collection, { behavior: 'void' });
  assert.equal(subscriptionUpdates[1].payload.pause_collection, null);
});

test('applyTenantBillingActionToStripe handles clear_plan_link and ignores missing subscriptions', async () => {
  const canceled = [];

  const stripeClient = {
    customers: {
      update: async () => {},
    },
    subscriptions: {
      update: async () => {},
      list: async () => ({
        data: [
          { id: 'sub_4', status: 'active' },
          { id: 'sub_canceled', status: 'canceled' },
          { id: 'sub_5', status: 'trialing' },
        ],
        has_more: false,
      }),
      cancel: async (id) => {
        if (id === 'sub_5') {
          const err = new Error('No such subscription');
          err.code = 'resource_missing';
          throw err;
        }
        canceled.push(id);
      },
    },
  };

  const result = await applyTenantBillingActionToStripe({
    stripeClient,
    tenantId: 'tenant_4',
    tenantData: {
      stripeCustomerId: 'cus_4',
      stripeSubscriptionId: 'sub_legacy',
    },
    action: 'clear_plan_link',
    reason: 'tenant_cleanup',
    actorUid: 'uid_admin',
    sanitizeStripeMetadataValue: sanitize,
  });

  assert.equal(result.applied, true);
  assert.equal(result.action, 'subscriptions_canceled_plan_unlinked');
  assert.ok(canceled.includes('sub_legacy'));
  assert.ok(canceled.includes('sub_4'));
});

test('applyTenantBillingActionToStripe defaults to metadata update for unknown action', async () => {
  const updates = [];

  const result = await applyTenantBillingActionToStripe({
    stripeClient: {
      customers: { update: async () => {} },
      subscriptions: {
        update: async (id, payload) => {
          updates.push({ id, payload });
        },
        list: async () => ({ data: [], has_more: false }),
        cancel: async () => {},
      },
    },
    tenantId: 'tenant_5',
    tenantData: {
      stripeSubscriptionId: 'sub_5',
    },
    action: 'custom_action',
    reason: 'manual',
    actorUid: 'uid_admin',
    sanitizeStripeMetadataValue: sanitize,
  });

  assert.equal(result.applied, true);
  assert.equal(result.action, 'subscription_metadata_updated');
  assert.equal(updates.length, 1);
  assert.equal(updates[0].id, 'sub_5');
});
