const test = require('node:test');
const assert = require('node:assert/strict');

const {
  applyAsaasSeatAddonDeltaToActiveSubscription,
} = require('../../src/billing/asaas_seat_addon_helpers');
const {
  loadAsaasInternalPlanMapping,
  resolveAsaasSeatAddonMappingForBasePlan,
} = require('../../src/billing/asaas_plan_mapping_helpers');
const {
  normalizeBillingPlanKey,
  readNonNegativeInteger,
} = require('../../src/billing/shared_helpers');

function createFirestore({ plans = {} } = {}) {
  const planEntries = Object.entries(plans).map(([id, data]) => ({ id, data }));
  const tenantWrites = [];

  function buildPlansQuery(filters) {
    return {
      where(field, op, value) {
        return buildPlansQuery([...filters, { field, op, value }]);
      },
      limit() {
        return this;
      },
      async get() {
        const docs = planEntries
          .filter((entry) =>
            filters.every((filter) => {
              if (filter.op !== '==') {
                return false;
              }
              return entry.data?.[filter.field] === filter.value;
            }),
          )
          .map((entry) => ({
            id: entry.id,
            data: () => ({ ...entry.data }),
          }));
        return { docs, empty: docs.length === 0 };
      },
    };
  }

  return {
    firestore: {
      collection(name) {
        if (name === 'billing_integrations') {
          return {
            doc(id) {
              assert.equal(id, 'asaas');
              return {
                collection(child) {
                  assert.equal(child, 'internal_plan_catalog');
                  return {
                    doc(docId) {
                      return {
                        async get() {
                          const entry = planEntries.find((item) => item.id === docId);
                          return {
                            exists: Boolean(entry),
                            id: docId,
                            data: () => (entry ? { ...entry.data } : undefined),
                          };
                        },
                      };
                    },
                    where(field, op, value) {
                      return buildPlansQuery([{ field, op, value }]);
                    },
                  };
                },
              };
            },
          };
        }

        if (name === 'tenants') {
          return {
            doc(id) {
              return {
                async set(data, options) {
                  tenantWrites.push({ id, data: { ...data }, options });
                },
              };
            },
          };
        }

        throw new Error(`Unexpected collection ${name}`);
      },
    },
    tenantWrites,
  };
}

test('applyAsaasSeatAddonDeltaToActiveSubscription validates missing active subscription', async () => {
  const { firestore } = createFirestore();

  const result = await applyAsaasSeatAddonDeltaToActiveSubscription({
    firestore,
    asaasRuntime: {
      asaasApiKey: 'k',
      asaasApiBaseUrl: 'https://api.example',
    },
    tenantId: 'tenant_1',
    tenantData: {
      billingPlanKey: 'enterprise_plus',
    },
    billingPlanKey: 'enterprise_plus',
    addonSeatsDelta: 1,
    actorUid: 'uid_1',
    normalizeBillingPlanKey,
    readNonNegativeInteger,
    loadAsaasInternalPlanMapping,
    resolveAsaasSeatAddonMappingForBasePlan,
    fetchAsaasApiJson: async () => ({}),
  });

  assert.equal(result.applied, false);
  assert.equal(result.error, 'missing_active_subscription');
  assert.equal(result.status, 409);
});

test('applyAsaasSeatAddonDeltaToActiveSubscription recalculates recurring value and persists tenant fields', async () => {
  const { firestore, tenantWrites } = createFirestore({
    plans: {
      enterprise_plus: {
        billingPlanKey: 'enterprise_plus',
        mappingType: 'base',
        amountCents: 2590,
        currency: 'brl',
        interval: 'month',
        intervalCount: 1,
        includedSeats: 3,
        seatAddonPlanKey: 'enterprise_plus_extra_usuario',
        active: true,
      },
      enterprise_plus_extra_usuario: {
        billingPlanKey: 'enterprise_plus_extra_usuario',
        mappingType: 'overage',
        overageMetric: 'extra_usuario',
        linkedBasePlanKey: 'enterprise_plus',
        amountCents: 500,
        currency: 'brl',
        interval: 'month',
        intervalCount: 1,
        active: true,
      },
    },
  });

  const apiCalls = [];
  const result = await applyAsaasSeatAddonDeltaToActiveSubscription({
    firestore,
    asaasRuntime: {
      asaasApiKey: 'k',
      asaasApiBaseUrl: 'https://api.example',
    },
    tenantId: 'tenant_2',
    tenantData: {
      billingPlanKey: 'enterprise_plus',
      asaasSubscriptionId: 'sub_asaas_2',
      billingSeatsAddon: 2,
    },
    billingPlanKey: 'enterprise_plus',
    addonSeatsDelta: 2,
    actorUid: 'uid_2',
    normalizeBillingPlanKey,
    readNonNegativeInteger,
    loadAsaasInternalPlanMapping,
    resolveAsaasSeatAddonMappingForBasePlan,
    fetchAsaasApiJson: async (input) => {
      apiCalls.push(input);
      if (String(input.method).toUpperCase() === 'GET') {
        return {
          id: 'sub_asaas_2',
          cycle: 'MONTHLY',
          nextDueDate: '2026-12-01',
          description: 'Plano Enterprise Plus',
        };
      }
      return {
        id: 'sub_asaas_2',
        status: 'ACTIVE',
      };
    },
  });

  assert.equal(result.applied, true);
  assert.equal(result.status, 200);
  assert.equal(result.billingPlanKey, 'enterprise_plus');
  assert.equal(result.previousAddonSeats, 2);
  assert.equal(result.currentAddonSeats, 4);
  assert.equal(result.asaasSubscriptionValue, 45.9);
  assert.equal(apiCalls.length, 2);
  assert.equal(String(apiCalls[0].method).toUpperCase(), 'GET');
  assert.equal(String(apiCalls[1].method).toUpperCase(), 'PUT');
  assert.equal(apiCalls[1].body.value, 45.9);

  assert.equal(tenantWrites.length, 1);
  assert.equal(tenantWrites[0].id, 'tenant_2');
  assert.equal(tenantWrites[0].data.billingSeatsAddon, 4);
  assert.equal(tenantWrites[0].data.billingSeatsIncluded, 3);
  assert.equal(tenantWrites[0].data.billingSeatAddonPlanKey, 'enterprise_plus_extra_usuario');
  assert.equal(tenantWrites[0].data.billingSeatAddonUnitPriceCents, 500);
  assert.equal(tenantWrites[0].data.billingContractProvider, 'asaas');
});
