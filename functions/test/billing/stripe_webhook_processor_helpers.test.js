const test = require('node:test');
const assert = require('node:assert/strict');

const {
  processStripeWebhookEvent,
} = require('../../src/billing/stripe_webhook_processor_helpers');

function createWebhookEventsFirestore(initialDocs = {}) {
  const docs = new Map(Object.entries(initialDocs));

  function mergeData(current, patch) {
    return {
      ...(current || {}),
      ...(patch || {}),
    };
  }

  function eventRef(eventId) {
    return {
      id: eventId,
      async set(data, options) {
        const current = docs.get(eventId) || null;
        if (options?.merge) {
          docs.set(eventId, mergeData(current, data));
        } else {
          docs.set(eventId, { ...(data || {}) });
        }
      },
    };
  }

  return {
    docs,
    collection(name) {
      assert.equal(name, 'billing_webhook_events');
      return {
        doc(eventId) {
          return eventRef(eventId);
        },
      };
    },
    async runTransaction(callback) {
      const tx = {
        async get(ref) {
          const data = docs.get(ref.id);
          return {
            exists: data !== undefined,
            data: () => (data ? { ...data } : undefined),
          };
        },
        set(ref, data, options) {
          const current = docs.get(ref.id) || null;
          if (options?.merge) {
            docs.set(ref.id, mergeData(current, data));
          } else {
            docs.set(ref.id, { ...(data || {}) });
          }
        },
      };

      await callback(tx);
    },
  };
}

test('processStripeWebhookEvent requires event type', async () => {
  const firestore = createWebhookEventsFirestore();

  await assert.rejects(
    () =>
      processStripeWebhookEvent({
        firestore,
        event: {},
        enabledEvents: [],
        defaultEnabledEvents: ['invoice.paid'],
        stripeClient: {},
        applyStripeWebhookEventToTenant: async () => '',
      }),
    /Webhook Stripe sem event.type/,
  );
});

test('processStripeWebhookEvent ignores disabled event types', async () => {
  const firestore = createWebhookEventsFirestore();

  const result = await processStripeWebhookEvent({
    firestore,
    event: { id: 'evt_1', type: 'invoice.finalized' },
    enabledEvents: ['invoice.paid'],
    defaultEnabledEvents: ['invoice.paid'],
    stripeClient: {},
    applyStripeWebhookEventToTenant: async () => {
      throw new Error('should_not_apply');
    },
  });

  assert.deepEqual(result, {
    ignored: true,
    duplicate: false,
    tenantId: '',
  });
});

test('processStripeWebhookEvent returns duplicate when already successful', async () => {
  const firestore = createWebhookEventsFirestore({
    evt_dup: {
      processingStatus: 'success',
    },
  });

  const result = await processStripeWebhookEvent({
    firestore,
    event: { id: 'evt_dup', type: 'invoice.paid' },
    enabledEvents: ['invoice.paid'],
    defaultEnabledEvents: ['invoice.paid'],
    stripeClient: {},
    applyStripeWebhookEventToTenant: async () => {
      throw new Error('should_not_apply');
    },
  });

  assert.deepEqual(result, {
    ignored: false,
    duplicate: true,
    tenantId: '',
  });
});

test('processStripeWebhookEvent processes and marks success', async () => {
  const firestore = createWebhookEventsFirestore();

  const result = await processStripeWebhookEvent({
    firestore,
    event: { id: 'evt_ok', type: 'invoice.paid' },
    enabledEvents: ['invoice.paid'],
    defaultEnabledEvents: ['invoice.paid'],
    stripeClient: { marker: true },
    applyStripeWebhookEventToTenant: async ({ event }) => {
      assert.equal(event.id, 'evt_ok');
      return 'tenant_1';
    },
  });

  assert.deepEqual(result, {
    ignored: false,
    duplicate: false,
    tenantId: 'tenant_1',
  });

  const saved = firestore.docs.get('evt_ok');
  assert.equal(saved.provider, 'stripe');
  assert.equal(saved.processingStatus, 'success');
  assert.equal(saved.tenantId, 'tenant_1');
  assert.equal(saved.errorMessage, '');
});

test('processStripeWebhookEvent marks error and rethrows on apply failure', async () => {
  const firestore = createWebhookEventsFirestore();

  await assert.rejects(
    () =>
      processStripeWebhookEvent({
        firestore,
        event: { id: 'evt_err', type: 'invoice.paid' },
        enabledEvents: ['invoice.paid'],
        defaultEnabledEvents: ['invoice.paid'],
        stripeClient: {},
        applyStripeWebhookEventToTenant: async () => {
          throw new Error('apply_failed');
        },
      }),
    /apply_failed/,
  );

  const saved = firestore.docs.get('evt_err');
  assert.equal(saved.provider, 'stripe');
  assert.equal(saved.processingStatus, 'error');
  assert.equal(saved.errorMessage, 'apply_failed');
});
