const {
  buildTenantScopedOperationKey,
  normalizeOperationId,
  normalizeOperationStatus,
  normalizeOperationType,
  readContractVersion,
} = require('./internal_billing_engine_contract_helpers');
const {
  assertBillingOperationStatusTransition,
  isTerminalBillingOperationStatus,
} = require('./tenant_billing_operation_status_helpers');
const {
  buildBillingOperationLockWindow,
  isBillingOperationLockExpired,
  normalizeBillingOperationLockToken,
} = require('./tenant_billing_operation_lock_helpers');

function readOperationRequestHash(rawValue) {
  return String(rawValue ?? '').trim();
}

function buildOperationDocRef({ firestore, tenantId, operationId }) {
  const tenantToken = normalizeOperationId(tenantId, 96);
  const operationToken = normalizeOperationId(operationId, 128);
  if (!tenantToken || !operationToken) {
    throw new Error('billing_operation_identity_invalid');
  }

  const operationKey = buildTenantScopedOperationKey({
    tenantId: tenantToken,
    operationId: operationToken,
  });
  if (!operationKey) {
    throw new Error('billing_operation_identity_invalid');
  }

  return {
    operationKey,
    docRef: firestore.collection('tenant_billing_operations').doc(operationKey),
  };
}

function buildDefaultLockOwnerToken({ tenantId, operationId, nowDate }) {
  const now = nowDate instanceof Date ? nowDate : new Date();
  const seed = `${tenantId}:${operationId}:${now.getTime()}`;
  return normalizeBillingOperationLockToken(seed);
}

async function acquireTenantBillingOperationLock({
  firestore,
  tenantId,
  operationId,
  operationType,
  requestHash,
  lockOwnerToken,
  lockLeaseMs,
  nowDate,
  contractVersion,
}) {
  const normalizedType = normalizeOperationType(operationType);
  if (!normalizedType) {
    throw new Error('billing_operation_type_invalid');
  }

  const normalizedHash = readOperationRequestHash(requestHash);
  if (!normalizedHash) {
    throw new Error('billing_operation_request_hash_missing');
  }

  const now = nowDate instanceof Date ? nowDate : new Date();
  const nowIso = now.toISOString();
  const { operationKey, docRef } = buildOperationDocRef({
    firestore,
    tenantId,
    operationId,
  });

  const normalizedLockToken =
    normalizeBillingOperationLockToken(lockOwnerToken) ||
    buildDefaultLockOwnerToken({ tenantId, operationId, nowDate: now });

  if (!normalizedLockToken) {
    throw new Error('billing_operation_lock_token_invalid');
  }

  const lockWindow = buildBillingOperationLockWindow({
    nowDate: now,
    lockLeaseMs,
  });

  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(docRef);
    const data = snapshot.exists ? snapshot.data() || {} : null;

    if (!data) {
      const initial = {
        tenantId: normalizeOperationId(tenantId, 96),
        operationId: normalizeOperationId(operationId, 128),
        operationType: normalizedType,
        requestHash: normalizedHash,
        status: 'received',
        contractVersion: readContractVersion(contractVersion),
        lockOwnerToken: normalizedLockToken,
        lockAcquiredAt: lockWindow.acquiredAt,
        lockExpiresAt: lockWindow.expiresAt,
        retryCount: 0,
        createdAt: nowIso,
        updatedAt: nowIso,
        lastTransitionAt: nowIso,
      };

      transaction.set(docRef, initial, { merge: true });
      return {
        ok: true,
        acquired: true,
        duplicate: false,
        reason: 'acquired_new',
        operationKey,
        lockOwnerToken: normalizedLockToken,
        operation: initial,
      };
    }

    const currentHash = readOperationRequestHash(data.requestHash);
    if (currentHash && currentHash !== normalizedHash) {
      return {
        ok: false,
        acquired: false,
        duplicate: false,
        reason: 'request_hash_mismatch',
        operationKey,
        lockOwnerToken: '',
        operation: data,
      };
    }

    const currentStatus = normalizeOperationStatus(data.status);
    if (currentStatus === 'applied') {
      return {
        ok: true,
        acquired: false,
        duplicate: true,
        reason: 'already_applied',
        operationKey,
        lockOwnerToken: '',
        operation: data,
      };
    }

    const existingLockToken = normalizeBillingOperationLockToken(
      data.lockOwnerToken,
    );
    const lockExpired = isBillingOperationLockExpired({
      lockExpiresAt: data.lockExpiresAt,
      nowDate: now,
    });

    if (
      existingLockToken &&
      existingLockToken !== normalizedLockToken &&
      !lockExpired
    ) {
      return {
        ok: false,
        acquired: false,
        duplicate: false,
        reason: 'lock_active',
        operationKey,
        lockOwnerToken: '',
        operation: data,
      };
    }

    const currentRetry = Number(data.retryCount ?? 0);
    const patch = {
      tenantId: normalizeOperationId(tenantId, 96),
      operationId: normalizeOperationId(operationId, 128),
      operationType: normalizedType,
      requestHash: normalizedHash,
      status: currentStatus || 'received',
      contractVersion: readContractVersion(
        data.contractVersion,
        readContractVersion(contractVersion),
      ),
      lockOwnerToken: normalizedLockToken,
      lockAcquiredAt: lockWindow.acquiredAt,
      lockExpiresAt: lockWindow.expiresAt,
      retryCount: Number.isFinite(currentRetry) ? currentRetry + 1 : 1,
      updatedAt: nowIso,
      lastTransitionAt: nowIso,
    };

    transaction.set(docRef, patch, { merge: true });

    return {
      ok: true,
      acquired: true,
      duplicate: false,
      reason: 'acquired_existing',
      operationKey,
      lockOwnerToken: normalizedLockToken,
      operation: {
        ...data,
        ...patch,
      },
    };
  });
}

