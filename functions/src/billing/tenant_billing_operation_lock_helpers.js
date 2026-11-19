const {
  normalizeOperationId,
} = require('./internal_billing_engine_contract_helpers');

const DEFAULT_BILLING_OPERATION_LOCK_LEASE_MS = 90 * 1000;

function normalizeBillingOperationLockLeaseMs(rawValue) {
  const parsed = Number(rawValue);
  if (!Number.isFinite(parsed)) {
    return DEFAULT_BILLING_OPERATION_LOCK_LEASE_MS;
  }

  const floored = Math.floor(parsed);
  if (floored < 15 * 1000) {
    return 15 * 1000;
  }
  if (floored > 15 * 60 * 1000) {
    return 15 * 60 * 1000;
  }
  return floored;
}

function normalizeBillingOperationLockToken(rawValue) {
  return normalizeOperationId(rawValue, 128);
}

function buildBillingOperationLockWindow({ nowDate, lockLeaseMs }) {
  const baseDate = nowDate instanceof Date ? nowDate : new Date();
  const lease = normalizeBillingOperationLockLeaseMs(lockLeaseMs);
  const acquiredAt = baseDate.toISOString();
  const expiresAt = new Date(baseDate.getTime() + lease).toISOString();
  return {
    lease,
    acquiredAt,
    expiresAt,
  };
}

function isBillingOperationLockExpired({ lockExpiresAt, nowDate }) {
  const now = nowDate instanceof Date ? nowDate : new Date();
  const expiresRaw = String(lockExpiresAt ?? '').trim();
  if (!expiresRaw) {
    return true;
  }

  const expiresMs = new Date(expiresRaw).getTime();
  if (!Number.isFinite(expiresMs)) {
    return true;
  }

  return expiresMs <= now.getTime();
}

module.exports = {
  DEFAULT_BILLING_OPERATION_LOCK_LEASE_MS,
  buildBillingOperationLockWindow,
  isBillingOperationLockExpired,
  normalizeBillingOperationLockLeaseMs,
  normalizeBillingOperationLockToken,
};
