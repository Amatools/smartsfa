const {
  normalizeOperationStatus,
} = require('./internal_billing_engine_contract_helpers');

const BILLING_OPERATION_TERMINAL_STATUSES = new Set([
  'applied',
  'failed',
  'pending_reconcile',
]);

const BILLING_OPERATION_ALLOWED_TRANSITIONS = new Map([
  ['received', new Set(['received', 'applied', 'failed', 'pending_reconcile'])],
  ['failed', new Set(['failed', 'pending_reconcile', 'applied'])],
  ['pending_reconcile', new Set(['pending_reconcile', 'applied', 'failed'])],
  ['applied', new Set(['applied'])],
]);

function isTerminalBillingOperationStatus(rawStatus) {
  const normalized = normalizeOperationStatus(rawStatus);
  return BILLING_OPERATION_TERMINAL_STATUSES.has(normalized);
}

function canTransitionBillingOperationStatus({ currentStatus, nextStatus }) {
  const current = normalizeOperationStatus(currentStatus);
  const next = normalizeOperationStatus(nextStatus);
  if (!current || !next) {
    return false;
  }
  const allowed = BILLING_OPERATION_ALLOWED_TRANSITIONS.get(current);
  if (!allowed) {
    return false;
  }
  return allowed.has(next);
}

function assertBillingOperationStatusTransition({ currentStatus, nextStatus }) {
  if (
    !canTransitionBillingOperationStatus({
      currentStatus,
      nextStatus,
    })
  ) {
    throw new Error('billing_operation_status_transition_invalid');
  }
}

module.exports = {
  assertBillingOperationStatusTransition,
  canTransitionBillingOperationStatus,
  isTerminalBillingOperationStatus,
};
