const { extractAsaasReferenceInfo } = require('./asaas_webhook_helpers');

async function resolveTenantIdFromAsaasReferences({
  firestore,
  eventPayload,
}) {
  const payment = eventPayload?.payment ?? {};
  const subscription = eventPayload?.subscription ?? {};
  const checkout = eventPayload?.checkout ?? {};
  const invoice = eventPayload?.invoice ?? {};

  const referenceInfos = [
    extractAsaasReferenceInfo(payment?.externalReference),
    extractAsaasReferenceInfo(subscription?.externalReference),
    extractAsaasReferenceInfo(checkout?.externalReference),
  ];

  for (const info of referenceInfos) {
    const candidateTenantId = String(info?.tenantId ?? '').trim();
    if (!candidateTenantId) {
      continue;
    }
    const tenantDoc = await firestore.collection('tenants').doc(candidateTenantId).get();
    if (tenantDoc.exists) {
      return candidateTenantId;
    }
  }

  const subscriptionId = String(
    payment?.subscription ?? subscription?.id ?? checkout?.subscription?.id ?? '',
  ).trim();
  if (subscriptionId) {
    const snapshot = await firestore
      .collection('tenants')
      .where('asaasSubscriptionId', '==', subscriptionId)
      .limit(1)
      .get();
    if (!snapshot.empty) {
      return snapshot.docs[0].id;
    }
  }

  const customerId = String(
    payment?.customer ??
      subscription?.customer ??
      checkout?.customer ??
      invoice?.customer ??
      '',
  ).trim();
  if (customerId) {
    const snapshot = await firestore
      .collection('tenants')
      .where('asaasCustomerId', '==', customerId)
      .limit(1)
      .get();
    if (!snapshot.empty) {
      return snapshot.docs[0].id;
    }
  }

  const checkoutId = String(checkout?.id ?? '').trim();
  if (checkoutId) {
    const snapshot = await firestore
      .collection('tenants')
      .where('asaasCheckoutId', '==', checkoutId)
      .limit(1)
      .get();
    if (!snapshot.empty) {
      return snapshot.docs[0].id;
    }
  }

  const paymentId = String(payment?.id ?? '').trim();
  if (paymentId) {
    const snapshot = await firestore
      .collection('tenants')
      .where('asaasPaymentId', '==', paymentId)
      .limit(1)
      .get();
    if (!snapshot.empty) {
      return snapshot.docs[0].id;
    }
  }

  const invoicePaymentId = String(invoice?.payment ?? '').trim();
  if (invoicePaymentId) {
    const snapshot = await firestore
      .collection('tenants')
      .where('asaasPaymentId', '==', invoicePaymentId)
      .limit(1)
      .get();
    if (!snapshot.empty) {
      return snapshot.docs[0].id;
    }
  }

  return '';
}

async function resolveTenantIdFromStripeReferences({
  firestore,
  explicitTenantId,
  stripeCustomerId,
  stripeSubscriptionId,
}) {
  const explicit = String(explicitTenantId ?? '').trim();
  if (explicit) {
    return explicit;
  }

  const subscriptionId = String(stripeSubscriptionId ?? '').trim();
  if (subscriptionId) {
    const subscriptionSnapshot = await firestore
      .collection('tenants')
      .where('stripeSubscriptionId', '==', subscriptionId)
      .limit(1)
      .get();
    if (!subscriptionSnapshot.empty) {
      return subscriptionSnapshot.docs[0].id;
    }
  }

  const customerId = String(stripeCustomerId ?? '').trim();
  if (customerId) {
    const customerSnapshot = await firestore
      .collection('tenants')
      .where('stripeCustomerId', '==', customerId)
      .limit(1)
      .get();
    if (!customerSnapshot.empty) {
      return customerSnapshot.docs[0].id;
    }
  }

  return '';
}

module.exports = {
  resolveTenantIdFromAsaasReferences,
  resolveTenantIdFromStripeReferences,
};
