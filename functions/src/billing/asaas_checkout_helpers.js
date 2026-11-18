const ASAAS_CHECKOUT_DEFAULT_BILLING_TYPES = ['PIX', 'CREDIT_CARD'];
const ASAAS_CHECKOUT_DEFAULT_CHARGE_TYPE = 'RECURRENT';
const ASAAS_CHECKOUT_DEFAULT_MINUTES_TO_EXPIRE = 60;

function mapStripeIntervalToAsaasCycle(interval, intervalCount) {
  const normalizedInterval = String(interval ?? '').trim().toLowerCase();
  const countInput = Number(intervalCount ?? 0);
  const count = Number.isFinite(countInput) && countInput > 0
    ? Math.floor(countInput)
    : 1;

  if (normalizedInterval === 'week') {
    if (count <= 1) {
      return 'WEEKLY';
    }
    if (count === 2) {
      return 'BIWEEKLY';
    }
    return 'MONTHLY';
  }

  if (normalizedInterval === 'year') {
    return 'YEARLY';
  }

  if (normalizedInterval === 'month') {
    if (count <= 1) {
      return 'MONTHLY';
    }
    if (count === 2) {
      return 'BIMONTHLY';
    }
    if (count === 3) {
      return 'QUARTERLY';
    }
    if (count === 6) {
      return 'SEMIANNUALLY';
    }
    if (count >= 12) {
      return 'YEARLY';
    }
    return 'MONTHLY';
  }

  return 'MONTHLY';
}

function normalizeAsaasBillingTypes(value) {
  const input = Array.isArray(value)
    ? value
    : [value];

  const allowed = new Set(['PIX', 'CREDIT_CARD']);
  const normalized = [];
  for (const item of input) {
    const candidate = String(item ?? '').trim().toUpperCase();
    if (allowed.has(candidate) && !normalized.includes(candidate)) {
      normalized.push(candidate);
    }
  }

  if (normalized.length === 0) {
    return [...ASAAS_CHECKOUT_DEFAULT_BILLING_TYPES];
  }
  return normalized;
}

function normalizeAsaasChargeType(value) {
  const candidate = String(value ?? '').trim().toUpperCase();
  return candidate === 'DETACHED' || candidate === 'INSTALLMENT' || candidate === 'RECURRENT'
    ? candidate
    : ASAAS_CHECKOUT_DEFAULT_CHARGE_TYPE;
}

function normalizeAsaasMinutesToExpire(value) {
  const input = Number(value ?? 0);
  if (!Number.isFinite(input) || input <= 0) {
    return ASAAS_CHECKOUT_DEFAULT_MINUTES_TO_EXPIRE;
  }
  const rounded = Math.floor(input);
  if (rounded < 10) {
    return 10;
  }
  if (rounded > 1440) {
    return 1440;
  }
  return rounded;
}

function buildAsaasCheckoutExternalReference({ tenantId, billingPlanKey }) {
  const now = Date.now();
  return `smartsfa:${tenantId}:${billingPlanKey}:${now}`.slice(0, 200);
}

module.exports = {
  buildAsaasCheckoutExternalReference,
  mapStripeIntervalToAsaasCycle,
  normalizeAsaasBillingTypes,
  normalizeAsaasChargeType,
  normalizeAsaasMinutesToExpire,
};
