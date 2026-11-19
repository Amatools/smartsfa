const {
  executeTenantBillingOperationWithJournal:
    executeTenantBillingOperationWithJournalHelper,
} = require('./tenant_billing_operation_orchestrator_helpers');
const {
  buildQuoteOperationRequestHash: buildQuoteOperationRequestHashHelper,
  readCheckoutOperationIdFromPayload: readCheckoutOperationIdFromPayloadHelper,
} = require('./tenant_billing_operation_request_helpers');

async function executeAsaasQuoteDispatch({
  firestore,
  tenantId,
  tenantData,
  payload,
  providerSelection,
  billingProvider,
  createAsaasBillingQuote,
}) {
  try {
    const quoteResult = await createAsaasBillingQuote({
      firestore,
      tenantId,
      tenantData,
      payload,
      providerSelection,
    });

    if (!quoteResult.ok) {
      return {
        status: quoteResult.status,
        body: {
          error: quoteResult.error,
          message: quoteResult.message,
          billingProvider,
          providerSelectionSource: providerSelection.source,
          hasLinkedContract: providerSelection.hasLinkedContract,
        },
      };
    }

    return {
      status: quoteResult.status,
      body: quoteResult.body,
    };
  } catch (error) {
    return {
      status: 502,
      body: {
        error: 'provider_quote_failed',
        message: error instanceof Error ? error.message : String(error),
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }
}

function buildAsaasQuoteExecutionError(quoteResult) {
  const message = String(quoteResult?.body?.message ?? '').trim() ||
    'Falha ao criar quote no provider.';
  const error = new Error(message);
  error.code = String(quoteResult?.body?.error ?? '').trim() ||
    'provider_quote_failed';
  error.status = Number(quoteResult?.status ?? 502);
  error.body = quoteResult?.body || null;
  return error;
}

function mapQuoteOperationResultToHttpResponse({
  operationResult,
  billingProvider,
  providerSelection,
}) {
  if (operationResult.ok && operationResult.executed) {
    if (operationResult.responseSnapshot) {
      return operationResult.responseSnapshot;
    }

    return {
      status: 200,
      body: {
        ok: true,
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  if (operationResult.duplicate) {
    const responseSnapshot = operationResult.operation?.responseSnapshot;
    if (responseSnapshot && typeof responseSnapshot === 'object') {
      return responseSnapshot;
    }

    return {
      status: 200,
      body: {
        duplicate: true,
        message: 'Operacao de quote ja aplicada anteriormente.',
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  if (operationResult.retryable) {
    return {
      status: 409,
      body: {
        error: 'operation_in_progress',
        message:
          'Outra operacao de quote para este tenant esta em andamento. Tente novamente em instantes.',
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  if (operationResult.reason === 'request_hash_mismatch') {
    return {
      status: 409,
      body: {
        error: 'operation_id_conflict',
        message:
          'operationId ja foi utilizado com payload diferente. Gere um novo operationId para esta tentativa.',
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  if (
    operationResult.reason === 'execution_failed' &&
    Number.isFinite(Number(operationResult.errorStatus)) &&
    Number(operationResult.errorStatus) >= 400 &&
    operationResult.errorBody &&
    typeof operationResult.errorBody === 'object'
  ) {
    return {
      status: Number(operationResult.errorStatus),
      body: operationResult.errorBody,
    };
  }

  return {
    status: 502,
    body: {
      error: 'operation_execution_failed',
      message:
        operationResult.errorMessage ||
        'Falha ao executar operacao de quote com idempotencia.',
      billingProvider,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
    },
  };
}

async function writeTenantBillingQuoteAuditEvent({
  firestore,
  tenantId,
  authContext,
  payload,
  result,
  billingProvider,
  providerSelection,
  operationId,
  requestHash,
  reasonCode,
  timestampFromDate,
  logError,
}) {
  const statusCode = Number(result?.status ?? 0);
  const body = result?.body && typeof result.body === 'object' ? result.body : {};

  let action = 'billing_quote_created';
  if (String(reasonCode ?? '').trim() === 'permission_denied') {
    action = 'billing_quote_denied';
  } else if (body.duplicate === true) {
    action = 'billing_quote_replayed';
  } else if (statusCode >= 400 || String(body.error ?? '').trim()) {
    action = 'billing_quote_failed';
  }

  try {
    await firestore.collection('tenant_billing_audit').add({
      action,
      tenantId,
      actorUid: String(authContext?.uid ?? '').trim(),
      actorEmail: String(authContext?.email ?? '').trim(),
      actorLabel:
        String(authContext?.email ?? '').trim() ||
        String(authContext?.uid ?? '').trim(),
      details: {
        reasonCode: String(reasonCode ?? '').trim(),
        statusCode,
        error: String(body.error ?? '').trim(),
        message: String(body.message ?? '').trim(),
        billingProvider: String(billingProvider ?? '').trim(),
        providerSelectionSource: String(providerSelection?.source ?? '').trim(),
        hasLinkedContract: providerSelection?.hasLinkedContract === true,
        billingPlanKey: String(payload?.billingPlanKey ?? '').trim(),
        addonSeats: Number(payload?.addonSeats ?? 0),
        quoteId: String(body.quoteId ?? '').trim(),
        quoteStatus: String(body.quoteStatus ?? '').trim(),
        totalAmountCents: Number(body.totalAmountCents ?? 0),
        operationId: String(operationId ?? '').trim(),
        requestHash: String(requestHash ?? '').trim(),
      },
      createdAt: timestampFromDate(new Date()),
    });
  } catch (error) {
    logError('createBillingQuote audit persistence failed', {
      tenantId,
      billingProvider,
      operationId: String(operationId ?? '').trim(),
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

async function executeCreateBillingQuoteAction({
  firestore,
  payload,
  tenantId,
  authContext,
  assertTenantBillingActorPermission,
  readCheckoutApiConfig,
  resolveCheckoutApiProviderSelection,
  createAsaasBillingQuote,
  billingProviderStripe,
  billingProviderAsaas,
  executeTenantBillingOperationWithJournal =
    executeTenantBillingOperationWithJournalHelper,
  readCheckoutOperationIdFromPayload =
    readCheckoutOperationIdFromPayloadHelper,
  buildQuoteOperationRequestHash = buildQuoteOperationRequestHashHelper,
  timestampFromDate = (date) => date.toISOString(),
  logError = console.error,
}) {
  const actorPermission = await assertTenantBillingActorPermission({
    firestore,
    uid: authContext.uid,
    tenantId,
  });
  if (!actorPermission.allowed) {
    const result = {
      status: actorPermission.status,
      body: {
        error: actorPermission.error,
        message: actorPermission.message,
      },
    };

    await writeTenantBillingQuoteAuditEvent({
      firestore,
      tenantId,
      authContext,
      payload,
      result,
      billingProvider: '',
      providerSelection: {
        source: '',
        hasLinkedContract: false,
      },
      operationId: '',
      requestHash: '',
      reasonCode: 'permission_denied',
      timestampFromDate,
      logError,
    });

    return result;
  }

  const tenantDoc = await firestore.collection('tenants').doc(tenantId).get();
  if (!tenantDoc.exists) {
    const result = {
      status: 404,
      body: {
        error: 'tenant_not_found',
        message: 'Tenant nao encontrado.',
      },
    };

    await writeTenantBillingQuoteAuditEvent({
      firestore,
      tenantId,
      authContext,
      payload,
      result,
      billingProvider: '',
      providerSelection: {
        source: '',
        hasLinkedContract: false,
      },
      operationId: '',
      requestHash: '',
      reasonCode: 'tenant_not_found',
      timestampFromDate,
      logError,
    });

    return result;
  }

  const tenantData = tenantDoc.data() || {};
  const checkoutApiConfig = await readCheckoutApiConfig(firestore);
  const providerSelection = resolveCheckoutApiProviderSelection({
    payload,
    checkoutApiConfig,
    tenantData,
  });
  const billingProvider = providerSelection.provider;

  if (
    !providerSelection.hasLinkedContract &&
    !checkoutApiConfig.activeProviders.includes(billingProvider)
  ) {
    const result = {
      status: 409,
      body: {
        error: 'provider_disabled',
        message: `Provider ${billingProvider} nao esta ativo na API Checkout.`,
      },
    };

    await writeTenantBillingQuoteAuditEvent({
      firestore,
      tenantId,
      authContext,
      payload,
      result,
      billingProvider,
      providerSelection,
      operationId: '',
      requestHash: '',
      reasonCode: 'provider_disabled',
      timestampFromDate,
      logError,
    });

    return result;
  }

  if (billingProvider === billingProviderStripe) {
    const result = {
      status: 409,
      body: {
        error: 'provider_quote_not_supported',
        message:
          'Quote de billing ainda nao esta disponivel para Stripe neste endpoint unificado.',
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };

    await writeTenantBillingQuoteAuditEvent({
      firestore,
      tenantId,
      authContext,
      payload,
      result,
      billingProvider,
      providerSelection,
      operationId: '',
      requestHash: '',
      reasonCode: 'provider_quote_not_supported',
      timestampFromDate,
      logError,
    });

    return result;
  }

  if (billingProvider === billingProviderAsaas) {
    const operationId = readCheckoutOperationIdFromPayload(payload);

    if (!operationId) {
      const result = await executeAsaasQuoteDispatch({
        firestore,
        tenantId,
        tenantData,
        payload,
        providerSelection,
        billingProvider,
        createAsaasBillingQuote,
      });

      await writeTenantBillingQuoteAuditEvent({
        firestore,
        tenantId,
        authContext,
        payload,
        result,
        billingProvider,
        providerSelection,
        operationId: '',
        requestHash: '',
        reasonCode: 'asaas_quote_dispatch',
        timestampFromDate,
        logError,
      });

      return result;
    }

    const requestHash = buildQuoteOperationRequestHash({
      tenantId,
      payload,
      billingProvider,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
    });

    const operationResult = await executeTenantBillingOperationWithJournal({
      firestore,
      tenantId,
      operationId,
      operationType: 'create_quote',
      requestHash,
      lockOwnerToken: `${tenantId}:${String(authContext.uid ?? '').trim()}`,
      nowDate: new Date(),
      executeOperation: async () => {
        const quoteResult = await executeAsaasQuoteDispatch({
          firestore,
          tenantId,
          tenantData,
          payload,
          providerSelection,
          billingProvider,
          createAsaasBillingQuote,
        });

        if (Number(quoteResult.status) >= 400) {
          throw buildAsaasQuoteExecutionError(quoteResult);
        }

        return {
          status: 'applied',
          responseSnapshot: quoteResult,
        };
      },
    });

    const result = mapQuoteOperationResultToHttpResponse({
      operationResult,
      billingProvider,
      providerSelection,
    });

    await writeTenantBillingQuoteAuditEvent({
      firestore,
      tenantId,
      authContext,
      payload,
      result,
      billingProvider,
      providerSelection,
      operationId,
      requestHash,
      reasonCode: 'asaas_quote_journal',
      timestampFromDate,
      logError,
    });

    return result;
  }

  const result = {
    status: 400,
    body: {
      error: 'provider_not_supported',
      message: `Provider de billing nao suportado: ${billingProvider}.`,
      billingProvider,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
      activeProviders: checkoutApiConfig.activeProviders,
      preferredProvider: checkoutApiConfig.preferredProvider,
    },
  };

  await writeTenantBillingQuoteAuditEvent({
    firestore,
    tenantId,
    authContext,
    payload,
    result,
    billingProvider,
    providerSelection,
    operationId: '',
    requestHash: '',
    reasonCode: 'provider_not_supported',
    timestampFromDate,
    logError,
  });

  return result;
}

module.exports = {
  executeCreateBillingQuoteAction,
};