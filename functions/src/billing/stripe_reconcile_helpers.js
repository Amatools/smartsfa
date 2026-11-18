async function reconcileTenantStripeState({
  firestore,
  stripeClient,
  tenantId,
  billingProviderStripe,
  readStripeSubscriptionPriceId,
  resolveStripePlanMappingByPriceId,
  buildTenantPatchFromStripeSubscription,
  readStripeSubscriptionPeriodFromInvoices,
}) {
  const tenantRef = firestore.collection('tenants').doc(tenantId);
  const tenantDoc = await tenantRef.get();
  if (!tenantDoc.exists) {
    throw new Error('Tenant nao encontrado para reconciliacao.');
  }

  const tenantData = tenantDoc.data() || {};
  const previousBillingStatus = String(tenantData.billingStatus ?? '').trim();
  const stripeCustomerId = String(tenantData.stripeCustomerId ?? '').trim();
  let stripeSubscriptionId = String(tenantData.stripeSubscriptionId ?? '').trim();

  if (!stripeCustomerId && !stripeSubscriptionId) {
    throw new Error('Tenant sem stripeCustomerId/stripeSubscriptionId para reconciliar.');
  }

  let subscription = null;
  if (stripeSubscriptionId) {
    try {
      subscription = await stripeClient.subscriptions.retrieve(stripeSubscriptionId, {
        expand: ['items.data.price'],
      });
    } catch (_) {
      subscription = null;
    }
  }

  if (!subscription && stripeCustomerId) {
    const list = await stripeClient.subscriptions.list({
      customer: stripeCustomerId,
      status: 'all',
      limit: 1,
      expand: ['data.items.data.price'],
    });
    if (Array.isArray(list.data) && list.data.length > 0) {
      subscription = list.data[0];
      stripeSubscriptionId = String(subscription.id ?? '').trim();
    }
  }

  let patch;
  if (subscription) {
    const priceId = readStripeSubscriptionPriceId(subscription);
    const priceMapping = await resolveStripePlanMappingByPriceId({
      firestore,
      stripePriceId: priceId,
    });
    const mappedPlanKey = priceMapping?.billingPlanKey ?? '';
    patch = buildTenantPatchFromStripeSubscription({
      subscription,
      billingPlanKey: mappedPlanKey || tenantData.billingPlanKey,
    });

    if (!patch.billingCurrentPeriodStartAt || !patch.billingCurrentPeriodEndAt) {
      const invoicePeriodBounds = await readStripeSubscriptionPeriodFromInvoices({
        stripeClient,
        subscriptionId: stripeSubscriptionId,
      });
      if (invoicePeriodBounds.startIso && !patch.billingCurrentPeriodStartAt) {
        patch.billingCurrentPeriodStartAt = invoicePeriodBounds.startIso;
      }
      if (invoicePeriodBounds.endIso && !patch.billingCurrentPeriodEndAt) {
        patch.billingCurrentPeriodEndAt = invoicePeriodBounds.endIso;
      }
    }
  } else {
    const nowIso = new Date().toISOString();
    patch = {
      billingProvider: billingProviderStripe,
      billingContractProvider: billingProviderStripe,
      billingContractLinkedAt: nowIso,
      stripeCustomerId,
      stripeSubscriptionId,
      billingStatus: 'canceled',
      billingSuspendedAt: nowIso,
      billingUpdatedAt: nowIso,
    };
  }

  await tenantRef.set(patch, { merge: true });

  return {
    stripeSubscriptionId: String(patch.stripeSubscriptionId ?? '').trim(),
    previousBillingStatus,
    currentBillingStatus: String(patch.billingStatus ?? '').trim(),
    updatedAt: String(patch.billingUpdatedAt ?? '').trim(),
  };
}

module.exports = {
  reconcileTenantStripeState,
};
