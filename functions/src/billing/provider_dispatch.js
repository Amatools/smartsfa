const { normalizeBillingProviderKey } = require('./provider_resolution');

const BILLING_PROVIDER_STRIPE = 'stripe';
const BILLING_PROVIDER_ASAAS = 'asaas';

async function processBillingWebhookEvent({
  firestore,
  providerKey,
  event,
  enabledEvents,
  stripeClient,
  asaasRuntime,
  processStripeWebhookEvent,
  processAsaasWebhookEvent,
}) {
  const normalizedProvider = normalizeBillingProviderKey(providerKey);
  if (normalizedProvider === BILLING_PROVIDER_STRIPE) {
    return processStripeWebhookEvent({
      firestore,
      event,
      enabledEvents,
      stripeClient,
    });
  }

  if (normalizedProvider === BILLING_PROVIDER_ASAAS) {
    return processAsaasWebhookEvent({
      firestore,
      event,
      enabledEvents,
      asaasRuntime,
    });
  }

  throw new Error(
    `Webhook nao implementado para provider ${normalizedProvider}.`,
  );
}

async function reconcileTenantBillingState({
  firestore,
  providerKey,
  tenantId,
  stripeClient,
  asaasRuntime,
  reconcileTenantStripeState,
  reconcileTenantAsaasState,
}) {
  const normalizedProvider = normalizeBillingProviderKey(providerKey);
  if (normalizedProvider === BILLING_PROVIDER_STRIPE) {
    return reconcileTenantStripeState({
      firestore,
      stripeClient,
      tenantId,
    });
  }

  if (normalizedProvider === BILLING_PROVIDER_ASAAS) {
    return reconcileTenantAsaasState({
      firestore,
      asaasRuntime,
      tenantId,
    });
  }

  throw new Error(
    `Reconciliacao nao implementada para provider ${normalizedProvider}.`,
  );
}

async function applyTenantBillingActionToProvider({
  providerKey,
  stripeClient,
  asaasRuntime,
  tenantId,
  tenantData,
  action,
  reason,
  actorUid,
  applyTenantBillingActionToStripe,
  applyTenantBillingActionToAsaas,
}) {
  const normalizedProvider = normalizeBillingProviderKey(providerKey);
  if (normalizedProvider === BILLING_PROVIDER_STRIPE) {
    return applyTenantBillingActionToStripe({
      stripeClient,
      tenantId,
      tenantData,
      action,
      reason,
      actorUid,
    });
  }

  if (normalizedProvider === BILLING_PROVIDER_ASAAS) {
    return applyTenantBillingActionToAsaas({
      asaasRuntime,
      tenantId,
      tenantData,
      action,
      reason,
      actorUid,
    });
  }

  return {
    applied: false,
    action: 'provider_not_implemented',
    message: `Acao de billing ainda nao implementada para provider ${normalizedProvider}.`,
  };
}

async function applyTenantBillingSelfServiceActionToProvider({
  providerKey,
  asaasRuntime,
  tenantData,
  action,
  applyTenantBillingSelfServiceActionToAsaas,
}) {
  const normalizedProvider = normalizeBillingProviderKey(providerKey);
  if (normalizedProvider === BILLING_PROVIDER_ASAAS) {
    return applyTenantBillingSelfServiceActionToAsaas({
      asaasRuntime,
      tenantData,
      action,
    });
  }

  return {
    applied: false,
    action: 'provider_not_supported',
    message:
      `Acoes self-service de billing nao suportadas para provider ${normalizedProvider}.`,
    billingStatus: '',
  };
}

module.exports = {
  applyTenantBillingActionToProvider,
  applyTenantBillingSelfServiceActionToProvider,
  processBillingWebhookEvent,
  reconcileTenantBillingState,
};
