const ASAAS_CHECKOUT_DEFAULT_BILLING_TYPES = ['PIX', 'CREDIT_CARD'];
const ASAAS_CHECKOUT_DEFAULT_CHARGE_TYPE = 'RECURRENT';
const ASAAS_CHECKOUT_DEFAULT_MINUTES_TO_EXPIRE = 60;
const ASAAS_CHECKOUT_PLACEHOLDER_IMAGE_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO6QX5wAAAAASUVORK5CYII=';

const { isValidHttpAbsoluteUrl } = require('./shared_helpers');

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

function buildAsaasCheckoutPayload({
  payload,
  tenantId,
  tenantData,
  resolvedPlan,
  callback,
}) {
  const plan = resolvedPlan.mapping;
  const billingTypes = normalizeAsaasBillingTypes(payload?.billingTypes);
  const chargeType = normalizeAsaasChargeType(payload?.chargeType);
  const minutesToExpire = normalizeAsaasMinutesToExpire(payload?.minutesToExpire);
  const dueDate = new Date();
  dueDate.setUTCDate(dueDate.getUTCDate() + 1);
  const nextDueDate = dueDate.toISOString().slice(0, 10);

  const requestPayload = {
    billingTypes,
    chargeTypes: [chargeType],
    minutesToExpire,
    externalReference: buildAsaasCheckoutExternalReference({
      tenantId,
      billingPlanKey: plan.billingPlanKey,
    }),
    callback,
    items: [
      {
        externalReference: plan.billingPlanKey,
        description: plan.itemDescription,
        imageBase64: ASAAS_CHECKOUT_PLACEHOLDER_IMAGE_BASE64,
        name: plan.itemName,
        quantity: 1,
        value: plan.amount,
      },
    ],
  };

  const customerData = plan.customerData;
  if (customerData?.name) {
    requestPayload.customerData = customerData;
  }

  if (chargeType === 'RECURRENT') {
    requestPayload.subscription = {
      cycle: plan.cycle,
      nextDueDate,
    };
  }

  const walletId = String(
    payload?.walletId || tenantData?.billingAsaasWalletId || '',
  ).trim();
  if (walletId) {
    requestPayload.splits = [
      {
        walletId,
      },
    ];
  }

  return requestPayload;
}

function resolveAsaasPortalFallbackUrl({ tenantData }) {
  const candidateKeys = [
    'asaasInvoiceUrl',
    'asaasLastInvoiceUrl',
    'asaasPaymentInvoiceUrl',
    'asaasPaymentBankSlipUrl',
    'asaasCheckoutLink',
  ];

  for (const key of candidateKeys) {
    const value = String(tenantData?.[key] ?? '').trim();
    if (isValidHttpAbsoluteUrl(value)) {
      return value;
    }
  }

  return '';
}

module.exports = {
  buildAsaasCheckoutExternalReference,
  buildAsaasCheckoutPayload,
  mapStripeIntervalToAsaasCycle,
  normalizeAsaasBillingTypes,
  normalizeAsaasChargeType,
  normalizeAsaasMinutesToExpire,
  resolveAsaasPortalFallbackUrl,
};
