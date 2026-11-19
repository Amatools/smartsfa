const {
  formatPlanAmountLabel,
  normalizeBillingPlanKey,
  resolveStripePlanPrefixByWorkspaceType,
} = require('./shared_helpers');
const {
  normalizeAsaasBillingTypes,
  normalizeAsaasChargeType,
} = require('./asaas_checkout_helpers');

async function listAsaasCheckoutPlansForTenant({
  firestore,
  tenantData,
}) {
  const workspaceType = String(tenantData.workspaceType ?? '')
    .trim()
    .toLowerCase();
  const requiredPrefix = resolveStripePlanPrefixByWorkspaceType(workspaceType);

  const snapshot = await firestore
    .collection('billing_integrations')
    .doc('asaas')
    .collection('internal_plan_catalog')
    .where('active', '==', true)
    .limit(400)
    .get();

  const seatAddonByPlanKey = new Map();
  const linkedSeatAddonByBasePlanKey = new Map();
  const baseDocs = [];

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const mappingType = String(data.mappingType ?? 'base').trim().toLowerCase();
    if (mappingType !== 'overage') {
      baseDocs.push(doc);
      continue;
    }

    const overageMetric = String(data.overageMetric ?? '').trim().toLowerCase();
    if (overageMetric !== 'extra_usuario') {
      continue;
    }

    const overagePlanKey = normalizeBillingPlanKey(data.billingPlanKey ?? doc.id);
    if (!overagePlanKey) {
      continue;
    }

    const overageUnitPriceCentsInput = Number(data.amountCents ?? 0);
    const overageUnitPriceCents = Number.isFinite(overageUnitPriceCentsInput)
      ? Math.max(0, Math.floor(overageUnitPriceCentsInput))
      : 0;
    const overageDisplayAmount =
      String(data.planDisplayAmount ?? '').trim() ||
      formatPlanAmountLabel({
        amountMinorUnits: overageUnitPriceCents,
        currency: String(data.currency ?? '').trim(),
        recurringInterval: String(data.interval ?? '').trim(),
        recurringIntervalCount: Number(data.intervalCount ?? 0),
      });

    const seatAddonInfo = {
      billingPlanKey: overagePlanKey,
      unitPriceCents: overageUnitPriceCents,
      displayAmount: overageDisplayAmount,
    };

    if (!seatAddonByPlanKey.has(overagePlanKey)) {
      seatAddonByPlanKey.set(overagePlanKey, seatAddonInfo);
    }

    const linkedBasePlanKey = normalizeBillingPlanKey(data.linkedBasePlanKey);
    if (!linkedBasePlanKey) {
      continue;
    }
    if (!linkedSeatAddonByBasePlanKey.has(linkedBasePlanKey)) {
      linkedSeatAddonByBasePlanKey.set(
        linkedBasePlanKey,
        seatAddonInfo,
      );
    }
  }

  const defaultAsaasChargeType = normalizeAsaasChargeType();
  const defaultAsaasBillingTypes = normalizeAsaasBillingTypes();

  const plans = [];
  for (const doc of baseDocs) {
    const data = doc.data() || {};
    const billingPlanKey = normalizeBillingPlanKey(data.billingPlanKey ?? doc.id);
    if (!billingPlanKey) {
      continue;
    }

    if (requiredPrefix && !billingPlanKey.startsWith(`${requiredPrefix}_`)) {
      continue;
    }

    const amountMinorUnits = Number(data.amountCents ?? 0);
    if (!Number.isFinite(amountMinorUnits) || amountMinorUnits <= 0) {
      continue;
    }

    const planDisplayName =
      String(data.planDisplayName ?? '').trim() ||
      billingPlanKey;

    const planDisplayAmount =
      String(data.planDisplayAmount ?? '').trim() ||
      formatPlanAmountLabel({
        amountMinorUnits,
        currency: String(data.currency ?? '').trim(),
        recurringInterval: String(data.interval ?? '').trim(),
        recurringIntervalCount: Number(data.intervalCount ?? 0),
      });

    const includedSeatsInput = Number(data.includedSeats ?? 0);
    const includedSeats = Number.isFinite(includedSeatsInput)
      ? Math.max(0, Math.floor(includedSeatsInput))
      : 0;

    let seatAddonInfo = null;
    let seatAddonPlanKey = normalizeBillingPlanKey(data.seatAddonPlanKey);
    if (seatAddonPlanKey) {
      seatAddonInfo = seatAddonByPlanKey.get(seatAddonPlanKey) || null;
    }
    if (!seatAddonPlanKey) {
      seatAddonInfo = linkedSeatAddonByBasePlanKey.get(billingPlanKey) || null;
      seatAddonPlanKey = String(seatAddonInfo?.billingPlanKey ?? '').trim();
    }
    if (!seatAddonInfo && seatAddonPlanKey) {
      seatAddonInfo = seatAddonByPlanKey.get(seatAddonPlanKey) || null;
    }

    const seatAddonUnitPriceCents = Number.isFinite(
      Number(seatAddonInfo?.unitPriceCents ?? 0),
    )
      ? Math.max(0, Math.floor(Number(seatAddonInfo?.unitPriceCents ?? 0)))
      : 0;
    const seatAddonDisplayAmount = String(
      seatAddonInfo?.displayAmount ?? '',
    ).trim();

    plans.push({
      mappingId: doc.id,
      billingPlanKey,
      planDisplayName,
      planDisplayAmount,
      stripePriceId: '',
      stripeProductId: '',
      stripeProductName: '',
      includedSeats,
      seatAddonPlanKey,
      seatAddonUnitPriceCents,
      seatAddonDisplayAmount,
      asaasChargeType: defaultAsaasChargeType,
      asaasBillingTypes: [...defaultAsaasBillingTypes],
    });
  }

  plans.sort((a, b) => {
    const byName = String(a.planDisplayName ?? '').localeCompare(
      String(b.planDisplayName ?? ''),
      'pt-BR',
    );
    if (byName !== 0) {
      return byName;
    }
    return String(a.billingPlanKey ?? '').localeCompare(
      String(b.billingPlanKey ?? ''),
    );
  });

  return {
    workspaceType,
    requiredPrefix,
    plans,
  };
}

module.exports = {
  listAsaasCheckoutPlansForTenant,
};
