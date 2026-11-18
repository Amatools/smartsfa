const { normalizeBillingPlanKey } = require('./shared_helpers');
const {
  extractAsaasReferenceInfo,
  mapAsaasCycleToBillingCycle,
  mapAsaasSubscriptionStatusToBillingStatus,
  mapBillingStatusToAccountState,
  normalizeAsaasDateToIso,
} = require('./asaas_webhook_helpers');

const BILLING_PROVIDER_ASAAS = 'asaas';

function mapAsaasEventToBillingStatus({
  eventType,
  eventPayload,
  currentBillingStatus,
}) {
  const type = String(eventType ?? '').trim().toUpperCase();
  const normalizedCurrent = String(currentBillingStatus ?? '').trim().toLowerCase();

  if (
    type === 'PAYMENT_RECEIVED' ||
    type === 'PAYMENT_CONFIRMED' ||
    type === 'PAYMENT_RESTORED' ||
    type === 'CHECKOUT_PAID'
  ) {
    return 'active';
  }

  if (
    type === 'PAYMENT_OVERDUE' ||
    type === 'PAYMENT_CHARGEBACK_REQUESTED' ||
    type === 'PAYMENT_CHARGEBACK_DISPUTE'
  ) {
    return 'past_due';
  }

  if (type === 'SUBSCRIPTION_CREATED' || type === 'SUBSCRIPTION_UPDATED') {
    const subscriptionStatus = mapAsaasSubscriptionStatusToBillingStatus(
      eventPayload?.subscription?.status,
    );
    return subscriptionStatus || 'active';
  }

  if (type === 'SUBSCRIPTION_INACTIVATED') {
    return 'suspended';
  }

  if (type === 'SUBSCRIPTION_DELETED' || type === 'PAYMENT_DELETED') {
    return 'canceled';
  }

  if (type === 'CHECKOUT_EXPIRED' || type === 'CHECKOUT_CANCELED') {
    if (
      normalizedCurrent === 'active' ||
      normalizedCurrent === 'trial' ||
      normalizedCurrent === 'past_due' ||
      normalizedCurrent === 'grace'
    ) {
      return '';
    }
    return 'no_plan';
  }

  return '';
}

function buildTenantPatchFromAsaasEvent({
  eventPayload,
  eventType,
  currentTenantData,
  webhookEnvironment,
}) {
  const payment = eventPayload?.payment ?? {};
  const subscription = eventPayload?.subscription ?? {};
  const checkout = eventPayload?.checkout ?? {};
  const invoice = eventPayload?.invoice ?? {};
  const nowIso = new Date().toISOString();

  const subscriptionRefInfo = extractAsaasReferenceInfo(
    subscription?.externalReference,
  );
  const paymentRefInfo = extractAsaasReferenceInfo(payment?.externalReference);
  const checkoutRefInfo = extractAsaasReferenceInfo(checkout?.externalReference);

  const billingPlanKey = normalizeBillingPlanKey(
    subscriptionRefInfo.billingPlanKey ||
      paymentRefInfo.billingPlanKey ||
      checkoutRefInfo.billingPlanKey,
  );

  const billingStatus = mapAsaasEventToBillingStatus({
    eventType,
    eventPayload,
    currentBillingStatus: currentTenantData?.billingStatus,
  });

  const patch = {
    billingProvider: BILLING_PROVIDER_ASAAS,
    billingUpdatedAt: nowIso,
    asaasLastEventId: String(eventPayload?.id ?? '').trim(),
    asaasLastEventType: eventType,
    asaasWebhookEnvironment: webhookEnvironment,
  };

  const asaasCustomerId = String(
    payment?.customer ?? subscription?.customer ?? checkout?.customer ?? '',
  ).trim();
  if (asaasCustomerId) {
    patch.asaasCustomerId = asaasCustomerId;
  }

  const asaasSubscriptionId = String(
    payment?.subscription ?? subscription?.id ?? checkout?.subscription?.id ?? '',
  ).trim();
  if (asaasSubscriptionId) {
    patch.asaasSubscriptionId = asaasSubscriptionId;
    patch.billingContractProvider = BILLING_PROVIDER_ASAAS;
    patch.billingContractLinkedAt = nowIso;
  }

  const asaasCheckoutId = String(checkout?.id ?? '').trim();
  if (asaasCheckoutId) {
    patch.asaasCheckoutId = asaasCheckoutId;
  }

  const asaasPaymentId = String(payment?.id ?? '').trim();
  if (asaasPaymentId) {
    patch.asaasPaymentId = asaasPaymentId;
  }

  const billingType = String(payment?.billingType ?? subscription?.billingType ?? '').trim();
  if (billingType) {
    patch.asaasBillingType = billingType;
  }

  const invoiceUrl = String(payment?.invoiceUrl ?? '').trim();
  if (invoiceUrl) {
    patch.asaasInvoiceUrl = invoiceUrl;
  }
  const bankSlipUrl = String(payment?.bankSlipUrl ?? '').trim();
  if (bankSlipUrl) {
    patch.asaasBankSlipUrl = bankSlipUrl;
  }
  const invoiceNumber = String(payment?.invoiceNumber ?? invoice?.number ?? '').trim();
  if (invoiceNumber) {
    patch.asaasInvoiceNumber = invoiceNumber;
  }
  const invoiceStatus = String(invoice?.status ?? '').trim();
  if (invoiceStatus) {
    patch.asaasInvoiceStatus = invoiceStatus;
  }

  const billingCycle = mapAsaasCycleToBillingCycle(subscription?.cycle);
  if (billingCycle) {
    patch.billingCycle = billingCycle;
  }

  const periodEndIso = normalizeAsaasDateToIso(
    subscription?.nextDueDate || payment?.dueDate,
  );
  if (periodEndIso) {
    patch.billingCurrentPeriodEndAt = periodEndIso;
  }

  const hasCurrentPeriodStart = String(
    currentTenantData?.billingCurrentPeriodStartAt ?? '',
  ).trim();
  const periodStartIso = normalizeAsaasDateToIso(
    payment?.dateCreated || subscription?.dateCreated || eventPayload?.dateCreated,
  );
  if (periodStartIso && !hasCurrentPeriodStart) {
    patch.billingCurrentPeriodStartAt = periodStartIso;
  }

  if (billingPlanKey) {
    patch.billingPlanKey = billingPlanKey;
  }

  if (billingStatus) {
    patch.billingStatus = billingStatus;
    patch.billingAccountState = mapBillingStatusToAccountState(billingStatus);
  }

  if (billingStatus === 'past_due') {
    const currentPastDue = String(currentTenantData?.billingPastDueSinceAt ?? '').trim();
    patch.billingPastDueSinceAt = currentPastDue || nowIso;
  }

  if (billingStatus === 'active' || billingStatus === 'trial') {
    patch.billingPastDueSinceAt = '';
    patch.billingSuspendedAt = '';
  }

  if (billingStatus === 'suspended' || billingStatus === 'canceled') {
    patch.billingSuspendedAt = nowIso;
  }

  return patch;
}

module.exports = {
  buildTenantPatchFromAsaasEvent,
  mapAsaasEventToBillingStatus,
};
