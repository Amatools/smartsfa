const test = require('node:test');
const assert = require('node:assert/strict');

const {
  canTransitionBillingOperationStatus,
  isTerminalBillingOperationStatus,
  assertBillingOperationStatusTransition,
} = require('../../src/billing/tenant_billing_operation_status_helpers');

test('isTerminalBillingOperationStatus recognizes terminal states', () => {
  assert.equal(isTerminalBillingOperationStatus('applied'), true);
  assert.equal(isTerminalBillingOperationStatus('failed'), true);
  assert.equal(isTerminalBillingOperationStatus('pending_reconcile'), true);
  assert.equal(isTerminalBillingOperationStatus('received'), false);
  assert.equal(isTerminalBillingOperationStatus('unknown'), false);
});

test('canTransitionBillingOperationStatus validates allowed transitions', () => {
  assert.equal(
    canTransitionBillingOperationStatus({
      currentStatus: 'received',
      nextStatus: 'applied',
    }),
    true,
  );

  assert.equal(
    canTransitionBillingOperationStatus({
      currentStatus: 'pending_reconcile',
      nextStatus: 'applied',
    }),
    true,
  );

  assert.equal(
    canTransitionBillingOperationStatus({
      currentStatus: 'applied',
      nextStatus: 'failed',
    }),
    false,
  );
});

test('assertBillingOperationStatusTransition throws for invalid transition', () => {
  assert.throws(
    () =>
      assertBillingOperationStatusTransition({
        currentStatus: 'applied',
        nextStatus: 'failed',
      }),
    /billing_operation_status_transition_invalid/,
  );
});