async function completeTenantBillingOperation({
  firestore,
  tenantId,
  operationId,
  lockOwnerToken,
  nextStatus,
  responseSnapshot,
  errorCode,
  errorMessage,
  nowDate,
}) {
  const normalizedStatus = normalizeOperationStatus(nextStatus);
  if (!isTerminalBillingOperationStatus(normalizedStatus)) {
    throw new Error('billing_operation_completion_status_invalid');
  }

  const normalizedLockToken = normalizeBillingOperationLockToken(lockOwnerToken);
  if (!normalizedLockToken) {
    throw new Error('billing_operation_lock_token_invalid');
  }

  const now = nowDate instanceof Date ? nowDate : new Date();
  const nowIso = now.toISOString();
  const { operationKey, docRef } = buildOperationDocRef({
    firestore,
    tenantId,
    operationId,
  });

  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(docRef);
    if (!snapshot.exists) {
      throw new Error('billing_operation_not_found');
    }

    const data = snapshot.data() || {};
    const currentLockToken = normalizeBillingOperationLockToken(data.lockOwnerToken);
    if (!currentLockToken || currentLockToken !== normalizedLockToken) {
      return {
        ok: false,
        updated: false,
        reason: 'lock_mismatch',
        operationKey,
        operation: data,
      };
    }

    const currentStatus = normalizeOperationStatus(data.status);
    assertBillingOperationStatusTransition({
      currentStatus,
      nextStatus: normalizedStatus,
    });

    const patch = {
      status: normalizedStatus,
      updatedAt: nowIso,
      lastTransitionAt: nowIso,
      lockOwnerToken: '',
      lockAcquiredAt: '',
      lockExpiresAt: '',
      responseSnapshot: responseSnapshot || null,
      errorCode: String(errorCode ?? '').trim(),
      errorMessage: String(errorMessage ?? '').trim(),
    };

    transaction.set(docRef, patch, { merge: true });

    return {
      ok: true,
      updated: true,
      reason: 'completed',
      operationKey,
      operation: {
        ...data,
        ...patch,
      },
    };
  });
}

async function releaseTenantBillingOperationLock({
  firestore,
  tenantId,
  operationId,
  lockOwnerToken,
  nowDate,
}) {
  const normalizedLockToken = normalizeBillingOperationLockToken(lockOwnerToken);
  if (!normalizedLockToken) {
    throw new Error('billing_operation_lock_token_invalid');
  }

  const now = nowDate instanceof Date ? nowDate : new Date();
  const nowIso = now.toISOString();
  const { operationKey, docRef } = buildOperationDocRef({
    firestore,
    tenantId,
    operationId,
  });

  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(docRef);
    if (!snapshot.exists) {
      return {
        ok: false,
        updated: false,
        reason: 'operation_not_found',
        operationKey,
        operation: null,
      };
    }

    const data = snapshot.data() || {};
    const currentLockToken = normalizeBillingOperationLockToken(data.lockOwnerToken);
    if (!currentLockToken || currentLockToken !== normalizedLockToken) {
      return {
        ok: false,
        updated: false,
        reason: 'lock_mismatch',
        operationKey,
        operation: data,
      };
    }

    const patch = {
      lockOwnerToken: '',
      lockAcquiredAt: '',
      lockExpiresAt: '',
      updatedAt: nowIso,
    };

    transaction.set(docRef, patch, { merge: true });

    return {
      ok: true,
      updated: true,
      reason: 'released',
      operationKey,
      operation: {
        ...data,
        ...patch,
      },
    };
  });
}

module.exports = {
  acquireTenantBillingOperationLock,
  completeTenantBillingOperation,
  releaseTenantBillingOperationLock,
};
