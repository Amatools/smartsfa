const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeTenantBillingOperationWithJournal,
} = require('../../src/billing/tenant_billing_operation_orchestrator_helpers');

function baseInput(overrides = {}) {
  return {
    firestore: { marker: true },
    tenantId: 'tenant_1',
    operationId: 'op_1234567890abcdef',
    operationType: 'change_seats',
    requestHash: 'hash_v1',
    lockOwnerToken: 'lock_owner_1234567890',
    nowDate: new Date('2026-11-18T16:00:00.000Z'),
    ...overrides,
  };
}

test('executeTenantBillingOperationWithJournal returns duplicate without executing operation', async () => {
  let executed = false;

  const result = await executeTenantBillingOperationWithJournal(
    baseInput({
      executeOperation: async () => {
        executed = true;
        return { ok: true };
      },
      acquireOperationLock: async () => ({
        ok: true,
        acquired: false,
        duplicate: true,
        reason: 'already_applied',
        operation: { status: 'applied' },
      }),
      completeOperation: async () => {
        throw new Error('should_not_complete');
      },
    }),
  );

  assert.equal(executed, false);
  assert.equal(result.ok, true);
  assert.equal(result.executed, false);
  assert.equal(result.duplicate, true);
  assert.equal(result.reason, 'already_applied');
});

test('executeTenantBillingOperationWithJournal returns retryable when lock is active', async () => {
  const result = await executeTenantBillingOperationWithJournal(
    baseInput({
      executeOperation: async () => ({ ok: true }),
      acquireOperationLock: async () => ({
        ok: false,
        acquired: false,
        duplicate: false,
        reason: 'lock_active',
      }),
      completeOperation: async () => {
        throw new Error('should_not_complete');
      },
    }),
  );

  assert.equal(result.ok, false);
  assert.equal(result.executed, false);
  assert.equal(result.retryable, true);
  assert.equal(result.reason, 'lock_active');
});

test('executeTenantBillingOperationWithJournal executes and completes applied status', async () => {
  const completeCalls = [];

  const result = await executeTenantBillingOperationWithJournal(
    baseInput({
      executeOperation: async () => ({
        status: 'applied',
        responseSnapshot: { checkoutId: 'chk_1' },
      }),
      acquireOperationLock: async () => ({
        ok: true,
        acquired: true,
        duplicate: false,
        reason: 'acquired_new',
        lockOwnerToken: 'lock_owner_1234567890',
      }),
      completeOperation: async (input) => {
        completeCalls.push(input);
        return {
          ok: true,
          updated: true,
          reason: 'completed',
          operation: {
            status: input.nextStatus,
            responseSnapshot: input.responseSnapshot,
          },
        };
      },
    }),
  );

  assert.equal(completeCalls.length, 1);
  assert.equal(completeCalls[0].nextStatus, 'applied');
  assert.deepEqual(completeCalls[0].responseSnapshot, { checkoutId: 'chk_1' });

  assert.equal(result.ok, true);
  assert.equal(result.executed, true);
  assert.equal(result.status, 'applied');
  assert.deepEqual(result.responseSnapshot, { checkoutId: 'chk_1' });
});

test('executeTenantBillingOperationWithJournal marks failed when executor throws', async () => {
  const completeCalls = [];

  const result = await executeTenantBillingOperationWithJournal(
    baseInput({
      executeOperation: async () => {
        const err = new Error('provider timeout');
        err.code = 'provider_timeout';
        throw err;
      },
      acquireOperationLock: async () => ({
        ok: true,
        acquired: true,
        duplicate: false,
        reason: 'acquired_new',
        lockOwnerToken: 'lock_owner_1234567890',
      }),
      completeOperation: async (input) => {
        completeCalls.push(input);
        return {
          ok: true,
          updated: true,
          reason: 'completed',
          operation: {
            status: input.nextStatus,
            errorCode: input.errorCode,
            errorMessage: input.errorMessage,
          },
        };
      },
      releaseOperationLock: async () => {
        throw new Error('should_not_release');
      },
    }),
  );

  assert.equal(completeCalls.length, 1);
  assert.equal(completeCalls[0].nextStatus, 'failed');
  assert.equal(completeCalls[0].errorCode, 'provider_timeout');
  assert.match(completeCalls[0].errorMessage, /provider timeout/);

  assert.equal(result.ok, false);
  assert.equal(result.executed, true);
  assert.equal(result.reason, 'execution_failed');
  assert.equal(result.errorCode, 'provider_timeout');
  assert.equal(result.errorStatus, 0);
  assert.equal(result.errorBody, null);
});

test('executeTenantBillingOperationWithJournal propagates structured status and body from execution errors', async () => {
  const result = await executeTenantBillingOperationWithJournal(
    baseInput({
      executeOperation: async () => {
        const err = new Error('provider rejected payload');
        err.code = 'invalid_payload';
        err.status = 422;
        err.body = {
          error: 'invalid_payload',
          message: 'payload invalido',
        };
        throw err;
      },
      acquireOperationLock: async () => ({
        ok: true,
        acquired: true,
        duplicate: false,
        reason: 'acquired_new',
        lockOwnerToken: 'lock_owner_1234567890',
      }),
      completeOperation: async () => ({
        ok: true,
        updated: true,
        reason: 'completed',
        operation: { status: 'failed' },
      }),
    }),
  );

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'execution_failed');
  assert.equal(result.errorStatus, 422);
  assert.deepEqual(result.errorBody, {
    error: 'invalid_payload',
    message: 'payload invalido',
  });
});

test('executeTenantBillingOperationWithJournal releases lock when failed completion is not ok', async () => {
  const releaseCalls = [];

  const result = await executeTenantBillingOperationWithJournal(
    baseInput({
      executeOperation: async () => {
        throw new Error('boom');
      },
      acquireOperationLock: async () => ({
        ok: true,
        acquired: true,
        duplicate: false,
        reason: 'acquired_new',
        lockOwnerToken: 'lock_owner_1234567890',
      }),
      completeOperation: async () => ({
        ok: false,
        updated: false,
        reason: 'lock_mismatch',
        operation: null,
      }),
      releaseOperationLock: async (input) => {
        releaseCalls.push(input);
        return {
          ok: true,
          updated: true,
          reason: 'released',
        };
      },
    }),
  );

  assert.equal(releaseCalls.length, 1);
  assert.equal(releaseCalls[0].tenantId, 'tenant_1');
  assert.equal(releaseCalls[0].operationId, 'op_1234567890abcdef');
  assert.equal(releaseCalls[0].lockOwnerToken, 'lock_owner_1234567890');

  assert.equal(result.ok, false);
  assert.equal(result.executed, true);
  assert.equal(result.reason, 'execution_failed');
});
