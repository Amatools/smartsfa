const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createAsaasBillingQuote,
} = require('../../src/billing/asaas_quote_helpers');
const {
  normalizeBillingPlanKey,
  readNonNegativeInteger,
} = require('../../src/billing/shared_helpers');

function createFirestoreForQuotes() {
  const quoteWrites = [];
  let quoteSeq = 0;

  return {
    quoteWrites,
    firestore: {
      collection(name) {
        assert.equal(name, 'billing_quotes');
        return {
          doc(docId) {
            const id = String(docId ?? '').trim() || `quote_${++quoteSeq}`;
            return {
              id,
              async set(data) {
                quoteWrites.push({ id, data: { ...data } });
              },
            };
          },
        };
      },
    },
  };
}

test('createAsaasBillingQuote validates required plan key', async () => {
  const { firestore } = createFirestoreForQuotes();
  const result = await createAsaasBillingQuote({
    firestore,
    tenantId: 'tenant_1',
    tenantData: {},
    payload: {},
    providerSelection: {
      source: 'payload_provider',
      hasLinkedContract: false,
    },
    billingProviderAsaas: 'asaas',
    normalizeBillingPlanKey,
    readNonNegativeInteger,
    loadAsaasInternalPlanMapping: async () => null,
    resolveAsaasSeatAddonMappingForBasePlan: async () => null,
  });

  assert.equal(result.ok, false);
  assert.equal(result.status, 400);
  assert.equal(result.error, 'invalid_payload');
});

test('createAsaasBillingQuote calculates total and persists quote', async () => {
  const { firestore, quoteWrites } = createFirestoreForQuotes();

  const result = await createAsaasBillingQuote({
    firestore,
    tenantId: 'tenant_2',
    tenantData: { workspaceType: 'brand_owner_workspace' },
    payload: {
      billingPlanKey: 'enterprise_plus',
      addonSeats: 2,
      quoteTtlMinutes: 45,
      operationId: 'op_1234567890abcdef',
    },
    providerSelection: {
      source: 'payload_provider',
      hasLinkedContract: false,
    },
    billingProviderAsaas: 'asaas',
    normalizeBillingPlanKey,
    readNonNegativeInteger,
    loadAsaasInternalPlanMapping: async () => ({
      billingPlanKey: 'enterprise_plus',
      mappingType: 'base',
      amountCents: 2590,
      currency: 'brl',
      interval: 'month',
      intervalCount: 1,
      includedSeats: 3,
      active: true,
    }),
    resolveAsaasSeatAddonMappingForBasePlan: async () => ({
      billingPlanKey: 'enterprise_plus_extra_usuario',
      mappingType: 'overage',
      overageMetric: 'extra_usuario',
      amountCents: 500,
      active: true,
    }),
  });

  assert.equal(result.ok, true);
  assert.equal(result.status, 200);
  assert.equal(result.body.billingPlanKey, 'enterprise_plus');
  assert.equal(result.body.baseAmountCents, 2590);
  assert.equal(result.body.extraSeatUnitAmountCents, 500);
  assert.equal(result.body.addonSeats, 2);
  assert.equal(result.body.totalAmountCents, 3590);
  assert.equal(result.body.totalAmount, 35.9);
  assert.equal(result.body.seatAddonPlanKey, 'enterprise_plus_extra_usuario');
  assert.equal(quoteWrites.length, 1);
  assert.equal(quoteWrites[0].data.status, 'open');
  assert.equal(quoteWrites[0].data.totalAmountCents, 3590);
});

test('createAsaasBillingQuote rejects addon seats when addon mapping is missing', async () => {
  const { firestore } = createFirestoreForQuotes();

  const result = await createAsaasBillingQuote({
    firestore,
    tenantId: 'tenant_3',
    tenantData: {},
    payload: {
      billingPlanKey: 'enterprise_plus',
      addonSeats: 1,
    },
    providerSelection: {
      source: 'payload_provider',
      hasLinkedContract: false,
    },
    billingProviderAsaas: 'asaas',
    normalizeBillingPlanKey,
    readNonNegativeInteger,
    loadAsaasInternalPlanMapping: async () => ({
      billingPlanKey: 'enterprise_plus',
      mappingType: 'base',
      amountCents: 2590,
      currency: 'brl',
      interval: 'month',
      intervalCount: 1,
      includedSeats: 3,
      active: true,
    }),
    resolveAsaasSeatAddonMappingForBasePlan: async () => null,
  });

  assert.equal(result.ok, false);
  assert.equal(result.status, 409);
  assert.equal(result.error, 'invalid_seat_addon_mapping');
});