const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeCreateBillingCheckoutSessionAction,
} = require('../../src/billing/checkout_session_management_helpers');

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

test('executeCreateBillingCheckoutSessionAction returns permission error when actor is not allowed', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {},
    tenantId: 'tenant_1',
    authContext: { uid: 'uid_1', email: 'u1@example.com' },
    assertTenantBillingActorPermission: async () => ({
      allowed: false,
      status: 403,
      error: 'owner_required',
      message: 'not allowed',
    }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe'] }),
    resolveCheckoutApiProviderSelection: () => ({ provider: 'stripe' }),
    proxyBillingRequestToFunction: async () => {},
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({ ok: true }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'owner_required');
});

test('executeCreateBillingCheckoutSessionAction delegates stripe requests to proxy', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: { workspaceType: 'brand_owner_workspace' },
  });
  const proxyCalls = [];

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {},
    tenantId: 'tenant_2',
    authContext: { uid: 'uid_2', email: 'u2@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['stripe', 'asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async (input) => {
      proxyCalls.push(input);
    },
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({ ok: true }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, true);
  assert.equal(proxyCalls.length, 1);
  assert.equal(proxyCalls[0].targetUrl, 'https://example.test/checkout');
  assert.equal(proxyCalls[0].method, 'POST');
  assert.equal(proxyCalls[0].extraResponseFields.billingProvider, 'stripe');
});

test('executeCreateBillingCheckoutSessionAction returns provider_disabled for inactive provider without linked contract', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {},
    tenantId: 'tenant_3',
    authContext: { uid: 'uid_3', email: 'u3@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'tenant_linked_contract',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({ ok: true }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'provider_disabled');
});

test('executeCreateBillingCheckoutSessionAction returns asaas provider result when checkout helper succeeds', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: { workspaceType: 'revenda_workspace' },
  });

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: { billingPlanKey: 'revenda_pro' },
    tenantId: 'tenant_4',
    authContext: { uid: 'uid_4', email: 'u4@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: true,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({
      ok: true,
      status: 200,
      body: {
        checkoutUrl: 'https://asaas.example/checkout/abc',
      },
    }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 200);
  assert.equal(result.body.checkoutUrl, 'https://asaas.example/checkout/abc');
});

test('executeCreateBillingCheckoutSessionAction maps asaas exceptions to provider_checkout_failed', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {},
    tenantId: 'tenant_5',
    authContext: { uid: 'uid_5', email: 'u5@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => {
      throw new Error('checkout failed');
    },
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 502);
  assert.equal(result.body.error, 'provider_checkout_failed');
  assert.match(result.body.message, /checkout failed/);
});

test('executeCreateBillingCheckoutSessionAction uses operation journal and returns checkout snapshot for Asaas', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const journalCalls = [];

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {
      billingPlanKey: 'enterprise',
      operationId: 'op_1234567890abcdef',
    },
    tenantId: 'tenant_6',
    authContext: { uid: 'uid_6', email: 'u6@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({
      ok: true,
      status: 200,
      body: {
        checkoutUrl: 'https://asaas.example/checkout/ok',
      },
    }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
    readCheckoutOperationIdFromPayload: () => 'op_1234567890abcdef',
    buildCheckoutOperationRequestHash: () => 'hash_op_1',
    executeTenantBillingOperationWithJournal: async (input) => {
      journalCalls.push(input);
      const executionResult = await input.executeOperation();
      return {
        ok: true,
        executed: true,
        duplicate: false,
        retryable: false,
        reason: 'completed',
        responseSnapshot: executionResult.responseSnapshot,
      };
    },
  });

  assert.equal(journalCalls.length, 1);
  assert.equal(journalCalls[0].operationType, 'open_checkout');
  assert.equal(journalCalls[0].operationId, 'op_1234567890abcdef');
  assert.equal(journalCalls[0].requestHash, 'hash_op_1');

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 200);
  assert.equal(result.body.checkoutUrl, 'https://asaas.example/checkout/ok');
});

test('executeCreateBillingCheckoutSessionAction replays duplicate snapshot from operation journal', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {
      billingPlanKey: 'enterprise',
      operationId: 'op_1234567890abcdef',
    },
    tenantId: 'tenant_7',
    authContext: { uid: 'uid_7', email: 'u7@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({
      ok: true,
      status: 200,
      body: {
        checkoutUrl: 'https://asaas.example/checkout/should_not_run',
      },
    }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
    readCheckoutOperationIdFromPayload: () => 'op_1234567890abcdef',
    buildCheckoutOperationRequestHash: () => 'hash_op_2',
    executeTenantBillingOperationWithJournal: async () => ({
      ok: true,
      executed: false,
      duplicate: true,
      retryable: false,
      reason: 'already_applied',
      operation: {
        responseSnapshot: {
          handledByProxy: false,
          status: 200,
          body: {
            checkoutUrl: 'https://asaas.example/checkout/replayed',
          },
        },
      },
    }),
  });

  assert.equal(result.handledByProxy, false);
  assert.equal(result.status, 200);
  assert.equal(result.body.checkoutUrl, 'https://asaas.example/checkout/replayed');
});

test('executeCreateBillingCheckoutSessionAction maps operation lock_active to operation_in_progress', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {
      billingPlanKey: 'enterprise',
      operationId: 'op_1234567890abcdef',
    },
    tenantId: 'tenant_8',
    authContext: { uid: 'uid_8', email: 'u8@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({ ok: true, status: 200, body: {} }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
    readCheckoutOperationIdFromPayload: () => 'op_1234567890abcdef',
    buildCheckoutOperationRequestHash: () => 'hash_op_3',
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

test('executeCreateBillingCheckoutSessionAction preserves provider error body when operation execution fails', async () => {
  const { firestore } = createFirestore({
    tenantExists: true,
    tenantData: {},
  });

  const result = await executeCreateBillingCheckoutSessionAction({
    firestore,
    request: { method: 'POST' },
    response: {},
    payload: {
      billingPlanKey: 'enterprise',
      operationId: 'op_1234567890abcdef',
    },
    tenantId: 'tenant_9',
    authContext: { uid: 'uid_9', email: 'u9@example.com' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    proxyBillingRequestToFunction: async () => {},
    stripeCheckoutFunctionUrl: 'https://example.test/checkout',
    createAsaasCheckoutSession: async () => ({ ok: true, status: 200, body: {} }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
    readCheckoutOperationIdFromPayload: () => 'op_1234567890abcdef',
    buildCheckoutOperationRequestHash: () => 'hash_op_4',
    executeTenantBillingOperationWithJournal: async () => ({
      ok: false,
      executed: true,
      duplicate: false,
      retryable: false,
      reason: 'execution_failed',
      errorStatus: 422,
      errorBody: {
        error: 'invalid_payload',
        message: 'checkout invalido',
      },
    }),
  });

  assert.equal(result.status, 422);
  assert.equal(result.body.error, 'invalid_payload');
  assert.equal(result.body.message, 'checkout invalido');
});
