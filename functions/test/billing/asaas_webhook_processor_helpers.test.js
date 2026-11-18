const test = require('node:test');
const assert = require('node:assert/strict');

const {
  processAsaasWebhookEvent,
} = require('../../src/billing/asaas_webhook_processor_helpers');

test('processAsaasWebhookEvent requires event type', async () => {
  await assert.rejects(
    () =>
      processAsaasWebhookEvent({
        firestore: {},
        event: {},
        enabledEvents: [],
        defaultEnabledEvents: ['PAYMENT_RECEIVED'],
        asaasRuntime: {},
        applyAsaasWebhookEventToTenant: async () => ({
          tenantId: '',
          billingStatus: '',
        }),
      }),
    /Webhook Asaas sem event/,
  );
});

test('processAsaasWebhookEvent ignores events not enabled', async () => {
  const result = await processAsaasWebhookEvent({
    firestore: {},
    event: { event: 'PAYMENT_OVERDUE' },
    enabledEvents: ['PAYMENT_RECEIVED'],
    defaultEnabledEvents: ['PAYMENT_RECEIVED'],
    asaasRuntime: {},
    applyAsaasWebhookEventToTenant: async () => {
      throw new Error('should_not_apply');
    },
  });

  assert.deepEqual(result, {
    ignored: true,
    duplicate: false,
    tenantId: '',
    billingStatus: '',
  });
});

test('processAsaasWebhookEvent applies enabled event and returns tenant info', async () => {
  const result = await processAsaasWebhookEvent({
    firestore: { marker: true },
    event: { event: 'PAYMENT_RECEIVED', id: 'evt_1' },
    enabledEvents: [],
    defaultEnabledEvents: ['PAYMENT_RECEIVED'],
    asaasRuntime: { environment: 'sandbox' },
    applyAsaasWebhookEventToTenant: async ({ eventPayload, eventType }) => {
      assert.equal(eventPayload.id, 'evt_1');
      assert.equal(eventType, 'PAYMENT_RECEIVED');
      return {
        tenantId: 'tenant_1',
        billingStatus: 'active',
      };
    },
  });

  assert.deepEqual(result, {
    ignored: false,
    duplicate: false,
    tenantId: 'tenant_1',
    billingStatus: 'active',
  });
});
