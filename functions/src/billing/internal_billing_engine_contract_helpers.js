const BILLING_ENGINE_COLLECTIONS = Object.freeze({
  planCatalog: 'billing_plan_catalog',
  tenantContracts: 'tenant_billing_contracts',
  tenantSeatChanges: 'tenant_billing_seat_changes',
  quotes: 'billing_quotes',
  providerRefs: 'billing_provider_refs',
  operations: 'tenant_billing_operations',
});

const BILLING_ENGINE_PROVIDERS = Object.freeze({
  stripe: 'stripe',
  asaas: 'asaas',
});

const BILLING_ENGINE_OPERATION_TYPES = new Set([
  'create_quote',
  'open_checkout',
  'change_seats',
  'change_plan',
  'cancel',
]);

const BILLING_ENGINE_OPERATION_STATUSES = new Set([
  'received',
  'applied',
  'failed',
  'pending_reconcile',
]);

const BILLING_ENGINE_QUOTE_STATUSES = new Set([
  'open',
  'used',
  'expired',
  'canceled',
]);

const BILLING_ENGINE_SEAT_CHANGE_TYPES = new Set([
  'add',
  'remove',
  'support_override',
]);

const BILLING_ENGINE_IMPACT_TYPES = new Set([
  'next_cycle',
  'immediate_invoice',
  'credit_next_cycle',
]);

const BILLING_ENGINE_CYCLES = new Set(['month', 'year']);

function normalizeContractToken(rawValue) {
  return String(rawValue ?? '').trim().toLowerCase();
}

function normalizeProviderKey(rawValue) {
  const normalized = normalizeContractToken(rawValue);
  if (
    normalized !== BILLING_ENGINE_PROVIDERS.stripe &&
    normalized !== BILLING_ENGINE_PROVIDERS.asaas
  ) {
    return '';
  }
  return normalized;
}

function normalizeOperationType(rawValue) {
  const normalized = normalizeContractToken(rawValue);
  return BILLING_ENGINE_OPERATION_TYPES.has(normalized) ? normalized : '';
}

function normalizeOperationStatus(rawValue) {
  const normalized = normalizeContractToken(rawValue);
  return BILLING_ENGINE_OPERATION_STATUSES.has(normalized) ? normalized : '';
}

function normalizeQuoteStatus(rawValue) {
  const normalized = normalizeContractToken(rawValue);
  return BILLING_ENGINE_QUOTE_STATUSES.has(normalized) ? normalized : '';
}

function normalizeSeatChangeType(rawValue) {
  const normalized = normalizeContractToken(rawValue);
  return BILLING_ENGINE_SEAT_CHANGE_TYPES.has(normalized) ? normalized : '';
}

function normalizeImpactType(rawValue) {
  const normalized = normalizeContractToken(rawValue);
  return BILLING_ENGINE_IMPACT_TYPES.has(normalized) ? normalized : '';
}

function normalizeBillingCycle(rawValue) {
  const normalized = normalizeContractToken(rawValue);
  return BILLING_ENGINE_CYCLES.has(normalized) ? normalized : '';
}

function normalizeOperationId(rawValue, maxLength = 128) {
  const cleaned = String(rawValue ?? '')
    .trim()
    .replace(/[^A-Za-z0-9:_-]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '');

  if (!cleaned) {
    return '';
  }

  const limit = Number.isFinite(Number(maxLength))
    ? Math.max(16, Math.floor(Number(maxLength)))
    : 128;

  return cleaned.length <= limit ? cleaned : cleaned.slice(0, limit);
}

function isValidOperationId(rawValue) {
  const normalized = String(rawValue ?? '').trim();
  return /^[A-Za-z0-9:_-]{16,128}$/.test(normalized);
}

function buildTenantScopedOperationKey({ tenantId, operationId }) {
  const tenantToken = normalizeOperationId(tenantId, 96);
  const operationToken = normalizeOperationId(operationId, 128);
  if (!tenantToken || !operationToken) {
    return '';
  }
  return `${tenantToken}__${operationToken}`;
}

function readContractVersion(rawValue, fallback = 0) {
  const asNumber = Number(rawValue);
  if (!Number.isFinite(asNumber)) {
    return Math.max(0, Math.floor(Number(fallback) || 0));
  }
  return Math.max(0, Math.floor(asNumber));
}

module.exports = {
  BILLING_ENGINE_COLLECTIONS,
  BILLING_ENGINE_PROVIDERS,
  normalizeProviderKey,
  normalizeOperationType,
  normalizeOperationStatus,
  normalizeQuoteStatus,
  normalizeSeatChangeType,
  normalizeImpactType,
  normalizeBillingCycle,
  normalizeOperationId,
  isValidOperationId,
  buildTenantScopedOperationKey,
  readContractVersion,
};
