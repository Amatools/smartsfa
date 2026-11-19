const test = require('node:test');
const assert = require('node:assert/strict');

const {
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
} = require('../../src/billing/internal_billing_engine_contract_helpers');

test('billing engine collections expose expected names', () => {
  assert.deepEqual(BILLING_ENGINE_COLLECTIONS, {
    planCatalog: 'billing_plan_catalog',
    tenantContracts: 'tenant_billing_contracts',
    tenantSeatChanges: 'tenant_billing_seat_changes',
    quotes: 'billing_quotes',
    providerRefs: 'billing_provider_refs',
    operations: 'tenant_billing_operations',
  });
});

test('normalizeProviderKey accepts known providers', () => {
  assert.equal(normalizeProviderKey(' Stripe '), BILLING_ENGINE_PROVIDERS.stripe);
  assert.equal(normalizeProviderKey('asaas'), BILLING_ENGINE_PROVIDERS.asaas);
  assert.equal(normalizeProviderKey('other'), '');
});

test('normalizeOperationType and status normalize known tokens', () => {
  assert.equal(normalizeOperationType('CREATE_QUOTE'), 'create_quote');
  assert.equal(normalizeOperationType('unknown_action'), '');

  assert.equal(normalizeOperationStatus('pending_reconcile'), 'pending_reconcile');
  assert.equal(normalizeOperationStatus('received'), 'received');
  assert.equal(normalizeOperationStatus('unexpected'), '');
});

test('normalize quote, seat change, impact and cycle values', () => {
  assert.equal(normalizeQuoteStatus(' USED '), 'used');
  assert.equal(normalizeQuoteStatus('draft'), '');

  assert.equal(normalizeSeatChangeType('support_override'), 'support_override');
  assert.equal(normalizeSeatChangeType('swap'), '');

  assert.equal(normalizeImpactType('immediate_invoice'), 'immediate_invoice');
  assert.equal(normalizeImpactType('none'), '');

  assert.equal(normalizeBillingCycle('MONTH'), 'month');
  assert.equal(normalizeBillingCycle('weekly'), '');
});

test('normalizeOperationId sanitizes value with max length cap', () => {
  const normalized = normalizeOperationId('  op id!@# test  ');
  assert.equal(normalized, 'op_id_test');

  const long = 'a'.repeat(300);
  assert.equal(normalizeOperationId(long, 80).length, 80);
  assert.equal(normalizeOperationId(null), '');
});

test('isValidOperationId enforces expected format and length', () => {
  assert.equal(isValidOperationId('op_1234567890abcd'), true);
  assert.equal(isValidOperationId('short_id'), false);
  assert.equal(isValidOperationId('op with spaces 1234567890'), false);
});

test('buildTenantScopedOperationKey joins sanitized tenant and operation ids', () => {
  const key = buildTenantScopedOperationKey({
    tenantId: 'tenant alpha',
    operationId: 'op::1234567890abcdef',
  });
  assert.equal(key, 'tenant_alpha__op::1234567890abcdef');

  assert.equal(
    buildTenantScopedOperationKey({ tenantId: '', operationId: 'op_1234567890abcd' }),
    '',
  );
});

test('readContractVersion returns non-negative integers with fallback', () => {
  assert.equal(readContractVersion(10), 10);
  assert.equal(readContractVersion('7'), 7);
  assert.equal(readContractVersion('7.9'), 7);
  assert.equal(readContractVersion(-4), 0);
  assert.equal(readContractVersion('x', 3), 3);
});
