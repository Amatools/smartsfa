const { normalizeBillingPlanKey } = require('./shared_helpers');

function buildStripePlanMappingFromDocData(data, fallbackPlanKey = '') {
  const priceId = String(data.stripePriceId ?? '').trim();
  if (!priceId || data.active === false) {
    return null;
  }

  const includedSeatsInput = Number(data.includedSeats ?? 0);
  const includedSeats = Number.isFinite(includedSeatsInput)
    ? Math.max(0, Math.floor(includedSeatsInput))
    : 0;

  return {
    billingPlanKey: normalizeBillingPlanKey(data.billingPlanKey ?? fallbackPlanKey),
    planDisplayName: String(data.planDisplayName ?? '').trim(),
    planDisplayAmount: String(data.planDisplayAmount ?? '').trim(),
    stripeProductId: String(data.stripeProductId ?? '').trim(),
    stripeProductName: String(data.stripeProductName ?? '').trim(),
    stripePriceId: priceId,
    stripePriceNickname: String(data.stripePriceNickname ?? '').trim(),
    stripeUnitAmount: Number(data.stripeUnitAmount ?? 0),
    stripeCurrency: String(data.stripeCurrency ?? '').trim().toLowerCase(),
    stripeRecurringInterval: String(data.stripeRecurringInterval ?? '')
      .trim()
      .toLowerCase(),
    stripeRecurringIntervalCount: Number(data.stripeRecurringIntervalCount ?? 0),
    mappingType: String(data.mappingType ?? 'base').trim().toLowerCase(),
    overageMetric: String(data.overageMetric ?? '').trim().toLowerCase(),
    includedSeats,
    seatAddonPlanKey: normalizeBillingPlanKey(data.seatAddonPlanKey),
    linkedBasePlanKey: normalizeBillingPlanKey(data.linkedBasePlanKey),
    active: data.active !== false,
  };
}

async function loadStripePlanMapping({ firestore, billingPlanKey }) {
  const normalizedPlanKey = normalizeBillingPlanKey(billingPlanKey);
  if (!normalizedPlanKey) {
    return null;
  }

  const byIdDoc = await firestore
    .collection('billing_integrations')
    .doc('stripe')
    .collection('plan_mappings')
    .doc(normalizedPlanKey)
    .get();

  if (byIdDoc.exists) {
    const data = byIdDoc.data() || {};
    const mapping = buildStripePlanMappingFromDocData(data, normalizedPlanKey);
    if (mapping) {
      return mapping;
    }
  }

  const querySnapshot = await firestore
    .collection('billing_integrations')
    .doc('stripe')
    .collection('plan_mappings')
    .where('billingPlanKey', '==', normalizedPlanKey)
    .limit(5)
    .get();

  for (const doc of querySnapshot.docs) {
    const data = doc.data() || {};
    const mapping = buildStripePlanMappingFromDocData(data, normalizedPlanKey);
    if (mapping) {
      return mapping;
    }
  }

  return null;
}

async function resolveStripePlanMappingByPriceId({ firestore, stripePriceId }) {
  const normalizedPriceId = String(stripePriceId ?? '').trim();
  if (!normalizedPriceId) {
    return null;
  }

  const snapshot = await firestore
    .collection('billing_integrations')
    .doc('stripe')
    .collection('plan_mappings')
    .where('stripePriceId', '==', normalizedPriceId)
    .limit(10)
    .get();

  for (const doc of snapshot.docs) {
    const mapping = buildStripePlanMappingFromDocData(doc.data() || {}, doc.id);
    if (mapping) {
      return mapping;
    }
  }

  return null;
}

async function resolveStripeSeatAddonMappingForBasePlan({
  firestore,
  baseMapping,
}) {
  const normalizedBasePlanKey = normalizeBillingPlanKey(baseMapping?.billingPlanKey);
  if (!normalizedBasePlanKey) {
    return null;
  }

  const seatAddonPlanKey = normalizeBillingPlanKey(baseMapping?.seatAddonPlanKey);
  if (seatAddonPlanKey) {
    const directMapping = await loadStripePlanMapping({
      firestore,
      billingPlanKey: seatAddonPlanKey,
    });
    if (
      directMapping &&
      directMapping.mappingType === 'overage' &&
      directMapping.overageMetric === 'extra_usuario'
    ) {
      return directMapping;
    }
  }

  const fallbackSnapshot = await firestore
    .collection('billing_integrations')
    .doc('stripe')
    .collection('plan_mappings')
    .where('linkedBasePlanKey', '==', normalizedBasePlanKey)
    .limit(20)
    .get();

  for (const doc of fallbackSnapshot.docs) {
    const mapping = buildStripePlanMappingFromDocData(doc.data() || {}, doc.id);
    if (!mapping) {
      continue;
    }
    if (mapping.mappingType !== 'overage') {
      continue;
    }
    if (mapping.overageMetric !== 'extra_usuario') {
      continue;
    }
    return mapping;
  }

  return null;
}

module.exports = {
  buildStripePlanMappingFromDocData,
  loadStripePlanMapping,
  resolveStripePlanMappingByPriceId,
  resolveStripeSeatAddonMappingForBasePlan,
};
