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

test('executeUpdateBillingSeatAddonsAction supports asaas provider when linked contract is asaas', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {
      asaasSubscriptionId: 'sub_asaas_1',
      billingPlanKey: 'enterprise_plus',
    },
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
      source: 'existing_contract',
      hasLinkedContract: true,
    }),
    loadBillingProviderRuntime: async () => ({
      ok: true,
      asaasApiKey: 'api_key',
      asaasApiBaseUrl: 'https://api.example',
    }),
    applyStripeSeatAddonDeltaToActiveSubscription: async () => ({ applied: true }),
    applyAsaasSeatAddonDeltaToActiveSubscription: async () => ({
      applied: true,
      billingPlanKey: 'enterprise_plus',
      addedSeats: 1,
      previousAddonSeats: 2,
      currentAddonSeats: 3,
      asaasSubscriptionId: 'sub_asaas_1',
      asaasAddonPlanKey: 'enterprise_plus_extra_usuario',
      asaasSubscriptionValue: 40.9,
      asaasSubscriptionStatus: 'ACTIVE',
      message: 'updated',
    }),
    enforceTenantSeatAllowanceForTenant: async () => ({}),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.billingProvider, 'asaas');
  assert.equal(result.body.currentAddonSeats, 3);
});

test('executeUpdateBillingSeatAddonsAction rejects unsupported providers', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeUpdateBillingSeatAddonsAction({
    firestore,
    payload: {},
    tenantId: 'tenant_3x',
    billingPlanKey: 'starter',
    addonSeatsDelta: 1,
    authContext: { uid: 'uid_3x', email: 'u3x@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'custom_provider',
      source: 'payload_provider',
      hasLinkedContract: true,
    }),
    loadBillingProviderRuntime: async () => ({ ok: true }),
    applyStripeSeatAddonDeltaToActiveSubscription: async () => ({ applied: true }),
    applyAsaasSeatAddonDeltaToActiveSubscription: async () => ({ applied: true }),
    enforceTenantSeatAllowanceForTenant: async () => ({}),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'seat_addon_update_not_supported_for_provider');
  assert.equal(result.body.billingProvider, 'custom_provider');
});

test('executeUpdateBillingSeatAddonsAction keeps explicit provider in unsupported response', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeUpdateBillingSeatAddonsAction({
    firestore,
    payload: {},
    tenantId: 'tenant_3y',
    billingPlanKey: 'starter',
    addonSeatsDelta: 1,
    authContext: { uid: 'uid_3y', email: 'u3y@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: true,
    }),
    loadBillingProviderRuntime: async () => ({ ok: true }),
    applyStripeSeatAddonDeltaToActiveSubscription: async () => ({ applied: true }),
    applyAsaasSeatAddonDeltaToActiveSubscription: async () => ({
      applied: false,
      status: 409,
      error: 'invalid_seat_addon_mapping',
      action: 'seat_addon_mapping_invalid',
      message: 'missing overage mapping',
    }),
    enforceTenantSeatAllowanceForTenant: async () => ({}),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'invalid_seat_addon_mapping');
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

test('executeUpdateBillingSeatAddonsAction keeps existing linked provider even when not active for new selections', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {
      stripeSubscriptionId: 'sub_legacy_1',
    },
  });

  let runtimeCalls = 0;
  const result = await executeUpdateBillingSeatAddonsAction({
    firestore,
    payload: { provider: 'asaas' },
    tenantId: 'tenant_legacy_1',
    billingPlanKey: 'pro',
    addonSeatsDelta: 1,
    authContext: { uid: 'uid_legacy_1', email: 'legacy@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'existing_contract',
      hasLinkedContract: true,
    }),
    loadBillingProviderRuntime: async () => {
      runtimeCalls += 1;
      return {
        ok: true,
        stripeClient: {},
      };
    },
    applyStripeSeatAddonDeltaToActiveSubscription: async () => ({
      applied: true,
      billingPlanKey: 'pro',
      addedSeats: 1,
      previousAddonSeats: 2,
      currentAddonSeats: 3,
      stripeSubscriptionId: 'sub_legacy_1',
      stripeAddonPriceId: 'price_addon',
      invoiceId: 'in_legacy_1',
      invoiceStatus: 'open',
      invoiceUrl: 'https://stripe.example/in_legacy_1',
      message: 'updated',
    }),
    enforceTenantSeatAllowanceForTenant: async () => ({ state: 'within_limit' }),
    billingProviderStripe: 'stripe',
  });

  assert.equal(runtimeCalls, 1);
  assert.equal(result.status, 200);
  assert.equal(result.body.billingProvider, 'stripe');
  assert.equal(result.body.providerSelectionSource, 'existing_contract');
  assert.equal(result.body.hasLinkedContract, true);
});

