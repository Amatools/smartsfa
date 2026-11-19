const {
  acquireTenantBillingOperationLock,
  completeTenantBillingOperation,
  releaseTenantBillingOperationLock,
} = require('./tenant_billing_operation_journal_helpers');

function readOperationFailureCode(error) {
  const fromCode = String(error?.code ?? '').trim();
  if (fromCode) {
    return fromCode;
  }
  return 'billing_operation_execution_failed';
}

function readOperationFailureMessage(error) {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error ?? 'Falha na execucao da operacao de billing.');
}

function readOperationFailureStatus(error) {
  const parsed = Number(error?.status ?? 0);
  if (!Number.isFinite(parsed)) {
    return 0;
  }

  const asInt = Math.floor(parsed);
  if (asInt < 400 || asInt > 599) {
    return 0;
  }
  return asInt;
}

function readOperationFailureBody(error) {
  if (error?.body && typeof error.body === 'object') {
    return error.body;
  }
  return null;
}

async function executeTenantBillingOperationWithJournal({
  firestore,
  tenantId,
  operationId,
  operationType,
  requestHash,
  lockOwnerToken,
  lockLeaseMs,
  nowDate,
  executeOperation,
  acquireOperationLock = acquireTenantBillingOperationLock,
  completeOperation = completeTenantBillingOperation,
  releaseOperationLock = releaseTenantBillingOperationLock,
}) {
  if (typeof executeOperation !== 'function') {
    throw new Error('billing_operation_executor_missing');
  }

  const lockResult = await acquireOperationLock({
    firestore,
    tenantId,
    operationId,
    operationType,
    requestHash,
    lockOwnerToken,
    lockLeaseMs,
    nowDate,
  });

  if (!lockResult.ok || !lockResult.acquired) {
    return {
      ok: Boolean(lockResult.ok),
      executed: false,
      duplicate: Boolean(lockResult.duplicate),
      retryable: lockResult.reason === 'lock_active',
      reason: lockResult.reason,
      operation: lockResult.operation || null,
    };
  }

  const activeLockToken = lockResult.lockOwnerToken;

  try {
    const executionResult = await executeOperation({
      tenantId,
      operationId,
      operationType,
      requestHash,
    });

    const normalizedStatus =
      String(executionResult?.status ?? '').trim() || 'applied';
    const responseSnapshot =
      executionResult && typeof executionResult === 'object'
        ? executionResult.responseSnapshot || executionResult
        : null;

    const completion = await completeOperation({
      firestore,
      tenantId,
      operationId,
      lockOwnerToken: activeLockToken,
      nextStatus: normalizedStatus,
      responseSnapshot,
      errorCode: '',
      errorMessage: '',
      nowDate,
    });

    return {
      ok: Boolean(completion.ok),
      executed: true,
      duplicate: false,
      retryable: false,
      reason: completion.reason,
      status: normalizedStatus,
      operation: completion.operation || null,
      responseSnapshot,
    };
  } catch (error) {
    const failureCode = readOperationFailureCode(error);
    const failureMessage = readOperationFailureMessage(error);
    const failureStatus = readOperationFailureStatus(error);
    const failureBody = readOperationFailureBody(error);

    const failureCompletion = await completeOperation({
      firestore,
      tenantId,
      operationId,
      lockOwnerToken: activeLockToken,
      nextStatus: 'failed',
      responseSnapshot: null,
      errorCode: failureCode,
      errorMessage: failureMessage,
      nowDate,
    });

    if (!failureCompletion.ok) {
      await releaseOperationLock({
        firestore,
        tenantId,
        operationId,
        lockOwnerToken: activeLockToken,
        nowDate,
      });
    }

    return {
      ok: false,
      executed: true,
      duplicate: false,
      retryable: false,
      reason: 'execution_failed',
      status: 'failed',
      errorStatus: failureStatus,
      errorBody: failureBody,
      errorCode: failureCode,
      errorMessage: failureMessage,
      operation: failureCompletion.operation || null,
    };
  }
}

module.exports = {
  executeTenantBillingOperationWithJournal,
};
