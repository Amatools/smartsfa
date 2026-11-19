const crypto = require('node:crypto');

const {
  normalizeOperationId,
} = require('./internal_billing_engine_contract_helpers');

function normalizeToken(rawValue, maxLength = 256) {
  const trimmed = String(rawValue ?? '').trim();
  if (!trimmed) {
    return '';
  }

  return trimmed.length <= maxLength ? trimmed : trimmed.slice(0, maxLength);
}

function normalizeNonNegativeInteger(rawValue) {
  const parsed = Number(rawValue);
  if (!Number.isFinite(parsed)) {
    return 0;
  }
  return Math.max(0, Math.floor(parsed));
}

function stableSerialize(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableSerialize(item)).join(',')}]`;
  }

  if (value && typeof value === 'object') {
    const entries = Object.entries(value)
      .filter(([, v]) => v !== undefined)
      .sort(([a], [b]) => a.localeCompare(b));

    return `{${entries
      .map(([key, entryValue]) => `${JSON.stringify(key)}:${stableSerialize(entryValue)}`)
      .join(',')}}`;
  }

  return JSON.stringify(value);
}

function readCheckoutOperationIdFromPayload(payload) {
  return normalizeOperationId(
    payload?.operationId ?? payload?.idempotencyKey,
    128,
  );
}

function buildCheckoutOperationRequestHash({
  tenantId,
  payload,
  billingProvider,
  providerSelectionSource,
  hasLinkedContract,
}) {
  const projection = {
    tenantId: normalizeOperationId(tenantId, 96),
    billingProvider: normalizeToken(billingProvider, 48).toLowerCase(),
    providerSelectionSource: normalizeToken(providerSelectionSource, 96).toLowerCase(),
    hasLinkedContract: Boolean(hasLinkedContract),
    billingPlanKey: normalizeToken(payload?.billingPlanKey, 128).toLowerCase(),
    addonSeats: normalizeNonNegativeInteger(payload?.addonSeats),
    successUrl: normalizeToken(payload?.successUrl, 1024),
    cancelUrl: normalizeToken(payload?.cancelUrl, 1024),
    callbackUrl: normalizeToken(payload?.callbackUrl, 1024),
    returnUrl: normalizeToken(payload?.returnUrl, 1024),
    quoteId: normalizeToken(payload?.quoteId, 128),
  };

  const serialized = stableSerialize(projection);
  return crypto.createHash('sha256').update(serialized).digest('hex');
}

function buildSeatAddonOperationRequestHash({
  tenantId,
  billingPlanKey,
  addonSeatsDelta,
  payload,
  billingProvider,
  providerSelectionSource,
  hasLinkedContract,
}) {
  const projection = {
    tenantId: normalizeOperationId(tenantId, 96),
    billingProvider: normalizeToken(billingProvider, 48).toLowerCase(),
    providerSelectionSource: normalizeToken(providerSelectionSource, 96).toLowerCase(),
    hasLinkedContract: Boolean(hasLinkedContract),
    billingPlanKey: normalizeToken(billingPlanKey, 128).toLowerCase(),
    addonSeatsDelta: normalizeNonNegativeInteger(addonSeatsDelta),
    requestedProvider: normalizeToken(payload?.provider, 48).toLowerCase(),
    operationReason: normalizeToken(payload?.reason, 256),
  };

  const serialized = stableSerialize(projection);
  return crypto.createHash('sha256').update(serialized).digest('hex');
}

function buildQuoteOperationRequestHash({
  tenantId,
  payload,
  billingProvider,
  providerSelectionSource,
  hasLinkedContract,
}) {
  const projection = {
    tenantId: normalizeOperationId(tenantId, 96),
    billingProvider: normalizeToken(billingProvider, 48).toLowerCase(),
    providerSelectionSource: normalizeToken(providerSelectionSource, 96).toLowerCase(),
    hasLinkedContract: Boolean(hasLinkedContract),
    billingPlanKey: normalizeToken(payload?.billingPlanKey, 128).toLowerCase(),
    addonSeats: normalizeNonNegativeInteger(payload?.addonSeats),
    quoteTtlMinutes: normalizeNonNegativeInteger(payload?.quoteTtlMinutes),
    requestedProvider: normalizeToken(payload?.provider, 48).toLowerCase(),
  };

  const serialized = stableSerialize(projection);
  return crypto.createHash('sha256').update(serialized).digest('hex');
}

module.exports = {
  buildSeatAddonOperationRequestHash,
  buildCheckoutOperationRequestHash,
  buildQuoteOperationRequestHash,
  readCheckoutOperationIdFromPayload,
};
