const crypto = require('node:crypto');

function normalizeQuoteTtlMinutes(rawValue) {
  const input = Number(rawValue ?? 0);
  if (!Number.isFinite(input) || input <= 0) {
    return 60;
  }

  const rounded = Math.floor(input);
  if (rounded < 5) {
    return 5;
  }
  if (rounded > 1440) {
    return 1440;
  }
  return rounded;
}

function buildQuoteChecksum(input) {
  const serialized = JSON.stringify(input);
  return crypto.createHash('sha256').update(serialized).digest('hex');
}

function toSafeDocToken(rawValue) {
  return String(rawValue ?? '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '');
}

async function createAsaasBillingQuote({
  firestore,
  tenantId,
  tenantData,
  payload,
  providerSelection,
  billingProviderAsaas,
  normalizeBillingPlanKey,
  readNonNegativeInteger,
  loadAsaasInternalPlanMapping,
  resolveAsaasSeatAddonMappingForBasePlan,
}) {
  const billingPlanKey = normalizeBillingPlanKey(payload?.billingPlanKey);
  if (!billingPlanKey) {
    return {
      ok: false,
      status: 400,
      error: 'invalid_payload',
      message: 'billingPlanKey e obrigatorio para gerar quote.',
      body: null,
    };
  }

  const addonSeats = readNonNegativeInteger(payload?.addonSeats, 0);
  if (addonSeats > 1000) {
    return {
      ok: false,
      status: 400,
      error: 'invalid_payload',
      message: 'addonSeats deve estar entre 0 e 1000.',
      body: null,
    };
  }

  const baseMapping = await loadAsaasInternalPlanMapping({
    firestore,
    billingPlanKey,
  });

  if (!baseMapping || baseMapping.active === false || baseMapping.mappingType !== 'base') {
    return {
      ok: false,
      status: 409,
      error: 'base_plan_mapping_not_found',
      message: 'Nao foi possivel identificar mapeamento base ativo para este plano.',
      body: null,
    };
  }

  const baseAmountCents = readNonNegativeInteger(baseMapping.amountCents, 0);
  if (baseAmountCents <= 0) {
    return {
      ok: false,
      status: 409,
      error: 'invalid_plan_amount',
      message: 'Plano base sem valor valido para gerar quote.',
      body: null,
    };
  }

  let addonMapping = null;
  let extraSeatUnitAmountCents = 0;
  if (addonSeats > 0) {
    addonMapping = await resolveAsaasSeatAddonMappingForBasePlan({
      firestore,
      baseMapping,
    });

    if (
      !addonMapping ||
      addonMapping.active === false ||
      addonMapping.mappingType !== 'overage' ||
      addonMapping.overageMetric !== 'extra_usuario'
    ) {
      return {
        ok: false,
        status: 409,
        error: 'invalid_seat_addon_mapping',
        message:
          'Plano base sem mapeamento overage extra_usuario valido para calcular seats extras.',
        body: null,
      };
    }

    extraSeatUnitAmountCents = readNonNegativeInteger(addonMapping.amountCents, 0);
    if (extraSeatUnitAmountCents <= 0) {
      return {
        ok: false,
        status: 409,
        error: 'invalid_plan_amount',
        message: 'Plano aditivo de seats sem valor valido para gerar quote.',
        body: null,
      };
    }
  }

  const totalAmountCents =
    baseAmountCents + extraSeatUnitAmountCents * addonSeats;
  const quoteTtlMinutes = normalizeQuoteTtlMinutes(payload?.quoteTtlMinutes);
  const now = new Date();
  const expiresAtDate = new Date(now.getTime() + quoteTtlMinutes * 60 * 1000);
  const nowIso = now.toISOString();
  const expiresAtIso = expiresAtDate.toISOString();

  const quoteRef = firestore.collection('billing_quotes').doc();
  let quoteId = String(quoteRef?.id ?? '').trim();
  if (!quoteId) {
    const tenantToken = toSafeDocToken(tenantId) || 'tenant';
    quoteId = `${tenantToken}_${now.getTime()}`;
  }

  const checksum = buildQuoteChecksum({
    tenantId,
    billingProvider: billingProviderAsaas,
    billingPlanKey: baseMapping.billingPlanKey,
    baseAmountCents,
    addonSeats,
    extraSeatUnitAmountCents,
    totalAmountCents,
    currency: String(baseMapping.currency ?? 'brl').trim().toLowerCase(),
    interval: String(baseMapping.interval ?? 'month').trim().toLowerCase(),
    intervalCount: readNonNegativeInteger(baseMapping.intervalCount, 1),
    quoteTtlMinutes,
  });

  const quoteData = {
    quoteId,
    tenantId,
    billingProvider: billingProviderAsaas,
    billingPlanKey: baseMapping.billingPlanKey,
    planKey: baseMapping.billingPlanKey,
    baseAmountCents,
    extraSeats: addonSeats,
    extraSeatUnitAmountCents,
    totalAmountCents,
    includedSeats: readNonNegativeInteger(baseMapping.includedSeats, 0),
    seatAddonPlanKey: String(addonMapping?.billingPlanKey ?? '').trim(),
    currency: String(baseMapping.currency ?? 'brl').trim().toLowerCase(),
    cycle: String(baseMapping.interval ?? 'month').trim().toLowerCase(),
    intervalCount: readNonNegativeInteger(baseMapping.intervalCount, 1),
    status: 'open',
    checksum,
    operationId: String(payload?.operationId ?? payload?.idempotencyKey ?? '').trim(),
    providerSelectionSource: String(providerSelection?.source ?? '').trim(),
    hasLinkedContract: providerSelection?.hasLinkedContract === true,
    workspaceType: String(tenantData?.workspaceType ?? '').trim().toLowerCase(),
    expiresAt: expiresAtIso,
    usedAt: '',
    usedByCheckoutId: '',
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  await firestore.collection('billing_quotes').doc(quoteId).set(quoteData);

  return {
    ok: true,
    status: 200,
    error: '',
    message: '',
    body: {
      tenantId,
      billingProvider: billingProviderAsaas,
      providerSelectionSource: providerSelection.source,
      hasLinkedContract: providerSelection.hasLinkedContract,
      quoteId,
      quoteStatus: 'open',
      billingPlanKey: baseMapping.billingPlanKey,
      baseAmountCents,
      addonSeats,
      extraSeatUnitAmountCents,
      totalAmountCents,
      totalAmount: Number((totalAmountCents / 100).toFixed(2)),
      includedSeats: readNonNegativeInteger(baseMapping.includedSeats, 0),
      seatAddonPlanKey: String(addonMapping?.billingPlanKey ?? '').trim(),
      currency: String(baseMapping.currency ?? 'brl').trim().toLowerCase(),
      cycle: String(baseMapping.interval ?? 'month').trim().toLowerCase(),
      intervalCount: readNonNegativeInteger(baseMapping.intervalCount, 1),
      expiresAt: expiresAtIso,
      checksum,
    },
  };
}

module.exports = {
  createAsaasBillingQuote,
  normalizeQuoteTtlMinutes,
};