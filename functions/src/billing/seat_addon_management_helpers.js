const {
  executeTenantBillingOperationWithJournal:
    executeTenantBillingOperationWithJournalHelper,
} = require('./tenant_billing_operation_orchestrator_helpers');
const {
  buildSeatAddonOperationRequestHash: buildSeatAddonOperationRequestHashHelper,
  readCheckoutOperationIdFromPayload: readCheckoutOperationIdFromPayloadHelper,
} = require('./tenant_billing_operation_request_helpers');

async function executeStripeSeatAddonDispatch({
  firestore,
  tenantData,
  tenantId,
  billingPlanKey,
  addonSeatsDelta,
  authContext,
  loadBillingProviderRuntime,
  applyStripeSeatAddonDeltaToActiveSubscription,
  enforceTenantSeatAllowanceForTenant,
  billingProvider,
  providerSelection,
  logError,
}) {
  const runtime = await loadBillingProviderRuntime({
    firestore,
    providerKey: billingProvider,
    requireWebhookSecret: false,
  });
  if (!runtime.ok) {
    return {
      status: runtime.status,
      body: {
        error: runtime.error,
        message: runtime.message,
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  let updateResult;
  try {
    updateResult = await applyStripeSeatAddonDeltaToActiveSubscription({
      firestore,
      stripeClient: runtime.stripeClient,
      tenantId,
      tenantData,
      billingPlanKey,
      addonSeatsDelta,
      actorUid: authContext.uid,
    });
  } catch (error) {
    return {
      status: 502,
      body: {
        error: 'seat_addon_update_failed',
        message: error instanceof Error ? error.message : String(error),
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  if (!updateResult.applied) {
    return {
      status: updateResult.status || 409,
      body: {
        error: updateResult.error,
        message: updateResult.message,
        billingProvider,
        action: updateResult.action,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  let seatEnforcementSummary = null;
  let seatEnforcementError = '';
  try {
    seatEnforcementSummary = await enforceTenantSeatAllowanceForTenant({
      firestore,
      tenantId,
      nowDate: new Date(),
    });
  } catch (error) {
    seatEnforcementError =
      error instanceof Error ? error.message : String(error);
    logError('updateBillingSeatAddons seat enforcement failed', {
      tenantId,
      addonSeatsDelta,
      error: seatEnforcementError,
    });
  }

  return {
    status: 200,
    body: {
      tenantId,
      billingProvider,
      billingPlanKey: updateResult.billingPlanKey,
      addedSeats: updateResult.addedSeats,
      previousAddonSeats: updateResult.previousAddonSeats,
      currentAddonSeats: updateResult.currentAddonSeats,
      stripeSubscriptionId: updateResult.stripeSubscriptionId,
      stripeAddonPriceId: updateResult.stripeAddonPriceId,
      invoiceId: updateResult.invoiceId,
      invoiceStatus: updateResult.invoiceStatus,
      invoiceUrl: updateResult.invoiceUrl,
      message: updateResult.message,
      seatEnforcementSummary,
      seatEnforcementError,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
    },
  };
}

async function executeAsaasSeatAddonDispatch({
  firestore,
  tenantData,
  tenantId,
  billingPlanKey,
  addonSeatsDelta,
  authContext,
  loadBillingProviderRuntime,
  applyAsaasSeatAddonDeltaToActiveSubscription,
  enforceTenantSeatAllowanceForTenant,
  billingProvider,
  providerSelection,
  logError,
}) {
  const runtime = await loadBillingProviderRuntime({
    firestore,
    providerKey: billingProvider,
    requireWebhookSecret: false,
  });
  if (!runtime.ok) {
    return {
      status: runtime.status,
      body: {
        error: runtime.error,
        message: runtime.message,
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  let updateResult;
  try {
    updateResult = await applyAsaasSeatAddonDeltaToActiveSubscription({
      firestore,
      asaasRuntime: runtime,
      tenantId,
      tenantData,
      billingPlanKey,
      addonSeatsDelta,
      actorUid: authContext.uid,
    });
  } catch (error) {
    return {
      status: 502,
      body: {
        error: 'seat_addon_update_failed',
        message: error instanceof Error ? error.message : String(error),
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  if (!updateResult.applied) {
    return {
      status: updateResult.status || 409,
      body: {
        error: updateResult.error,
        message: updateResult.message,
        billingProvider,
        action: updateResult.action,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  let seatEnforcementSummary = null;
  let seatEnforcementError = '';
  try {
    seatEnforcementSummary = await enforceTenantSeatAllowanceForTenant({
      firestore,
      tenantId,
      nowDate: new Date(),
    });
  } catch (error) {
    seatEnforcementError =
      error instanceof Error ? error.message : String(error);
    logError('updateBillingSeatAddons seat enforcement failed', {
      tenantId,
      addonSeatsDelta,
      error: seatEnforcementError,
    });
  }

  return {
    status: 200,
    body: {
      tenantId,
      billingProvider,
      billingPlanKey: updateResult.billingPlanKey,
      addedSeats: updateResult.addedSeats,
      previousAddonSeats: updateResult.previousAddonSeats,
      currentAddonSeats: updateResult.currentAddonSeats,
      asaasSubscriptionId: updateResult.asaasSubscriptionId,
      asaasAddonPlanKey: updateResult.asaasAddonPlanKey,
      asaasSubscriptionValue: updateResult.asaasSubscriptionValue,
      asaasSubscriptionStatus: updateResult.asaasSubscriptionStatus,
      message: updateResult.message,
      seatEnforcementSummary,
      seatEnforcementError,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
    },
  };
}

function buildSeatAddonExecutionError(updateResult) {
  const message = String(updateResult?.body?.message ?? '').trim() ||
    'Falha ao atualizar seats extras.';
  const error = new Error(message);
  error.code = String(updateResult?.body?.error ?? '').trim() ||
    'seat_addon_update_failed';
  error.status = Number(updateResult?.status ?? 502);
  error.body = updateResult?.body || null;
  return error;
}

function mapSeatAddonOperationResultToHttpResponse({
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
        message: 'Operacao de seats extras ja aplicada anteriormente.',
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
          'Outra operacao de seats extras para este tenant esta em andamento. Tente novamente em instantes.',
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
        'Falha ao executar operacao de seats extras com idempotencia.',
      billingProvider,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
    },
  };
}

async function executeUpdateBillingSeatAddonsAction({
  firestore,
  payload,
  tenantId,
  billingPlanKey,
  addonSeatsDelta,
  authContext,
  assertTenantBillingActorPermission,
  readCheckoutApiConfig,
  resolveCheckoutApiProviderSelection,
  loadBillingProviderRuntime,
  applyStripeSeatAddonDeltaToActiveSubscription,
  applyAsaasSeatAddonDeltaToActiveSubscription,
  enforceTenantSeatAllowanceForTenant,
  billingProviderStripe,
  billingProviderAsaas,
  logError = console.error,
  executeTenantBillingOperationWithJournal =
    executeTenantBillingOperationWithJournalHelper,
  readCheckoutOperationIdFromPayload =
    readCheckoutOperationIdFromPayloadHelper,
  buildSeatAddonOperationRequestHash =
    buildSeatAddonOperationRequestHashHelper,
}) {
  const actorPermission = await assertTenantBillingActorPermission({
    firestore,
    uid: authContext.uid,
    tenantId,
  });
  if (!actorPermission.allowed) {
    return {
      status: actorPermission.status,
      body: {
        error: actorPermission.error,
        message: actorPermission.message,
      },
    };
  }

  const tenantRef = firestore.collection('tenants').doc(tenantId);
  const tenantDoc = await tenantRef.get();
  if (!tenantDoc.exists) {
    return {
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
      status: 409,
      body: {
        error: 'provider_disabled',
        message: `Provider ${billingProvider} nao esta ativo na API Checkout.`,
      },
    };
  }

  if (
    billingProvider !== billingProviderStripe &&
    billingProvider !== billingProviderAsaas
  ) {
    return {
      status: 409,
      body: {
        error: 'seat_addon_update_not_supported_for_provider',
        message:
          'Ajuste self-service de seats extras nao esta disponivel para este provider.',
        billingProvider,
        providerSelectionSource: providerSelection.source,
        hasLinkedContract: providerSelection.hasLinkedContract,
      },
    };
  }

  const executeSeatAddonDispatch = billingProvider === billingProviderAsaas
    ? () => executeAsaasSeatAddonDispatch({
        firestore,
        tenantData,
        tenantId,
        billingPlanKey,
        addonSeatsDelta,
        authContext,
        loadBillingProviderRuntime,
        applyAsaasSeatAddonDeltaToActiveSubscription,
        enforceTenantSeatAllowanceForTenant,
        billingProvider,
        providerSelection,
        logError,
      })
    : () => executeStripeSeatAddonDispatch({
        firestore,
        tenantData,
        tenantId,
        billingPlanKey,
        addonSeatsDelta,
        authContext,
        loadBillingProviderRuntime,
        applyStripeSeatAddonDeltaToActiveSubscription,
        enforceTenantSeatAllowanceForTenant,
        billingProvider,
        providerSelection,
        logError,
      });

  const operationId = readCheckoutOperationIdFromPayload(payload);
  if (!operationId) {
    return executeSeatAddonDispatch();
  }

  const requestHash = buildSeatAddonOperationRequestHash({
    tenantId,
    billingPlanKey,
    addonSeatsDelta,
    payload,
    billingProvider,
    providerSelectionSource: providerSelection.source,
    hasLinkedContract: providerSelection.hasLinkedContract,
  });

  const operationResult = await executeTenantBillingOperationWithJournal({
    firestore,
    tenantId,
    operationId,
    operationType: 'change_seats',
    requestHash,
    lockOwnerToken: `${tenantId}:${String(authContext.uid ?? '').trim()}`,
    nowDate: new Date(),
    executeOperation: async () => {
      const updateResult = await executeSeatAddonDispatch();

      if (Number(updateResult.status) >= 400) {
        throw buildSeatAddonExecutionError(updateResult);
      }

      return {
        status: 'applied',
        responseSnapshot: updateResult,
      };
    },
  });

  return mapSeatAddonOperationResultToHttpResponse({
    operationResult,
    billingProvider,
    providerSelection,
  });
}

module.exports = {
  executeUpdateBillingSeatAddonsAction,
};
