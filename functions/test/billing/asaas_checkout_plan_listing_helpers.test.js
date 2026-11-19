const test = require('node:test');
const assert = require('node:assert/strict');

const {
  listAsaasCheckoutPlansForTenant,
} = require('../../src/billing/asaas_checkout_plan_listing_helpers');

function createPlanMappingsFirestore(planMappingsByDocId) {
  const docs = Object.entries(planMappingsByDocId).map(([id, data]) => ({ id, data }));

  function buildQuery(filters) {
    const query = {
      where(field, op, value) {
        return buildQuery([...filters, { field, op, value }]);
      },
      limit() {
        return query;
      },
      async get() {
        const queryDocs = docs
          .filter((entry) => {
            return filters.every((filter) => {
              if (filter.op !== '==') {
                return false;
              }
              return entry.data?.[filter.field] === filter.value;
            });
          })
          .map((entry) => ({
            id: entry.id,
            data: () => ({ ...entry.data }),
          }));
        return { docs: queryDocs };
      },
    };
    return query;
  }

  return {
    collection(name) {
      assert.equal(name, 'billing_integrations');
      return {
        doc(id) {
          assert.equal(id, 'asaas');
          return {
            collection(child) {
              assert.equal(child, 'internal_plan_catalog');
              return buildQuery([]);
            },
          };
        },
      };
    },
  };
}

test('listAsaasCheckoutPlansForTenant filters by workspace prefix and links seat addon', async () => {
  const firestore = createPlanMappingsFirestore({
    enterprise_plus: {
      active: true,
      mappingType: 'base',
      billingPlanKey: 'enterprise_plus',
      amountCents: 2590,
      currency: 'brl',
      interval: 'month',
      intervalCount: 1,
      includedSeats: 3,
      planDisplayName: 'Enterprise Plus',
      planDisplayAmount: 'R$ 25,90 / mes',
    },
    individual_starter: {
      active: true,
      mappingType: 'base',
      billingPlanKey: 'individual_starter',
      amountCents: 990,
      currency: 'brl',
      interval: 'month',
      intervalCount: 1,
    },
    enterprise_plus_extra_usuario: {
      active: true,
      mappingType: 'overage',
      overageMetric: 'extra_usuario',
      billingPlanKey: 'enterprise_plus_extra_usuario',
      linkedBasePlanKey: 'enterprise_plus',
      amountCents: 500,
      currency: 'brl',
      interval: 'month',
      intervalCount: 1,
      planDisplayAmount: 'R$ 5,00 / usuario',
    },
  });

  const listed = await listAsaasCheckoutPlansForTenant({
    firestore,
    tenantData: {
      workspaceType: 'brand_owner_workspace',
    },
  });

  assert.equal(listed.workspaceType, 'brand_owner_workspace');
  assert.equal(listed.requiredPrefix, 'enterprise');
  assert.equal(listed.plans.length, 1);

  const plan = listed.plans[0];
  assert.equal(plan.billingPlanKey, 'enterprise_plus');
  assert.equal(plan.seatAddonPlanKey, 'enterprise_plus_extra_usuario');
  assert.equal(plan.seatAddonUnitPriceCents, 500);
  assert.equal(plan.seatAddonDisplayAmount, 'R$ 5,00 / usuario');
  assert.equal(plan.asaasChargeType, 'RECURRENT');
  assert.deepEqual(plan.asaasBillingTypes, ['PIX', 'CREDIT_CARD']);
});

test('listAsaasCheckoutPlansForTenant sorts plans by display name', async () => {
  const firestore = createPlanMappingsFirestore({
    enterprise_zeta: {
      active: true,
      mappingType: 'base',
      billingPlanKey: 'enterprise_zeta',
      amountCents: 3000,
      currency: 'brl',
      interval: 'month',
      intervalCount: 1,
      planDisplayName: 'Zeta Plan',
    },
    enterprise_alpha: {
      active: true,
      mappingType: 'base',
      billingPlanKey: 'enterprise_alpha',
      amountCents: 2000,
      currency: 'brl',
      interval: 'month',
      intervalCount: 1,
      planDisplayName: 'Alpha Plan',
    },
  });

  const listed = await listAsaasCheckoutPlansForTenant({
    firestore,
    tenantData: {
      workspaceType: 'brand_owner_workspace',
    },
  });

  assert.deepEqual(
    listed.plans.map((item) => item.billingPlanKey),
    ['enterprise_alpha', 'enterprise_zeta'],
  );
});
