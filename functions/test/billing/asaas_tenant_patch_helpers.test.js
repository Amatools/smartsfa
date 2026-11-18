const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildTenantPatchFromAsaasEvent,
  mapAsaasEventToBillingStatus,
} = require('../../src/billing/asaas_tenant_patch_helpers');

test('mapAsaasEventToBillingStatus maps payment and subscription events', () => {
  assert.equal(
    mapAsaasEventToBillingStatus({ eventType: 'PAYMENT_RECEIVED' }),
    'active',
  );
  assert.equal(
    mapAsaasEventToBillingStatus({ eventType: 'PAYMENT_OVERDUE' }),
    'past_due',
  );
  assert.equal(
    mapAsaasEventToBillingStatus({
      eventType: 'SUBSCRIPTION_UPDATED',
      eventPayload: { subscription: { status: 'ACTIVE' } },
    }),
    'active',
  );
  assert.equal(
    mapAsaasEventToBillingStatus({ eventType: 'SUBSCRIPTION_DELETED' }),
    'canceled',
  );
});

test('mapAsaasEventToBillingStatus keeps active tenants unchanged on checkout expiry', () => {
  assert.equal(
    mapAsaasEventToBillingStatus({
      eventType: 'CHECKOUT_EXPIRED',
      currentBillingStatus: 'active',
    }),
    '',
  );
  assert.equal(
    mapAsaasEventToBillingStatus({
      eventType: 'CHECKOUT_EXPIRED',
      currentBillingStatus: 'no_plan',
    }),
    'no_plan',
  );
});

test('buildTenantPatchFromAsaasEvent builds normalized tenant patch', () => {
  const patch = buildTenantPatchFromAsaasEvent({
    eventPayload: {
      id: 'evt_1',
      dateCreated: '2026-01-10',
      payment: {
        id: 'pay_1',
        customer: 'cus_asaas',
        subscription: 'sub_asaas',
        billingType: 'CREDIT_CARD',
        externalReference: 'tenantId=tenant_1&billingPlanKey=enterprise',
        dueDate: '2026-02-10',
        dateCreated: '2026-01-10',
      },
      subscription: {
        cycle: 'MONTHLY',
      },
      invoice: {
        number: 'NF-123',
        status: 'AUTHORIZED',
      },
    },
    eventType: 'PAYMENT_OVERDUE',
    currentTenantData: {
      billingStatus: 'active',
      billingCurrentPeriodStartAt: '',
      billingPastDueSinceAt: '',
    },
    webhookEnvironment: 'sandbox',
  });

  assert.equal(patch.billingProvider, 'asaas');
  assert.equal(patch.asaasLastEventId, 'evt_1');
  assert.equal(patch.asaasLastEventType, 'PAYMENT_OVERDUE');
  assert.equal(patch.asaasWebhookEnvironment, 'sandbox');
  assert.equal(patch.asaasCustomerId, 'cus_asaas');
  assert.equal(patch.asaasSubscriptionId, 'sub_asaas');
  assert.equal(patch.asaasPaymentId, 'pay_1');
  assert.equal(patch.asaasBillingType, 'CREDIT_CARD');
  assert.equal(patch.asaasInvoiceNumber, 'NF-123');
  assert.equal(patch.asaasInvoiceStatus, 'AUTHORIZED');
  assert.equal(patch.billingPlanKey, 'enterprise');
  assert.equal(patch.billingCycle, 'month');
  assert.equal(patch.billingStatus, 'past_due');
  assert.equal(patch.billingAccountState, 'past_due');
  assert.ok(patch.billingPastDueSinceAt);
  assert.ok(patch.billingCurrentPeriodStartAt);
  assert.equal(patch.billingCurrentPeriodEndAt, '2026-02-10T00:00:00.000Z');
  assert.ok(patch.billingContractLinkedAt);
  assert.equal(patch.billingContractProvider, 'asaas');
}
);