test('executeUpdateBillingSeatAddonsAction uses operation journal and returns snapshot for stripe', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {
      stripeSubscriptionId: 'sub_5',
    },
  });
  const journalCalls = [];

  const result = await executeUpdateBillingSeatAddonsAction({
    firestore,
    payload: { operationId: 'op_1234567890abcdef' },
    tenantId: 'tenant_5',
    billingPlanKey: 'pro',
    addonSeatsDelta: 2,
    authContext: { uid: 'uid_5', email: 'u5@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'existing_contract',
      hasLinkedContract: true,
    }),
    loadBillingProviderRuntime: async () => ({ ok: true, stripeClient: {} }),
    applyStripeSeatAddonDeltaToActiveSubscription: async () => ({
      applied: true,
      billingPlanKey: 'pro',
      addedSeats: 2,
      previousAddonSeats: 1,
      currentAddonSeats: 3,
      stripeSubscriptionId: 'sub_5',
      stripeAddonPriceId: 'price_addon',
      invoiceId: 'in_5',
      invoiceStatus: 'open',
      invoiceUrl: 'https://stripe.example/in_5',
      message: 'updated',
    }),
    enforceTenantSeatAllowanceForTenant: async () => ({ state: 'within_limit' }),
    billingProviderStripe: 'stripe',
    readCheckoutOperationIdFromPayload: () => 'op_1234567890abcdef',
    buildSeatAddonOperationRequestHash: () => 'hash_seat_1',
    executeTenantBillingOperationWithJournal: async (input) => {
      journalCalls.push(input);
      const execution = await input.executeOperation();
      return {
        ok: true,
        executed: true,
        duplicate: false,
        retryable: false,
        reason: 'completed',
        responseSnapshot: execution.responseSnapshot,
      };
    },
  });

  assert.equal(journalCalls.length, 1);
  assert.equal(journalCalls[0].operationType, 'change_seats');
  assert.equal(journalCalls[0].requestHash, 'hash_seat_1');
  assert.equal(result.status, 200);
  assert.equal(result.body.currentAddonSeats, 3);
});

test('executeUpdateBillingSeatAddonsAction replays duplicate operation snapshot', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {
      stripeSubscriptionId: 'sub_6',
    },
  });

  const result = await executeUpdateBillingSeatAddonsAction({
    firestore,
    payload: { operationId: 'op_1234567890abcdef' },
    tenantId: 'tenant_6',
    billingPlanKey: 'pro',
    addonSeatsDelta: 2,
    authContext: { uid: 'uid_6', email: 'u6@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'existing_contract',
      hasLinkedContract: true,
    }),
    loadBillingProviderRuntime: async () => ({ ok: true, stripeClient: {} }),
    applyStripeSeatAddonDeltaToActiveSubscription: async () => ({ applied: true }),
    enforceTenantSeatAllowanceForTenant: async () => ({ state: 'within_limit' }),
    billingProviderStripe: 'stripe',
    readCheckoutOperationIdFromPayload: () => 'op_1234567890abcdef',
    buildSeatAddonOperationRequestHash: () => 'hash_seat_2',
    executeTenantBillingOperationWithJournal: async () => ({
      ok: true,
      executed: false,
      duplicate: true,
      retryable: false,
      reason: 'already_applied',
      operation: {
        responseSnapshot: {
          status: 200,
          body: {
            tenantId: 'tenant_6',
            currentAddonSeats: 8,
          },
        },
      },
    }),
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.currentAddonSeats, 8);
});

test('executeUpdateBillingSeatAddonsAction maps operation lock to in-progress error', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {
      stripeSubscriptionId: 'sub_7',
    },
  });

  const result = await executeUpdateBillingSeatAddonsAction({
    firestore,
    payload: { operationId: 'op_1234567890abcdef' },
    tenantId: 'tenant_7',
    billingPlanKey: 'pro',
    addonSeatsDelta: 2,
    authContext: { uid: 'uid_7', email: 'u7@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'existing_contract',
      hasLinkedContract: true,
    }),
    loadBillingProviderRuntime: async () => ({ ok: true, stripeClient: {} }),
    applyStripeSeatAddonDeltaToActiveSubscription: async () => ({ applied: true }),
    enforceTenantSeatAllowanceForTenant: async () => ({ state: 'within_limit' }),
    billingProviderStripe: 'stripe',
    readCheckoutOperationIdFromPayload: () => 'op_1234567890abcdef',
    buildSeatAddonOperationRequestHash: () => 'hash_seat_3',
    executeTenantBillingOperationWithJournal: async () => ({
      ok: false,
      executed: false,
      duplicate: false,
      retryable: true,
      reason: 'lock_active',
    }),
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'operation_in_progress');
});
