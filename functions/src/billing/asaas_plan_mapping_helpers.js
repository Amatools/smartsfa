const { normalizeBillingPlanKey } = require('./shared_helpers');
const { loadStripePlanMapping } = require('./stripe_plan_mappings');
const { mapStripeIntervalToAsaasCycle } = require('./asaas_checkout_helpers');

function buildAsaasPlanDocId(billingPlanKey) {
  return String(billingPlanKey ?? '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, '_');
}

function normalizeAsaasPlanMapping(rawMapping, billingPlanKey) {
  if (!rawMapping || typeof rawMapping !== 'object') {
    return null;
  }

  const amountCentsInput = Number(rawMapping.amountCents ?? 0);
  const amountCents = Number.isFinite(amountCentsInput)
    ? Math.max(0, Math.floor(amountCentsInput))
    : 0;

  return {
    billingPlanKey,
    mappingType: String(rawMapping.mappingType ?? 'base').trim().toLowerCase() || 'base',
    overageMetric: String(rawMapping.overageMetric ?? '').trim().toLowerCase(),
    planDisplayName: String(rawMapping.planDisplayName ?? '').trim(),
    planDisplayAmount: String(rawMapping.planDisplayAmount ?? '').trim(),
    amountCents,
    currency: String(rawMapping.currency ?? '').trim().toLowerCase() || 'brl',
    interval: String(rawMapping.interval ?? '').trim().toLowerCase() || 'month',
    intervalCount: Math.max(1, Math.floor(Number(rawMapping.intervalCount ?? 1) || 1)),
    includedSeats: Math.max(0, Math.floor(Number(rawMapping.includedSeats ?? 0) || 0)),
    seatAddonPlanKey: normalizeBillingPlanKey(rawMapping.seatAddonPlanKey),
    linkedBasePlanKey: normalizeBillingPlanKey(rawMapping.linkedBasePlanKey),
    active: rawMapping.active !== false,
  };
}

async function loadAsaasInternalPlanMapping({
  firestore,
  billingPlanKey,
}) {
  const normalizedPlanKey = normalizeBillingPlanKey(billingPlanKey);
  if (!normalizedPlanKey) {
    return null;
  }

  const byDocId = await firestore
    .collection('billing_integrations')
    .doc('asaas')
    .collection('internal_plan_catalog')
    .doc(buildAsaasPlanDocId(normalizedPlanKey))
    .get();

  if (byDocId.exists) {
    const normalized = normalizeAsaasPlanMapping(
      byDocId.data() || {},
      normalizedPlanKey,
    );
    if (normalized) {
      return normalized;
    }
  }

  const byField = await firestore
    .collection('billing_integrations')
    .doc('asaas')
    .collection('internal_plan_catalog')
    .where('billingPlanKey', '==', normalizedPlanKey)
    .limit(1)
    .get();

  if (!Array.isArray(byField?.docs) || byField.docs.length === 0) {
    return null;
  }

  return normalizeAsaasPlanMapping(
    byField.docs[0].data() || {},
    normalizedPlanKey,
  );
}

async function resolveAsaasPlanMapping({
  firestore,
  tenantData,
  billingPlanKey,
}) {
  const normalizedPlanKey = normalizeBillingPlanKey(billingPlanKey);
  if (!normalizedPlanKey) {
    return {
      ok: false,
      status: 400,
      error: 'invalid_plan_key',
      message: 'billingPlanKey invalido.',
      mapping: null,
    };
  }

  const asaasInternalMapping = await loadAsaasInternalPlanMapping({
    firestore,
    billingPlanKey: normalizedPlanKey,
  });

  const stripeMappingFallback = asaasInternalMapping
    ? null
    : await loadStripePlanMapping({
        firestore,
        billingPlanKey: normalizedPlanKey,
      });

  const effectiveMapping = asaasInternalMapping || stripeMappingFallback;
  if (!effectiveMapping) {
    return {
      ok: false,
      status: 404,
      error: 'plan_mapping_not_found',
      message: 'Plano nao encontrado no catalogo de billing.',
      mapping: null,
    };
  }

  if (asaasInternalMapping && asaasInternalMapping.active === false) {
    return {
      ok: false,
      status: 404,
      error: 'plan_mapping_not_found',
      message: 'Plano inativo no catalogo interno Asaas.',
      mapping: null,
    };
  }

  if (
    String(effectiveMapping.mappingType ?? 'base').trim().toLowerCase() ===
    'overage'
  ) {
    return {
      ok: false,
      status: 409,
      error: 'invalid_mapping_type',
      message: 'Use um plano base para abrir o checkout Asaas.',
      mapping: null,
    };
  }

  const amountMinorUnits = Number(
    asaasInternalMapping
      ? effectiveMapping.amountCents
      : effectiveMapping.stripeUnitAmount,
  );
  if (!Number.isFinite(amountMinorUnits) || amountMinorUnits <= 0) {
    return {
      ok: false,
      status: 409,
      error: 'invalid_plan_amount',
      message: 'Plano sem valor valido para checkout.',
      mapping: null,
    };
  }

  const currency = String(
    asaasInternalMapping
      ? effectiveMapping.currency
      : effectiveMapping.stripeCurrency,
  )
    .trim()
    .toLowerCase() || 'brl';
  if (currency !== 'brl') {
    return {
      ok: false,
      status: 409,
      error: 'unsupported_currency',
      message: 'Checkout Asaas suporta apenas planos em BRL neste fluxo.',
      mapping: null,
    };
  }

  const tenantName = String(
    tenantData?.displayName ||
      tenantData?.nomeFantasia ||
      tenantData?.razaoSocial ||
      tenantData?.name ||
      tenantData?.tenantName ||
      '',
  ).trim();

  const fallbackItemName = normalizedPlanKey.slice(0, 30);
  const itemName = String(
    effectiveMapping.planDisplayName ||
      effectiveMapping.stripeProductName ||
      effectiveMapping.stripePriceNickname ||
      fallbackItemName,
  )
    .trim()
    .slice(0, 30);

  const itemDescription = String(
    effectiveMapping.planDisplayAmount ||
      effectiveMapping.stripeProductName ||
      itemName,
  )
    .trim()
    .slice(0, 150);

  const cycle = mapStripeIntervalToAsaasCycle(
    asaasInternalMapping
      ? effectiveMapping.interval
      : effectiveMapping.stripeRecurringInterval,
    asaasInternalMapping
      ? effectiveMapping.intervalCount
      : effectiveMapping.stripeRecurringIntervalCount,
  );

  const customerData = {
    name: tenantName || `Tenant ${normalizedPlanKey}`,
  };
  const tenantEmail = String(tenantData?.email ?? '').trim().toLowerCase();
  if (tenantEmail) {
    customerData.email = tenantEmail;
  }

  const cpfCnpj = String(tenantData?.cnpj ?? tenantData?.cpfCnpj ?? '').trim();
  if (cpfCnpj) {
    customerData.cpfCnpj = cpfCnpj.replace(/\D+/g, '').slice(0, 14);
  }

  return {
    ok: true,
    status: 200,
    error: '',
    message: '',
    mapping: {
      billingPlanKey: normalizedPlanKey,
      amount: amountMinorUnits / 100,
      cycle,
      itemName: itemName || fallbackItemName,
      itemDescription,
      customerData,
    },
  };
}

async function resolveAsaasSeatAddonMappingForBasePlan({
  firestore,
  baseMapping,
}) {
  const normalizedBasePlanKey = normalizeBillingPlanKey(baseMapping?.billingPlanKey);
  if (!normalizedBasePlanKey) {
    return null;
  }

  const seatAddonPlanKey = normalizeBillingPlanKey(baseMapping?.seatAddonPlanKey);
  if (seatAddonPlanKey) {
    const directMapping = await loadAsaasInternalPlanMapping({
      firestore,
      billingPlanKey: seatAddonPlanKey,
    });
    if (
      directMapping &&
      directMapping.active !== false &&
      directMapping.mappingType === 'overage' &&
      directMapping.overageMetric === 'extra_usuario'
    ) {
      return directMapping;
    }
  }

  const fallbackSnapshot = await firestore
    .collection('billing_integrations')
    .doc('asaas')
    .collection('internal_plan_catalog')
    .where('linkedBasePlanKey', '==', normalizedBasePlanKey)
    .limit(20)
    .get();

  for (const doc of fallbackSnapshot.docs || []) {
    const mapping = normalizeAsaasPlanMapping(doc.data() || {}, doc.id);
    if (!mapping) {
      continue;
    }
    if (mapping.active === false) {
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
  loadAsaasInternalPlanMapping,
  resolveAsaasPlanMapping,
  resolveAsaasSeatAddonMappingForBasePlan,
};
