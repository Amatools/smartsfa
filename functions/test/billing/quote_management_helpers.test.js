const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeCreateBillingQuoteAction,
} = require('../../src/billing/quote_management_helpers');

function createFirestore({ tenantExists = true, tenantData = {} } = {}) {
  const auditWrites = [];
  return {
    auditWrites,
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

        if (name === 'tenant_billing_audit') {
          return {
            async add(payload) {
              auditWrites.push(payload);
            },
          };
        }

        throw new Error(`Unexpected collection ${name}`);
      },
    },
  };
}

test('executeCreateBillingQuoteAction returns permission error when actor is not allowed', async () => {
  const { firestore, auditWrites } = createFirestore({ tenantExists: true, tenantData: {} });

  const result = await executeCreateBillingQuoteAction({
    firestore,
    payload: {},
    tenantId: 'tenant_1',
    authContext: { uid: 'uid_1' },
    assertTenantBillingActorPermission: async () => ({
      allowed: false,
      status: 403,
      error: 'owner_required',
      message: 'not allowed',
    }),
    readCheckoutApiConfig: async () => ({ activeProviders: ['asaas'] }),
    resolveCheckoutApiProviderSelection: () => ({ provider: 'asaas' }),
    createAsaasBillingQuote: async () => ({ ok: true, status: 200, body: {} }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'owner_required');
  assert.equal(auditWrites.length, 1);
  assert.equal(auditWrites[0].action, 'billing_quote_denied');
  assert.equal(auditWrites[0].details.error, 'owner_required');
});

test('executeCreateBillingQuoteAction returns provider_quote_not_supported for stripe', async () => {
  const { firestore, auditWrites } = createFirestore({ tenantExists: true, tenantData: {} });

  const result = await executeCreateBillingQuoteAction({
    firestore,
    payload: {},
    tenantId: 'tenant_2',
    authContext: { uid: 'uid_2' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({
      activeProviders: ['stripe', 'asaas'],
      preferredProvider: 'stripe',
    }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'stripe',
      source: 'preferred_provider',
      hasLinkedContract: false,
    }),
    createAsaasBillingQuote: async () => ({ ok: true, status: 200, body: {} }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.error, 'provider_quote_not_supported');
  assert.equal(auditWrites.length, 1);
  assert.equal(auditWrites[0].action, 'billing_quote_failed');
  assert.equal(auditWrites[0].details.reasonCode, 'provider_quote_not_supported');
});

test('executeCreateBillingQuoteAction returns Asaas quote payload when helper succeeds', async () => {
  const { firestore, auditWrites } = createFirestore({ tenantExists: true, tenantData: {} });

  const result = await executeCreateBillingQuoteAction({
    firestore,
    payload: { billingPlanKey: 'enterprise_plus' },
    tenantId: 'tenant_3',
    authContext: { uid: 'uid_3' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({
      activeProviders: ['asaas'],
      preferredProvider: 'asaas',
    }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    createAsaasBillingQuote: async () => ({
      ok: true,
      status: 200,
      body: {
        quoteId: 'quote_1',
        totalAmountCents: 3590,
      },
    }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.quoteId, 'quote_1');
  assert.equal(result.body.totalAmountCents, 3590);
  assert.equal(auditWrites.length, 1);
  assert.equal(auditWrites[0].action, 'billing_quote_created');
  assert.equal(auditWrites[0].details.quoteId, 'quote_1');
});

test('executeCreateBillingQuoteAction uses operation journal and returns quote snapshot', async () => {
  const { firestore, auditWrites } = createFirestore({ tenantExists: true, tenantData: {} });
  const journalCalls = [];

  const result = await executeCreateBillingQuoteAction({
    firestore,
    payload: {
      billingPlanKey: 'enterprise_plus',
      operationId: 'op_1234567890abcdef',
    },
    tenantId: 'tenant_4',
    authContext: { uid: 'uid_4' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({
      activeProviders: ['asaas'],
      preferredProvider: 'asaas',
    }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    createAsaasBillingQuote: async () => ({
      ok: true,
      status: 200,
      body: {
        quoteId: 'quote_2',
      },
    }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
    readCheckoutOperationIdFromPayload: () => 'op_1234567890abcdef',
    buildQuoteOperationRequestHash: () => 'hash_quote_1',
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
  assert.equal(journalCalls[0].operationType, 'create_quote');
  assert.equal(journalCalls[0].requestHash, 'hash_quote_1');
  assert.equal(result.status, 200);
  assert.equal(result.body.quoteId, 'quote_2');
  assert.equal(auditWrites.length, 1);
  assert.equal(auditWrites[0].action, 'billing_quote_created');
  assert.equal(auditWrites[0].details.operationId, 'op_1234567890abcdef');
  assert.equal(auditWrites[0].details.requestHash, 'hash_quote_1');
});

test('executeCreateBillingQuoteAction writes replay audit when journal returns duplicate', async () => {
  const { firestore, auditWrites } = createFirestore({ tenantExists: true, tenantData: {} });

  const result = await executeCreateBillingQuoteAction({
    firestore,
    payload: {
      billingPlanKey: 'enterprise_plus',
      operationId: 'op_abcdef1234567890',
    },
    tenantId: 'tenant_5',
    authContext: { uid: 'uid_5' },
    assertTenantBillingActorPermission: async () => ({ allowed: true }),
    readCheckoutApiConfig: async () => ({
      activeProviders: ['asaas'],
      preferredProvider: 'asaas',
    }),
    resolveCheckoutApiProviderSelection: () => ({
      provider: 'asaas',
      source: 'payload_provider',
      hasLinkedContract: false,
    }),
    createAsaasBillingQuote: async () => ({
      ok: true,
      status: 200,
      body: {
        quoteId: 'quote_duplicate',
      },
    }),
    billingProviderStripe: 'stripe',
    billingProviderAsaas: 'asaas',
    readCheckoutOperationIdFromPayload: () => 'op_abcdef1234567890',
    buildQuoteOperationRequestHash: () => 'hash_quote_duplicate',
    executeTenantBillingOperationWithJournal: async () => ({
      ok: true,
      executed: false,
      duplicate: true,
      retryable: false,
      reason: 'duplicate',
      operation: {
        responseSnapshot: {
          status: 200,
          body: {
            quoteId: 'quote_duplicate',
            duplicate: true,
          },
        },
      },
    }),
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.quoteId, 'quote_duplicate');
  assert.equal(auditWrites.length, 1);
  assert.equal(auditWrites[0].action, 'billing_quote_replayed');
  assert.equal(auditWrites[0].details.operationId, 'op_abcdef1234567890');
});