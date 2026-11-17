function normalizeBillingPlanKey(rawValue) {
  return String(rawValue ?? '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_');
}

function normalizeBillingSelfServiceAction(rawValue) {
  const normalized = String(rawValue ?? '').trim().toLowerCase();
  if (!normalized) {
    return '';
  }

  if (
    normalized === 'stop_renewal' ||
    normalized === 'pause_renewal' ||
    normalized === 'suspend_renewal' ||
    normalized === 'suspend'
  ) {
    return 'stop_renewal';
  }

  if (
    normalized === 'cancel_now' ||
    normalized === 'cancel_plan' ||
    normalized === 'cancel'
  ) {
    return 'cancel_now';
  }

  return '';
}

function parseBillingPlanKeyParts(billingPlanKey) {
  const normalized = normalizeBillingPlanKey(billingPlanKey);
  if (!normalized) {
    return { prefix: '', slug: '' };
  }

  const separatorIndex = normalized.indexOf('_');
  if (separatorIndex <= 0 || separatorIndex >= normalized.length - 1) {
    return { prefix: normalized, slug: normalized };
  }

  return {
    prefix: normalized.slice(0, separatorIndex),
    slug: normalized.slice(separatorIndex + 1),
  };
}

function sanitizeStripeMetadataValue(value, maxLength = 200) {
  const text = String(value ?? '').trim();
  if (!text) {
    return '';
  }
  return text.length <= maxLength ? text : text.slice(0, maxLength);
}

function resolveStripePlanPrefixByWorkspaceType(workspaceType) {
  const normalized = String(workspaceType ?? '').trim().toLowerCase();
  if (normalized === 'seller_solo_workspace') {
    return 'individual';
  }
  if (normalized === 'rep_workspace') {
    return 'representacoes';
  }
  if (normalized === 'brand_owner_workspace') {
    return 'enterprise';
  }
  return '';
}

function formatPlanAmountLabel({
  amountMinorUnits,
  currency,
  recurringInterval,
  recurringIntervalCount,
}) {
  const amount = Number(amountMinorUnits ?? 0);
  if (!Number.isFinite(amount) || amount <= 0) {
    return '';
  }

  const normalizedCurrency = String(currency ?? '').trim().toLowerCase();
  const currencyLabel =
    normalizedCurrency === 'brl'
      ? 'R$'
      : normalizedCurrency
        ? normalizedCurrency.toUpperCase()
        : '';
  const base = `${currencyLabel ? `${currencyLabel} ` : ''}${(amount / 100).toFixed(2)}`;

  const interval = String(recurringInterval ?? '').trim().toLowerCase();
  if (!interval) {
    return base;
  }

  const intervalCount = Number(recurringIntervalCount ?? 0);
  const normalizedCount = Number.isFinite(intervalCount) && intervalCount > 0
    ? Math.floor(intervalCount)
    : 1;

  return `${base} / ${interval} x${normalizedCount}`;
}

function isValidHttpAbsoluteUrl(value) {
  const raw = String(value ?? '').trim();
  if (!raw) {
    return false;
  }

  try {
    const parsed = new URL(raw);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

function readNonNegativeInteger(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return Math.max(0, Math.floor(Number(fallback) || 0));
  }
  return Math.max(0, Math.floor(parsed));
}

module.exports = {
  formatPlanAmountLabel,
  isValidHttpAbsoluteUrl,
  normalizeBillingPlanKey,
  normalizeBillingSelfServiceAction,
  parseBillingPlanKeyParts,
  readNonNegativeInteger,
  resolveStripePlanPrefixByWorkspaceType,
  sanitizeStripeMetadataValue,
};
