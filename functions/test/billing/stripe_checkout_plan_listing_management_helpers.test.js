const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeListStripeCheckoutPlansAction,
} = require('../../src/billing/stripe_checkout_plan_listing_management_helpers');

function createPlanMappingsQuery(docs) {
  return {
    where() {
      return this;
    },
    limit() {
      return this;
    },
    async get() {
      return {
        docs: docs.map((doc) => ({
          id: doc.id,
          data: () => ({ ...doc.data }),
        })),
      };
    },
  };
}

function createFirestore({
  tenantExists = true,
  tenantData = {},
  baseMappings = [],
  overageMappings = [],
} = {}) {
  return {
    firestore: {
      collection(name) {
        if (name === 'tenants') {
          return {
            doc() {
              return {
                async get() {
                  return {
                    exists: tenantExists,
                    data: () => (tenantExists ? { ...tenantData } : undefined),
                  };
                },
              };
            },
          };
        }

        if (name === 'billing_integrations') {
          return {
            doc(docId) {
              if (docId !== 'stripe') {
                throw new Error(`Unexpected billing integration doc ${docId}`);
              }
              return {
                collection(subName) {
                  if (subName !== 'plan_mappings') {
                    throw new Error(`Unexpected subcollection ${subName}`);
                  }
                  let mappingType = '';
                  return {
                    where(field, _op, value) {
                      if (field === 'mappingType') {
                        mappingType = String(value ?? '').trim();
                      }
                      return this;
                    },
                    limit() {
                      return this;
                    },
                    async get() {
                      if (mappingType === 'base') {
                        return createPlanMappingsQuery(baseMappings).get();
                      }
                      if (mappingType === 'overage') {
                        return createPlanMappingsQuery(overageMappings).get();
                      }
                      return { docs: [] };
                    },
                  };
                },
              };
            },
          };
        }

        throw new Error(`Unexpected collection ${name}`);
      },
    },
  };
}

function normalizeBillingPlanKey(value) {
  return String(value ?? '').trim().toLowerCase();
}

test('executeListStripeCheckoutPlansAction returns permission error when actor is not allowed', async () => {
  const { firestore } = createFirestore({ tenantExists: true, tenantData: {} });

  const result = await executeListStripeCheckoutPlansAction({
    firestore,
    tenantId: 'tenant_1',
    authContext: { uid: 'uid_1' },
    assertTenantBillingActorPermission: async () => ({
      allowed: false,
      status: 403,
      error: 'owner_required',
      message: 'not allowed',
    }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    resolveStripePlanPrefixByWorkspaceType: () => '',
    buildStripePlanMappingFromDocData: () => null,
    formatPlanAmountLabel: () => '',
    normalizeBillingPlanKey,
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'owner_required');
});

test('executeListStripeCheckoutPlansAction returns provider disabled when stripe is inactive', async () => {
  const { firestore } = createFirestore({ tenantExists: true, tenantData: {} });

  const result = await executeListStripeCheckoutPlansAction({
    firestore,
    tenantId: 'tenant_2',
    authContext: { uid: 'uid_2' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveStripePlanPrefixByWorkspaceType: () => '',
    buildStripePlanMappingFromDocData: () => null,
    formatPlanAmountLabel: () => '',
    normalizeBillingPlanKey,
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'provider_disabled');
});

test('executeListStripeCheckoutPlansAction returns tenant not found', async () => {
  const { firestore } = createFirestore({ tenantExists: false });

  const result = await executeListStripeCheckoutPlansAction({
    firestore,
    tenantId: 'tenant_3',
    authContext: { uid: 'uid_3' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    resolveStripePlanPrefixByWorkspaceType: () => '',
    buildStripePlanMappingFromDocData: () => null,
    formatPlanAmountLabel: () => '',
    normalizeBillingPlanKey,
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 404);
  assert.equal(result.body.error, 'tenant_not_found');
});

test('executeListStripeCheckoutPlansAction filters by workspace prefix, links addon and sorts plans', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: { workspaceType: 'brand_owner_workspace' },
    baseMappings: [
      {
        id: 'm2',
        data: {
          billingPlanKey: 'brand_pro',
          stripePriceId: 'price_pro',
          planDisplayName: 'Plano Z',
          stripeProductName: 'Produto Z',
          includedSeats: 5,
          stripeCurrency: 'brl',
          stripeRecurringInterval: 'month',
          stripeRecurringIntervalCount: 1,
          stripeUnitAmount: 19990,
        },
      },
      {
        id: 'm1',
        data: {
          billingPlanKey: 'brand_start',
          stripePriceId: 'price_start',
          planDisplayName: 'Plano A',
          stripeProductName: 'Produto A',
          includedSeats: 2,
          stripeCurrency: 'brl',
          stripeRecurringInterval: 'month',
          stripeRecurringIntervalCount: 1,
          stripeUnitAmount: 9990,
        },
      },
      {
        id: 'm3',
        data: {
          billingPlanKey: 'revenda_other',
          stripePriceId: 'price_other',
          planDisplayName: 'Plano Fora',
        },
      },
    ],
    overageMappings: [
      {
        id: 'ov1',
        data: {
          mappingType: 'overage',
          overageMetric: 'extra_usuario',
          billingPlanKey: 'brand_pro_addon',
          linkedBasePlanKey: 'brand_pro',
          stripeUnitAmount: 2990,
          planDisplayAmount: 'R$ 29,90',
          stripeCurrency: 'brl',
          stripeRecurringInterval: 'month',
          stripeRecurringIntervalCount: 1,
        },
      },
      {
        id: 'ov2',
        data: {
          mappingType: 'overage',
          overageMetric: 'other_metric',
          billingPlanKey: 'brand_ignore_addon',
        },
      },
    ],
  });

  const result = await executeListStripeCheckoutPlansAction({
    firestore,
    tenantId: 'tenant_4',
    authContext: { uid: 'uid_4' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe', 'asaas'] }),
    resolveStripePlanPrefixByWorkspaceType: () => 'brand',
    buildStripePlanMappingFromDocData: (data, id) => ({
      ...data,
      billingPlanKey: normalizeBillingPlanKey(data.billingPlanKey ?? id),
      mappingType: String(data.mappingType ?? '').trim(),
      overageMetric: String(data.overageMetric ?? '').trim(),
      linkedBasePlanKey: normalizeBillingPlanKey(data.linkedBasePlanKey),
    }),
    formatPlanAmountLabel: ({ amountMinorUnits }) => `fmt:${amountMinorUnits}`,
    normalizeBillingPlanKey,
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.tenantId, 'tenant_4');
  assert.equal(result.body.workspaceType, 'brand_owner_workspace');
  assert.equal(result.body.requiredPrefix, 'brand');
  assert.equal(result.body.plans.length, 2);
  assert.equal(result.body.plans[0].billingPlanKey, 'brand_start');
  assert.equal(result.body.plans[1].billingPlanKey, 'brand_pro');
  assert.equal(result.body.plans[1].seatAddonPlanKey, 'brand_pro_addon');
  assert.equal(result.body.plans[1].seatAddonUnitPriceCents, 2990);
  assert.equal(result.body.plans[1].seatAddonDisplayAmount, 'R$ 29,90');
});
