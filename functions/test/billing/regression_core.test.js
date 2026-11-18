const test = require('node:test');
const assert = require('node:assert/strict');

const stripeCatalogHelpers = require('../../src/billing/stripe_catalog_helpers');
const stripePlanMappings = require('../../src/billing/stripe_plan_mappings');
const webhookTenantResolution = require('../../src/billing/webhook_tenant_resolution');

function toQueryDocs(items) {
  return items.map((item) => ({
    id: item.id,
    data: () => item.data,
  }));
}

function createPlanMappingsFirestore(docsById) {
  const entries = Object.entries(docsById || {}).map(([id, data]) => ({ id, data }));

  function queryByField(field, value, limitValue) {
    const docs = entries
      .filter((entry) => String(entry.data?.[field] ?? '') === String(value ?? ''))
      .slice(0, limitValue || entries.length);
    return {
      docs: toQueryDocs(docs),
      empty: docs.length === 0,
    };
  }

  return {
    collection(name) {
      assert.equal(name, 'billing_integrations');
      return {
        doc(id) {
          assert.equal(id, 'stripe');
          return {
            collection(subName) {
              assert.equal(subName, 'plan_mappings');
              return {
                doc(mappingId) {
                  return {
                    async get() {
                      const found = docsById?.[mappingId];
                      return {
                        exists: Boolean(found),
                        data: () => found || {},
                      };
                    },
                  };
                },
                where(field, op, value) {
                  assert.equal(op, '==');
                  return {
                    limit(limitValue) {
                      return {
                        async get() {
                          return queryByField(field, value, limitValue);
                        },
                      };
                    },
                  };
                },
              };
            },
          };
        },
      };
    },
  };
}

function createTenantsFirestore(tenants) {
  const rows = Array.isArray(tenants) ? tenants : [];

  function findById(id) {
    const found = rows.find((row) => row.id === id);
    return found || null;
  }

  function queryByField(field, value, limitValue) {
    const filtered = rows
      .filter((row) => String(row.data?.[field] ?? '') === String(value ?? ''))
      .slice(0, limitValue || rows.length);
    return {
      docs: filtered.map((row) => ({ id: row.id, data: () => row.data || {} })),
      empty: filtered.length === 0,
    };
  }

  return {
    collection(name) {
      assert.equal(name, 'tenants');
      return {
        doc(id) {
          return {
            async get() {
              const found = findById(id);
              return {
                exists: Boolean(found),
                data: () => (found ? found.data || {} : {}),
              };
            },
          };
        },
        where(field, op, value) {
          assert.equal(op, '==');
          return {
            limit(limitValue) {
              return {
                async get() {
                  return queryByField(field, value, limitValue);
                },
              };
            },
          };
        },
      };
    },
  };
}

test('stripe catalog helpers build stable lookup key and metadata', () => {
  const key = stripeCatalogHelpers.buildStripeRecommendedLookupKey({
    billingPlanKey: 'Enterprise Plus',
    currency: 'BRL',
    recurringInterval: 'MONTH',
    recurringIntervalCount: 3,
  });

  assert.equal(key, 'smartsfa_enterprise_plus_brl_monthx3');

  const metadata = stripeCatalogHelpers.buildStripeCatalogPlanMetadata({
    billingPlanKey: 'Enterprise Plus',
    amountMinorUnits: 2590,
    currency: 'BRL',
    recurringInterval: 'Month',
    recurringIntervalCount: 1,
    lookupKey: key,
    actorUid: 'uid_123',
    actorEmail: 'owner@example.com',
  });

  assert.equal(metadata.source, 'smartsfa_admin_console');
  assert.equal(metadata.billingPlanKey, 'Enterprise Plus');
  assert.equal(metadata.billingPlanPrefix, 'enterprise');
  assert.equal(metadata.billingPlanSlug, 'plus');
  assert.equal(metadata.currency, 'brl');
  assert.equal(metadata.lookupKey, key);
});

test('stripe plan mappings loader and resolver behave deterministically', async () => {
  const firestore = createPlanMappingsFirestore({
    enterprise: {
      billingPlanKey: 'enterprise',
      stripePriceId: 'price_base_enterprise',
      stripeUnitAmount: 10000,
      stripeCurrency: 'brl',
      stripeRecurringInterval: 'month',
      stripeRecurringIntervalCount: 1,
      mappingType: 'base',
      includedSeats: 3,
      seatAddonPlanKey: 'enterprise_addon',
      active: true,
    },
    enterprise_addon: {
      billingPlanKey: 'enterprise_addon',
      stripePriceId: 'price_addon_enterprise',
      stripeUnitAmount: 1500,
      stripeCurrency: 'brl',
      stripeRecurringInterval: 'month',
      stripeRecurringIntervalCount: 1,
      mappingType: 'overage',
      overageMetric: 'extra_usuario',
      linkedBasePlanKey: 'enterprise',
      active: true,
    },
  });

  const base = await stripePlanMappings.loadStripePlanMapping({
    firestore,
    billingPlanKey: 'enterprise',
  });
  assert.equal(base.billingPlanKey, 'enterprise');
  assert.equal(base.mappingType, 'base');

  const byPrice = await stripePlanMappings.resolveStripePlanMappingByPriceId({
    firestore,
    stripePriceId: 'price_addon_enterprise',
  });
  assert.equal(byPrice.billingPlanKey, 'enterprise_addon');
  assert.equal(byPrice.mappingType, 'overage');

  const seatAddon = await stripePlanMappings.resolveStripeSeatAddonMappingForBasePlan({
    firestore,
    baseMapping: base,
  });
  assert.equal(seatAddon.billingPlanKey, 'enterprise_addon');
  assert.equal(seatAddon.overageMetric, 'extra_usuario');
});

