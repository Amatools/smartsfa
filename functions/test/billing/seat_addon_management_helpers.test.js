const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeUpdateBillingSeatAddonsAction,
} = require('../../src/billing/seat_addon_management_helpers');

function createFirestore({ tenantExists = true, tenantData = {} } = {}) {
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

        throw new Error(`Unexpected collection ${name}`);
      },
    },
  };
}

test('executeUpdateBillingSeatAddonsAction returns permission error when actor is not allowed', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeUpdateBillingSeatAddonsAction({
    firestore,
    payload: {},
    tenantId: 'tenant_1',
    billingPlanKey: 'starter',
    addonSeatsDelta: 1,
    authContext: { uid: 'uid_1', email: 'u1@example.com' },
    assertTenantBillingActorPermission: async () => ({
      allowed: false,
      status: 403,
      error: 'owner_required',
      message: 'not allowed',
    }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    resolveCheckoutApiProviderSelection: () => ({ provider: 'stripe' }),
    loadBillingProviderRuntime: async () => ({ ok: true }),
    applyStripeSeatAddonDeltaToActiveSubscription: async () => ({ applied: true }),
    enforceTenantSeatAllowanceForTenant: async () => ({}),
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'owner_required');
});

test('executeUpdateBillingSeatAddonsAction returns provider_disabled when provider is inactive without linked contract', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeUpdateBillingSeatAddonsAction({
    firestore,
    payload: {},
    tenantId: 'tenant_2',
    billingPlanKey: 'starter',
    addonSeatsDelta: 1,
    authContext: { uid: 'uid_2', email: 'u2@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'tenant_linked_contract',
      hasLinkedContract: false,
    }),
    loadBillingProviderRuntime: async () => ({ ok: true }),
    applyStripeSeatAddonDeltaToActiveSubscription: async () => ({ applied: true }),
    enforceTenantSeatAllowanceForTenant: async () => ({}),
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'provider_disabled');
});

test('executeUpdateBillingSeatAddonsAction rejects providers other than stripe', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeUpdateBillingSeatAddonsAction({
    firestore,
    payload: {},
    tenantId: 'tenant_3',
    billingPlanKey: 'starter',
    addonSeatsDelta: 1,
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: true,
    }),
    loadBillingProviderRuntime: async () => ({ ok: true }),
    applyStripeSeatAddonDeltaToActiveSubscription: async () => ({ applied: true }),
    enforceTenantSeatAllowanceForTenant: async () => ({}),
    billingProviderStripe: 'stripe',
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'seat_addon_update_not_supported_for_provider');
  assert.equal(result.body.billingProvider, 'asaas');
});

test('executeUpdateBillingSeatAddonsAction returns success and tolerates seat enforcement failures', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {
      stripeSubscriptionId: 'sub_4',
    },
  });

  const loggedErrors = [];
  const result = await executeUpdateBillingSeatAddonsAction({
    firestore,
    payload: { provider: 'stripe' },
    tenantId: 'tenant_4',
    billingPlanKey: 'pro',
    addonSeatsDelta: 2,
    authContext: { uid: 'uid_4', email: 'u4@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    loadBillingProviderRuntime: async () => ({ ok: true, stripeClient: {} }),
    applyStripeSeatAddonDeltaToActiveSubscription: async () => ({
      applied: true,
      billingPlanKey: 'pro',
      addedSeats: 2,
      previousAddonSeats: 1,
      currentAddonSeats: 3,
      stripeSubscriptionId: 'sub_4',
      stripeAddonPriceId: 'price_addon',
      invoiceId: 'in_4',
      invoiceStatus: 'open',
      invoiceUrl: 'https://stripe.example/in_4',
      message: 'updated',
    }),
    enforceTenantSeatAllowanceForTenant: async () => {
      throw new Error('seat_enforcement_failed');
    },
    billingProviderStripe: 'stripe',
    logError: (...args) => loggedErrors.push(args),
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.tenantId, 'tenant_4');
  assert.equal(result.body.billingProvider, 'stripe');
  assert.equal(result.body.billingPlanKey, 'pro');
  assert.equal(result.body.addedSeats, 2);
  assert.equal(result.body.currentAddonSeats, 3);
  assert.equal(result.body.providerSelectionSource, 'payload_provider');
  assert.equal(result.body.hasLinkedContract, false);
  assert.equal(result.body.seatEnforcementSummary, null);
  assert.match(result.body.seatEnforcementError, /seat_enforcement_failed/);
  assert.equal(loggedErrors.length, 1);
  assert.equal(loggedErrors[0][0], 'updateBillingSeatAddons seat enforcement failed');
});
