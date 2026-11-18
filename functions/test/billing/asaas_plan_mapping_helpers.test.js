const test = require('node:test');
const assert = require('node:assert/strict');

const {
  resolveAsaasPlanMapping,
} = require('../../src/billing/asaas_plan_mapping_helpers');

function createPlanMappingsFirestore(planMappingsByDocId) {
  const docs = { ...planMappingsByDocId };

  function buildDocRef(docId) {
    return {
      async get() {
        const data = docs[docId];
        return {
          exists: data !== undefined,
          data: () => (data ? { ...data } : undefined),
          id: docId,
        };
      },
    };
  }

  function buildQueryRef(filters) {
    return {
      where(field, op, value) {
        return buildQueryRef([...filters, { field, op, value }]);
      },
      limit() {
        return {
          async get() {
            const queryDocs = Object.entries(docs)
              .filter(([, data]) => {
                return filters.every((filter) => {
                  if (filter.op !== '==') {
                    return false;
                  }
                  return data?.[filter.field] === filter.value;
                });
              })
              .map(([id, data]) => ({
                id,
                data: () => ({ ...data }),
              }));
            return { docs: queryDocs };
          },
        };
      },
      async get() {
        const queryDocs = Object.entries(docs)
          .filter(([, data]) => {
            return filters.every((filter) => {
              if (filter.op !== '==') {
                return false;
              }
              return data?.[filter.field] === filter.value;
            });
          })
          .map(([id, data]) => ({
            id,
            data: () => ({ ...data }),
          }));
        return { docs: queryDocs };
      },
    };
  }

  return {
    collection(name) {
      assert.equal(name, 'billing_integrations');
      return {
        doc(id) {
          assert.equal(id, 'stripe');
          return {
            collection(child) {
              assert.equal(child, 'plan_mappings');
              return {
                doc: buildDocRef,
                where(field, op, value) {
                  return buildQueryRef([{ field, op, value }]);
                },
              };
            },
          };
        },
      };
    },
  };
}

test('resolveAsaasPlanMapping validates required plan key', async () => {
  const firestore = createPlanMappingsFirestore({});
  const result = await resolveAsaasPlanMapping({
    firestore,
    tenantData: {},
    billingPlanKey: '   ',
  });

  assert.equal(result.ok, false);
  assert.equal(result.error, 'invalid_plan_key');
  assert.equal(result.status, 400);
});

test('resolveAsaasPlanMapping returns not found when mapping does not exist', async () => {
  const firestore = createPlanMappingsFirestore({});
  const result = await resolveAsaasPlanMapping({
    firestore,
    tenantData: {},
    billingPlanKey: 'enterprise',
  });

  assert.equal(result.ok, false);
  assert.equal(result.error, 'plan_mapping_not_found');
  assert.equal(result.status, 404);
});

test('resolveAsaasPlanMapping rejects invalid amount and unsupported currency', async () => {
  const invalidAmountFirestore = createPlanMappingsFirestore({
    enterprise: {
      billingPlanKey: 'enterprise',
      stripePriceId: 'price_1',
      stripeUnitAmount: 0,
      stripeCurrency: 'brl',
      active: true,
    },
  });

  const invalidAmount = await resolveAsaasPlanMapping({
    firestore: invalidAmountFirestore,
    tenantData: {},
    billingPlanKey: 'enterprise',
  });
  assert.equal(invalidAmount.ok, false);
  assert.equal(invalidAmount.error, 'invalid_plan_amount');

  const unsupportedCurrencyFirestore = createPlanMappingsFirestore({
    enterprise: {
      billingPlanKey: 'enterprise',
      stripePriceId: 'price_1',
      stripeUnitAmount: 1990,
      stripeCurrency: 'usd',
      active: true,
    },
  });

  const unsupportedCurrency = await resolveAsaasPlanMapping({
    firestore: unsupportedCurrencyFirestore,
    tenantData: {},
    billingPlanKey: 'enterprise',
  });
  assert.equal(unsupportedCurrency.ok, false);
  assert.equal(unsupportedCurrency.error, 'unsupported_currency');
});

test('resolveAsaasPlanMapping returns normalized plan payload', async () => {
  const firestore = createPlanMappingsFirestore({
    enterprise: {
      billingPlanKey: 'enterprise',
      stripePriceId: 'price_1',
      stripeUnitAmount: 2590,
      stripeCurrency: 'brl',
      stripeRecurringInterval: 'month',
      stripeRecurringIntervalCount: 1,
      planDisplayName: 'Plano Enterprise Plus',
      planDisplayAmount: 'R$ 25,90 / mes',
      stripeProductName: 'Enterprise Product',
      active: true,
    },
  });

  const result = await resolveAsaasPlanMapping({
    firestore,
    tenantData: {
      displayName: 'ACME LTDA',
      email: 'BILLING@ACME.COM',
      cnpj: '12.345.678/0001-99',
    },
    billingPlanKey: ' Enterprise ',
  });

  assert.equal(result.ok, true);
  assert.equal(result.status, 200);
  assert.equal(result.mapping.billingPlanKey, 'enterprise');
  assert.equal(result.mapping.amount, 25.9);
  assert.equal(result.mapping.cycle, 'MONTHLY');
  assert.equal(result.mapping.itemName, 'Plano Enterprise Plus');
  assert.equal(result.mapping.itemDescription, 'R$ 25,90 / mes');
  assert.equal(result.mapping.customerData.name, 'ACME LTDA');
  assert.equal(result.mapping.customerData.email, 'billing@acme.com');
  assert.equal(result.mapping.customerData.cpfCnpj, '12345678000199');
});