test('stripe plan mappings fallback to linked base plan when seatAddonPlanKey is absent', async () => {
  const firestore = createPlanMappingsFirestore({
    any_base: {
      billingPlanKey: 'representacoes',
      stripePriceId: 'price_base_rep',
      stripeUnitAmount: 5000,
      stripeCurrency: 'brl',
      stripeRecurringInterval: 'month',
      stripeRecurringIntervalCount: 1,
      mappingType: 'base',
      includedSeats: 2,
      active: true,
    },
    addon_match: {
      billingPlanKey: 'representacoes_addon',
      stripePriceId: 'price_rep_addon',
      stripeUnitAmount: 1200,
      stripeCurrency: 'brl',
      stripeRecurringInterval: 'month',
      stripeRecurringIntervalCount: 1,
      mappingType: 'overage',
      overageMetric: 'extra_usuario',
      linkedBasePlanKey: 'representacoes',
      active: true,
    },
  });

  const seatAddon = await stripePlanMappings.resolveStripeSeatAddonMappingForBasePlan({
    firestore,
    baseMapping: { billingPlanKey: 'representacoes' },
  });

  assert.equal(seatAddon.billingPlanKey, 'representacoes_addon');
});

test('webhook tenant resolution: stripe explicit/subscription/customer', async () => {
  const firestore = createTenantsFirestore([
    { id: 't_sub', data: { stripeSubscriptionId: 'sub_123' } },
    { id: 't_cus', data: { stripeCustomerId: 'cus_123' } },
  ]);

  const explicit = await webhookTenantResolution.resolveTenantIdFromStripeReferences({
    firestore,
    explicitTenantId: 't_explicit',
    stripeCustomerId: 'cus_123',
    stripeSubscriptionId: 'sub_123',
  });
  assert.equal(explicit, 't_explicit');

  const bySub = await webhookTenantResolution.resolveTenantIdFromStripeReferences({
    firestore,
    explicitTenantId: '',
    stripeCustomerId: '',
    stripeSubscriptionId: 'sub_123',
  });
  assert.equal(bySub, 't_sub');

  const byCus = await webhookTenantResolution.resolveTenantIdFromStripeReferences({
    firestore,
    explicitTenantId: '',
    stripeCustomerId: 'cus_123',
    stripeSubscriptionId: '',
  });
  assert.equal(byCus, 't_cus');
});

test('webhook tenant resolution: asaas references and fallbacks', async () => {
  const firestore = createTenantsFirestore([
    {
      id: 'tenant_ref',
      data: {
        asaasSubscriptionId: 'sub_a1',
        asaasCustomerId: 'cus_a1',
        asaasCheckoutId: 'chk_a1',
        asaasPaymentId: 'pay_a1',
      },
    },
  ]);

  const byReference = await webhookTenantResolution.resolveTenantIdFromAsaasReferences({
    firestore,
    eventPayload: {
      payment: {
        externalReference: JSON.stringify({ tenantId: 'tenant_ref' }),
      },
    },
  });
  assert.equal(byReference, 'tenant_ref');

  const bySubscription = await webhookTenantResolution.resolveTenantIdFromAsaasReferences({
    firestore,
    eventPayload: {
      payment: {
        subscription: 'sub_a1',
      },
    },
  });
  assert.equal(bySubscription, 'tenant_ref');

  const byInvoicePayment = await webhookTenantResolution.resolveTenantIdFromAsaasReferences({
    firestore,
    eventPayload: {
      invoice: {
        payment: 'pay_a1',
      },
    },
  });
  assert.equal(byInvoicePayment, 'tenant_ref');
});

test('webhook tenant resolution returns empty when no match exists', async () => {
  const firestore = createTenantsFirestore([]);

  const result = await webhookTenantResolution.resolveTenantIdFromAsaasReferences({
    firestore,
    eventPayload: {
      payment: {
        externalReference: 'tenantId=unknown',
      },
    },
  });

  assert.equal(result, '');
});
