const BILLING_PROVIDER_STRIPE = 'stripe';
const BILLING_PROVIDER_ASAAS = 'asaas';
const BILLING_PROVIDER_DEFAULT = BILLING_PROVIDER_STRIPE;

function normalizeBillingProviderKey(rawValue) {
  const normalized = String(rawValue ?? '').trim().toLowerCase();
  if (!normalized) {
    return BILLING_PROVIDER_DEFAULT;
  }
  if (normalized === BILLING_PROVIDER_STRIPE) {
    return BILLING_PROVIDER_STRIPE;
  }
  if (normalized === BILLING_PROVIDER_ASAAS) {
    return BILLING_PROVIDER_ASAAS;
  }
  return normalized;
}

function resolveTenantLinkedBillingProvider(tenantData) {
  const data = tenantData && typeof tenantData === 'object' ? tenantData : {};

  const explicitContractProvider = normalizeBillingProviderKey(
    data.billingContractProvider,
  );
  if (
    explicitContractProvider === BILLING_PROVIDER_STRIPE ||
    explicitContractProvider === BILLING_PROVIDER_ASAAS
  ) {
    return explicitContractProvider;
  }

  const stripeSubscriptionId = String(data.stripeSubscriptionId ?? '').trim();
  const asaasSubscriptionId = String(data.asaasSubscriptionId ?? '').trim();
  const hasStripeLink = Boolean(stripeSubscriptionId);
  const hasAsaasLink = Boolean(asaasSubscriptionId);

  if (hasStripeLink && !hasAsaasLink) {
    return BILLING_PROVIDER_STRIPE;
  }
  if (hasAsaasLink && !hasStripeLink) {
    return BILLING_PROVIDER_ASAAS;
  }

  if (hasStripeLink && hasAsaasLink) {
    const providerFromTenant = normalizeBillingProviderKey(data.billingProvider);
    if (
      providerFromTenant === BILLING_PROVIDER_STRIPE ||
      providerFromTenant === BILLING_PROVIDER_ASAAS
    ) {
      return providerFromTenant;
    }
  }

  return '';
}

function resolveTenantBillingProviderKey({ tenantData, providerHint }) {
  const rawHint = String(providerHint ?? '').trim();
  const hint = rawHint ? normalizeBillingProviderKey(rawHint) : '';
  if (hint === BILLING_PROVIDER_STRIPE || hint === BILLING_PROVIDER_ASAAS) {
    return hint;
  }

  const linkedProvider = resolveTenantLinkedBillingProvider(tenantData);
  if (linkedProvider) {
    return linkedProvider;
  }

  const tenantProvider = normalizeBillingProviderKey(
    tenantData?.billingProvider ?? tenantData?.billingGateway,
  );
  if (
    tenantProvider === BILLING_PROVIDER_STRIPE ||
    tenantProvider === BILLING_PROVIDER_ASAAS
  ) {
    return tenantProvider;
  }

  return BILLING_PROVIDER_DEFAULT;
}

function resolveCheckoutApiProviderSelection({
  payload,
  checkoutApiConfig,
  tenantData,
}) {
  const linkedProvider = resolveTenantLinkedBillingProvider(tenantData);
  if (linkedProvider) {
    return {
      provider: linkedProvider,
      hasLinkedContract: true,
      source: 'existing_contract',
    };
  }

  const rawProvider = String(payload?.provider ?? '').trim().toLowerCase();
  const requestedProvider = rawProvider
    ? normalizeBillingProviderKey(rawProvider)
    : '';

  if (
    requestedProvider &&
    checkoutApiConfig.activeProviders.includes(requestedProvider)
  ) {
    return {
      provider: requestedProvider,
      hasLinkedContract: false,
      source: 'payload_provider',
    };
  }

  if (checkoutApiConfig.activeProviders.includes(checkoutApiConfig.preferredProvider)) {
    return {
      provider: checkoutApiConfig.preferredProvider,
      hasLinkedContract: false,
      source: 'preferred_provider',
    };
  }

  return {
    provider: checkoutApiConfig.activeProviders[0] || BILLING_PROVIDER_DEFAULT,
    hasLinkedContract: false,
    source: 'first_active_provider',
  };
}

module.exports = {
  normalizeBillingProviderKey,
  resolveCheckoutApiProviderSelection,
  resolveTenantBillingProviderKey,
  resolveTenantLinkedBillingProvider,
};
