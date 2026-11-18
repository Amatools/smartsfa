async function reconcileTenantStripePeriodIfMissing({
  firestore,
  stripeClient,
  tenantId,
  source,
  reconcileTenantBillingState,
  stripeProviderKey,
}) {
  if (!stripeClient) {
    return;
  }

  const tenantRef = firestore.collection('tenants').doc(tenantId);
  const tenantDoc = await tenantRef.get();
  if (!tenantDoc.exists) {
    return;
  }

  const tenantData = tenantDoc.data() || {};
  const billingStatus = String(tenantData.billingStatus ?? '').trim().toLowerCase();
  const stripeCustomerId = String(tenantData.stripeCustomerId ?? '').trim();
  const stripeSubscriptionId = String(tenantData.stripeSubscriptionId ?? '').trim();
  const periodStart = String(tenantData.billingCurrentPeriodStartAt ?? '').trim();
  const periodEnd = String(tenantData.billingCurrentPeriodEndAt ?? '').trim();

  const needsPeriod = !periodStart || !periodEnd;
  const statusAllowsReconcile =
    billingStatus === 'active' ||
    billingStatus === 'trial' ||
    billingStatus === 'past_due';
  const hasStripeReference = Boolean(stripeCustomerId || stripeSubscriptionId);

  if (!statusAllowsReconcile || !hasStripeReference || !needsPeriod) {
    return;
  }

  try {
    await reconcileTenantBillingState({
      firestore,
      providerKey: stripeProviderKey,
      stripeClient,
      tenantId,
    });
  } catch (error) {
    console.error('stripe period reconcile fallback failed', {
      tenantId,
      source,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

module.exports = {
  reconcileTenantStripePeriodIfMissing,
};
