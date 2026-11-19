const test = require('node:test');
const assert = require('node:assert/strict');

const {
  acquireTenantBillingOperationLock,
  completeTenantBillingOperation,
  releaseTenantBillingOperationLock,
} = require('../../src/billing/tenant_billing_operation_journal_helpers');

function createOperationFirestore(initialDocs = {}) {
  const docs = new Map(Object.entries(initialDocs));

  function mergeData(current, patch) {
    return {
      ...(current || {}),
      ...(patch || {}),
    };
  }

  return {
    docs,
    collection(name) {
      assert.equal(name, 'tenant_billing_operations');
      return {
        doc(id) {
          return {
            id,
            async set(data, options) {
              const current = docs.get(id) || null;
              if (options?.merge) {
                docs.set(id, mergeData(current, data));
                return;
              }
              docs.set(id, { ...(data || {}) });
            },
            async get() {
              const data = docs.get(id);
              return {
                exists: data !== undefined,
                data: () => (data ? { ...data } : undefined),
              };
            },
          };
        },
      };
    },
    async runTransaction(callback) {
      const tx = {
        async get(ref) {
          const data = docs.get(ref.id);
          return {
            exists: data !== undefined,
            data: () => (data ? { ...data } : undefined),
          };
        },
        set(ref, data, options) {
          const current = docs.get(ref.id) || null;
          if (options?.merge) {
            docs.set(ref.id, mergeData(current, data));
            return;
          }
          docs.set(ref.id, { ...(data || {}) });
        },
      };

      return callback(tx);
    },
  };
}

test('acquireTenantBillingOperationLock creates a new received operation with lock', async () => {
  const firestore = createOperationFirestore();

  const result = await acquireTenantBillingOperationLock({
    firestore,
    tenantId: 'tenant_1',
    operationId: 'op_1234567890abcdef',
    operationType: 'create_quote',
    requestHash: 'hash_v1',
    lockOwnerToken: 'lock_owner_1234567890',
    nowDate: new Date('2026-11-18T15:00:00.000Z'),
    lockLeaseMs: 60000,
  });

  assert.equal(result.ok, true);
  assert.equal(result.acquired, true);
  assert.equal(result.reason, 'acquired_new');
  assert.equal(result.operation.status, 'received');
  assert.equal(result.operation.requestHash, 'hash_v1');
  assert.equal(result.operation.lockOwnerToken, 'lock_owner_1234567890');
  assert.equal(result.operation.createdAt, '2026-11-18T15:00:00.000Z');
  assert.equal(result.operation.lockExpiresAt, '2026-11-18T15:01:00.000Z');

  assert.equal(firestore.docs.size, 1);
});

test('acquireTenantBillingOperationLock returns duplicate when already applied', async () => {
  const firestore = createOperationFirestore({
    tenant_1__op_1234567890abcdef: {
      tenantId: 'tenant_1',
      operationId: 'op_1234567890abcdef',
      operationType: 'create_quote',
      requestHash: 'hash_v1',
      status: 'applied',
      lockOwnerToken: '',
    },
  });

  const result = await acquireTenantBillingOperationLock({
    firestore,
    tenantId: 'tenant_1',
    operationId: 'op_1234567890abcdef',
    operationType: 'create_quote',
    requestHash: 'hash_v1',
    lockOwnerToken: 'lock_owner_1234567890',
    nowDate: new Date('2026-11-18T15:00:00.000Z'),
  });

  assert.equal(result.ok, true);
  assert.equal(result.acquired, false);
  assert.equal(result.duplicate, true);
  assert.equal(result.reason, 'already_applied');
});

test('acquireTenantBillingOperationLock returns conflict for request hash mismatch', async () => {
  const firestore = createOperationFirestore({
    tenant_1__op_1234567890abcdef: {
      tenantId: 'tenant_1',
      operationId: 'op_1234567890abcdef',
      operationType: 'create_quote',
      requestHash: 'hash_v1',
      status: 'received',
      lockOwnerToken: '',
    },
  });

  const result = await acquireTenantBillingOperationLock({
    firestore,
    tenantId: 'tenant_1',
    operationId: 'op_1234567890abcdef',
    operationType: 'create_quote',
    requestHash: 'hash_v2',
    lockOwnerToken: 'lock_owner_1234567890',
    nowDate: new Date('2026-11-18T15:00:00.000Z'),
  });

  assert.equal(result.ok, false);
  assert.equal(result.acquired, false);
  assert.equal(result.reason, 'request_hash_mismatch');
});

