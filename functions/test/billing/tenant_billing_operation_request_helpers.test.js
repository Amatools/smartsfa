const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildSeatAddonOperationRequestHash,
  buildCheckoutOperationRequestHash,
  buildQuoteOperationRequestHash,
  readCheckoutOperationIdFromPayload,
} = require('../../src/billing/tenant_billing_operation_request_helpers');

test('readCheckoutOperationIdFromPayload accepts operationId and idempotencyKey aliases', () => {
  assert.equal(
    readCheckoutOperationIdFromPayload({ operationId: ' op_1234567890abcdef ' }),
    'op_1234567890abcdef',
  );

  assert.equal(
    readCheckoutOperationIdFromPayload({ idempotencyKey: 'idem_1234567890abcdef' }),
    'idem_1234567890abcdef',
  );

  assert.equal(readCheckoutOperationIdFromPayload({}), '');
});

test('buildCheckoutOperationRequestHash is stable for equivalent payload and sensitive to key fields', () => {
  const base = {
    tenantId: 'tenant_1',
    payload: {
      billingPlanKey: 'enterprise',
      addonSeats: 2,
      successUrl: 'https://app.example/success',
      cancelUrl: 'https://app.example/cancel',
    },
    billingProvider: 'asaas',
    providerSelectionSource: 'payload_provider',
    hasLinkedContract: false,
  };

  const hashA = buildCheckoutOperationRequestHash(base);
  const hashB = buildCheckoutOperationRequestHash({
    ...base,
    payload: {
      cancelUrl: 'https://app.example/cancel',
      successUrl: 'https://app.example/success',
      addonSeats: 2,
      billingPlanKey: 'enterprise',
    },
  });

  assert.equal(hashA, hashB);

  const changedSeatsHash = buildCheckoutOperationRequestHash({
    ...base,
    payload: {
      ...base.payload,
      addonSeats: 3,
    },
  });

  assert.notEqual(hashA, changedSeatsHash);
});

test('buildSeatAddonOperationRequestHash is stable and reacts to delta changes', () => {
  const base = {
    tenantId: 'tenant_1',
    billingPlanKey: 'enterprise',
    addonSeatsDelta: 2,
    payload: {
      provider: 'stripe',
      reason: 'upgrade',
    },
    billingProvider: 'stripe',
    providerSelectionSource: 'existing_contract',
    hasLinkedContract: true,
  };

  const hashA = buildSeatAddonOperationRequestHash(base);
  const hashB = buildSeatAddonOperationRequestHash({
    ...base,
    payload: {
      reason: 'upgrade',
      provider: 'stripe',
    },
  });
  assert.equal(hashA, hashB);

  const changedHash = buildSeatAddonOperationRequestHash({
    ...base,
    addonSeatsDelta: 4,
  });
  assert.notEqual(hashA, changedHash);
});

test('buildQuoteOperationRequestHash is stable and reacts to addon seats changes', () => {
  const base = {
    tenantId: 'tenant_1',
    payload: {
      billingPlanKey: 'enterprise_plus',
      addonSeats: 2,
      quoteTtlMinutes: 30,
      provider: 'asaas',
    },
    billingProvider: 'asaas',
    providerSelectionSource: 'payload_provider',
    hasLinkedContract: false,
  };

  const hashA = buildQuoteOperationRequestHash(base);
  const hashB = buildQuoteOperationRequestHash({
    ...base,
    payload: {
      provider: 'asaas',
      quoteTtlMinutes: 30,
      addonSeats: 2,
      billingPlanKey: 'enterprise_plus',
    },
  });
  assert.equal(hashA, hashB);

  const changedHash = buildQuoteOperationRequestHash({
    ...base,
    payload: {
      ...base.payload,
      addonSeats: 5,
    },
  });
  assert.notEqual(hashA, changedHash);
});
