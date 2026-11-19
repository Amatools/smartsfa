const {
  executeTenantBillingOperationWithJournal:
    executeTenantBillingOperationWithJournalHelper,
} = require('./tenant_billing_operation_orchestrator_helpers');
const {
  buildCheckoutOperationRequestHash: buildCheckoutOperationRequestHashHelper,
  readCheckoutOperationIdFromPayload: readCheckoutOperationIdFromPayloadHelper,
} = require('./tenant_billing_operation_request_helpers');

async function executeAsaasCheckoutDispatch({
  firestore,
  tenantId,
  tenantData,
  payload,
  providerSelection,
  billingProvider,
  createAsaasCheckoutSession,
}) {
  try {
    const checkoutResult = await createAsaasCheckoutSession({
      firestore,
      tenantId,
      tenantData,
      payload,
      providerSelection,
    });

    if (!checkoutResult.ok) {
      return {
        handledByProxy: false,
        status: checkoutResult.status,
        body: {
          error: checkoutResult.error,
          message: checkoutResult.message,
          billingProvider,
          providerSelectionSource: providerSelection.source,
          hasLinkedContract: providerSelection.hasLinkedContract,
        },
      };
    }

    return {
      handledByProxy: false,
      status: checkoutResult.status,
      body: checkoutResult.body,
    };
  } catch (error) {
    return {
      handledByProxy: false,
      status: 502,
      body: {
        error: 'provider_checkout_failed',
        message: error instanceof Error ? error.message : String(error),
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }
}

function buildAsaasCheckoutExecutionError(checkoutResult) {
  const message = String(checkoutResult?.body?.message ?? '').trim() ||
    'Falha ao criar checkout no provider.';
  const error = new Error(message);
  error.code = String(checkoutResult?.body?.error ?? '').trim() ||
    'provider_checkout_failed';
  error.status = Number(checkoutResult?.status ?? 502);
  error.body = checkoutResult?.body || null;
  return error;
}

function mapCheckoutOperationResultToHttpResponse({
  operationResult,
  billingProvider,
  providerSelection,
}) {
  if (operationResult.ok && operationResult.executed) {
    if (operationResult.responseSnapshot) {
      return operationResult.responseSnapshot;
    }

    return {
      handledByProxy: false,
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
      handledByProxy: false,
      status: 200,
      body: {
        duplicate: true,
        message: 'Operacao de checkout ja aplicada anteriormente.',
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  if (operationResult.retryable) {
    return {
      handledByProxy: false,
      status: 409,
      body: {
        error: 'operation_in_progress',
        message:
          'Outra operacao de checkout para este tenant esta em andamento. Tente novamente em instantes.',
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  if (operationResult.reason === 'request_hash_mismatch') {
    return {
      handledByProxy: false,
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
      handledByProxy: false,
      status: Number(operationResult.errorStatus),
      body: operationResult.errorBody,
    };
  }

  return {
    handledByProxy: false,
    status: 502,
    body: {
      error: 'operation_execution_failed',
      message:
        operationResult.errorMessage ||
        'Falha ao executar operacao de checkout com idempotencia.',
      billingProvider,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
    },
  };
}

async function executeCreateBillingCheckoutSessionAction({
  firestore,
  request,
  response,
  payload,
  tenantId,
  authContext,
  assertTenantBillingActorPermission,
  readCheckoutApiConfig,
  resolveCheckoutApiProviderSelection,
  proxyBillingRequestToFunction,
  stripeCheckoutFunctionUrl,
  createAsaasCheckoutSession,
  billingProviderStripe,
  billingProviderAsaas,
  executeTenantBillingOperationWithJournal =
    executeTenantBillingOperationWithJournalHelper,
  readCheckoutOperationIdFromPayload =
    readCheckoutOperationIdFromPayloadHelper,
  buildCheckoutOperationRequestHash = buildCheckoutOperationRequestHashHelper,
}) {
  const actorPermission = await assertTenantBillingActorPermission({
    firestore,
    uid: authContext.uid,
    tenantId,
  });
  if (!actorPermission.allowed) {
    return {
      handledByProxy: false,
      status: actorPermission.status,
      body: {
        error: actorPermission.error,
        message: actorPermission.message,
      },
    };
  }

  const tenantDoc = await firestore.collection('tenants').doc(tenantId).get();
  if (!tenantDoc.exists) {
    return {
      handledByProxy: false,
      status: 404,
      body: {
        error: 'tenant_not_found',
        message: 'Tenant nao encontrado.',
      },
    };
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
    return {
      handledByProxy: false,
      status: 409,
      body: {
        error: 'provider_disabled',
        message: `Provider ${billingProvider} nao esta ativo na API Checkout.`,
      },
    };
  }

  if (billingProvider === billingProviderStripe) {
    await proxyBillingRequestToFunction({
      request,
      response,
      targetUrl: stripeCheckoutFunctionUrl,
      method: 'POST',
      extraResponseFields: {
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    });

    return {
      handledByProxy: true,
      status: 200,
      body: null,
    };
  }

  if (billingProvider === billingProviderAsaas) {
    const operationId = readCheckoutOperationIdFromPayload(payload);
    if (!operationId) {
      return executeAsaasCheckoutDispatch({
        firestore,
        tenantId,
        tenantData,
        payload,
        providerSelection,
        billingProvider,
        createAsaasCheckoutSession,
      });
    }

    const requestHash = buildCheckoutOperationRequestHash({
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
      operationType: 'open_checkout',
      requestHash,
      lockOwnerToken: `${tenantId}:${String(authContext.uid ?? '').trim()}`,
      nowDate: new Date(),
      executeOperation: async () => {
        const checkoutResult = await executeAsaasCheckoutDispatch({
          firestore,
          tenantId,
          tenantData,
          payload,
          providerSelection,
          billingProvider,
          createAsaasCheckoutSession,
        });

        if (Number(checkoutResult.status) >= 400) {
          throw buildAsaasCheckoutExecutionError(checkoutResult);
        }

        return {
          status: 'applied',
          responseSnapshot: checkoutResult,
        };
      },
    });

    return mapCheckoutOperationResultToHttpResponse({
      operationResult,
      billingProvider,
      providerSelection,
    });
  }

  return {
    handledByProxy: false,
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
}

module.exports = {
  executeCreateBillingCheckoutSessionAction,
};
