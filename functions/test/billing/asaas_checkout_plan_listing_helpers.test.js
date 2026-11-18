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
          assert.equal(id, 'stripe');
          return {
            collection(child) {
              assert.equal(child, 'plan_mappings');
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
      stripePriceId: 'price_ent_plus',
      stripeProductId: 'prod_ent_plus',
      stripeProductName: 'Enterprise Plus',
      stripeUnitAmount: 2590,
      stripeCurrency: 'brl',
      stripeRecurringInterval: 'month',
      stripeRecurringIntervalCount: 1,
      includedSeats: 3,
      planDisplayName: 'Enterprise Plus',
      planDisplayAmount: 'R$ 25,90 / mes',
    },
    individual_starter: {
      active: true,
      mappingType: 'base',
      billingPlanKey: 'individual_starter',
      stripePriceId: 'price_individual',
      stripeUnitAmount: 990,
      stripeCurrency: 'brl',
    },
    enterprise_plus_extra_usuario: {
      active: true,
      mappingType: 'overage',
      overageMetric: 'extra_usuario',
      billingPlanKey: 'enterprise_plus_extra_usuario',
      linkedBasePlanKey: 'enterprise_plus',
      stripePriceId: 'price_ent_overage',
      stripeUnitAmount: 500,
      stripeCurrency: 'brl',
      stripeRecurringInterval: 'month',
      stripeRecurringIntervalCount: 1,
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
      stripePriceId: 'price_zeta',
      stripeUnitAmount: 3000,
      stripeCurrency: 'brl',
      planDisplayName: 'Zeta Plan',
    },
    enterprise_alpha: {
      active: true,
      mappingType: 'base',
      billingPlanKey: 'enterprise_alpha',
      stripePriceId: 'price_alpha',
      stripeUnitAmount: 2000,
      stripeCurrency: 'brl',
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