test('acquireTenantBillingOperationLock blocks when another lock is active', async () => {
  const firestore = createOperationFirestore({
    tenant_1__op_1234567890abcdef: {
      tenantId: 'tenant_1',
      operationId: 'op_1234567890abcdef',
      operationType: 'create_quote',
      requestHash: 'hash_v1',
      status: 'received',
      lockOwnerToken: 'lock_other_1234567890',
      lockExpiresAt: '2026-11-18T15:05:00.000Z',
    },
  });

  const result = await acquireTenantBillingOperationLock({
    firestore,
    tenantId: 'tenant_1',
    operationId: 'op_1234567890abcdef',
    operationType: 'create_quote',
    requestHash: 'hash_v1',
    lockOwnerToken: 'lock_owner_1234567890',
    nowDate: new Date('2026-11-18T15:00:00.000Z'),
  });

  assert.equal(result.ok, false);
  assert.equal(result.acquired, false);
  assert.equal(result.reason, 'lock_active');
});

test('completeTenantBillingOperation finalizes state and clears lock', async () => {
  const firestore = createOperationFirestore({
    tenant_1__op_1234567890abcdef: {
      tenantId: 'tenant_1',
      operationId: 'op_1234567890abcdef',
      operationType: 'create_quote',
      requestHash: 'hash_v1',
      status: 'received',
      lockOwnerToken: 'lock_owner_1234567890',
      lockAcquiredAt: '2026-11-18T15:00:00.000Z',
      lockExpiresAt: '2026-11-18T15:05:00.000Z',
    },
  });

  const result = await completeTenantBillingOperation({
    firestore,
    tenantId: 'tenant_1',
    operationId: 'op_1234567890abcdef',
    lockOwnerToken: 'lock_owner_1234567890',
    nextStatus: 'applied',
    responseSnapshot: { checkoutId: 'chk_1' },
    nowDate: new Date('2026-11-18T15:01:00.000Z'),
  });

  assert.equal(result.ok, true);
  assert.equal(result.updated, true);
  assert.equal(result.operation.status, 'applied');
  assert.deepEqual(result.operation.responseSnapshot, { checkoutId: 'chk_1' });
  assert.equal(result.operation.lockOwnerToken, '');
  assert.equal(result.operation.updatedAt, '2026-11-18T15:01:00.000Z');
});

test('completeTenantBillingOperation returns lock mismatch when token differs', async () => {
  const firestore = createOperationFirestore({
    tenant_1__op_1234567890abcdef: {
      tenantId: 'tenant_1',
      operationId: 'op_1234567890abcdef',
      operationType: 'create_quote',
      requestHash: 'hash_v1',
      status: 'received',
      lockOwnerToken: 'lock_owner_1234567890',
    },
  });

  const result = await completeTenantBillingOperation({
    firestore,
    tenantId: 'tenant_1',
    operationId: 'op_1234567890abcdef',
    lockOwnerToken: 'lock_other_1234567890',
    nextStatus: 'failed',
    errorCode: 'provider_timeout',
    nowDate: new Date('2026-11-18T15:01:00.000Z'),
  });

  assert.equal(result.ok, false);
  assert.equal(result.updated, false);
  assert.equal(result.reason, 'lock_mismatch');
});

test('releaseTenantBillingOperationLock clears lock for current owner', async () => {
  const firestore = createOperationFirestore({
    tenant_1__op_1234567890abcdef: {
      tenantId: 'tenant_1',
      operationId: 'op_1234567890abcdef',
      operationType: 'create_quote',
      requestHash: 'hash_v1',
      status: 'received',
      lockOwnerToken: 'lock_owner_1234567890',
      lockAcquiredAt: '2026-11-18T15:00:00.000Z',
      lockExpiresAt: '2026-11-18T15:05:00.000Z',
    },
  });

  const result = await releaseTenantBillingOperationLock({
    firestore,
    tenantId: 'tenant_1',
    operationId: 'op_1234567890abcdef',
    lockOwnerToken: 'lock_owner_1234567890',
    nowDate: new Date('2026-11-18T15:02:00.000Z'),
  });

  assert.equal(result.ok, true);
  assert.equal(result.updated, true);
  assert.equal(result.reason, 'released');
  assert.equal(result.operation.lockOwnerToken, '');
  assert.equal(result.operation.lockExpiresAt, '');
});
