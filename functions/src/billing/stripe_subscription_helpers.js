const { normalizeBillingPlanKey } = require('./shared_helpers');

const BILLING_PROVIDER_STRIPE = 'stripe';

function readStripeSubscriptionPriceId(subscription) {
  const items = Array.isArray(subscription?.items?.data)
    ? subscription.items.data
    : [];
  const firstItem = items.length > 0 ? items[0] : null;
  return String(firstItem?.price?.id ?? '').trim();
}

function readStripeSubscriptionLineItems(subscription) {
  const items = Array.isArray(subscription?.items?.data)
    ? subscription.items.data
    : [];

  return items
    .map((item) => {
      const priceId = String(item?.price?.id ?? '').trim();
      const quantityInput = Number(item?.quantity ?? 0);
      const quantity = Number.isFinite(quantityInput)
        ? Math.max(0, Math.floor(quantityInput))
        : 0;
      return { priceId, quantity };
    })
    .filter((item) => item.priceId);
}

function readStripeSubscriptionCycle(subscription) {
  const items = Array.isArray(subscription?.items?.data)
    ? subscription.items.data
    : [];
  const firstItem = items.length > 0 ? items[0] : null;
  return String(firstItem?.price?.recurring?.interval ?? '').trim() || 'month';
}

function mapStripeSubscriptionStatusToBillingStatus(rawStatus) {
  const status = String(rawStatus ?? '').trim().toLowerCase();
  switch (status) {
    case 'trialing':
      return 'trial';
    case 'active':
      return 'active';
    case 'past_due':
    case 'unpaid':
    case 'incomplete':
      return 'past_due';
    case 'paused':
      return 'suspended';
    case 'canceled':
    case 'incomplete_expired':
      return 'canceled';
    default:
      return 'active';
  }
}

function toIsoFromUnixSeconds(value) {
  const seconds = Number(value);
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return '';
  }
  return new Date(seconds * 1000).toISOString();
}

function readStripeSubscriptionPeriodBounds(subscription) {
  const directStart = Number(
    subscription?.current_period_start ?? subscription?.current_period?.start,
  );
  const directEnd = Number(
    subscription?.current_period_end ?? subscription?.current_period?.end,
  );

  if (Number.isFinite(directStart) && directStart > 0 && Number.isFinite(directEnd) && directEnd > 0) {
    return {
      startIso: toIsoFromUnixSeconds(directStart),
      endIso: toIsoFromUnixSeconds(directEnd),
    };
  }

  const items = Array.isArray(subscription?.items?.data)
    ? subscription.items.data
    : [];

  let startSeconds = Number.isFinite(directStart) && directStart > 0 ? directStart : 0;
  let endSeconds = Number.isFinite(directEnd) && directEnd > 0 ? directEnd : 0;

  for (const item of items) {
    const itemStart = Number(
      item?.current_period_start ?? item?.current_period?.start,
    );
    const itemEnd = Number(
      item?.current_period_end ?? item?.current_period?.end,
    );

    if (!startSeconds && Number.isFinite(itemStart) && itemStart > 0) {
      startSeconds = itemStart;
    }
    if (!endSeconds && Number.isFinite(itemEnd) && itemEnd > 0) {
      endSeconds = itemEnd;
    }

    if (startSeconds && endSeconds) {
      break;
    }
  }

  return {
    startIso: toIsoFromUnixSeconds(startSeconds),
    endIso: toIsoFromUnixSeconds(endSeconds),
  };
}

function readStripeInvoicePeriodBounds(invoice) {
  const lines = Array.isArray(invoice?.lines?.data) ? invoice.lines.data : [];
  let minStart = 0;
  let maxEnd = 0;

  for (const line of lines) {
    const start = Number(line?.period?.start ?? 0);
    const end = Number(line?.period?.end ?? 0);
    if (Number.isFinite(start) && start > 0) {
      if (!minStart || start < minStart) {
        minStart = start;
      }
    }
    if (Number.isFinite(end) && end > 0) {
      if (!maxEnd || end > maxEnd) {
        maxEnd = end;
      }
    }
  }

  return {
    startIso: toIsoFromUnixSeconds(minStart),
    endIso: toIsoFromUnixSeconds(maxEnd),
  };
}

async function readStripeSubscriptionPeriodFromInvoices({
  stripeClient,
  subscriptionId,
}) {
  const normalizedSubscriptionId = String(subscriptionId ?? '').trim();
  if (!stripeClient || !normalizedSubscriptionId) {
    return { startIso: '', endIso: '' };
  }

  try {
    const invoiceList = await stripeClient.invoices.list({
      subscription: normalizedSubscriptionId,
      limit: 5,
      expand: ['data.lines.data'],
    });

    const invoices = Array.isArray(invoiceList?.data) ? invoiceList.data : [];
    for (const invoice of invoices) {
      const bounds = readStripeInvoicePeriodBounds(invoice);
      if (bounds.startIso && bounds.endIso) {
        return bounds;
      }
    }
  } catch (error) {
    console.error('stripe invoice period fallback failed', {
      subscriptionId: normalizedSubscriptionId,
      error: error instanceof Error ? error.message : String(error),
    });
  }

  return { startIso: '', endIso: '' };
}

function buildTenantPatchFromStripeSubscription({ subscription, billingPlanKey }) {
  const priceId = readStripeSubscriptionPriceId(subscription);
  const nowIso = new Date().toISOString();
  const billingStatus = mapStripeSubscriptionStatusToBillingStatus(
    subscription?.status,
  );
  const periodBounds = readStripeSubscriptionPeriodBounds(subscription);

  const patch = {
    billingProvider: BILLING_PROVIDER_STRIPE,
    stripeCustomerId: String(subscription?.customer ?? '').trim(),
    stripeSubscriptionId: String(subscription?.id ?? '').trim(),
    stripePriceId: priceId,
    billingStatus,
    billingCycle: readStripeSubscriptionCycle(subscription),
    billingUpdatedAt: nowIso,
  };

  if (patch.stripeSubscriptionId) {
    patch.billingContractProvider = BILLING_PROVIDER_STRIPE;
    patch.billingContractLinkedAt = nowIso;
  }

  if (periodBounds.startIso) {
    patch.billingCurrentPeriodStartAt = periodBounds.startIso;
  }
  if (periodBounds.endIso) {
    patch.billingCurrentPeriodEndAt = periodBounds.endIso;
  }

  const normalizedPlanKey = normalizeBillingPlanKey(billingPlanKey);
  if (normalizedPlanKey) {
    patch.billingPlanKey = normalizedPlanKey;
  }

  if (billingStatus === 'past_due') {
    patch.billingPastDueSinceAt = nowIso;
  }
  if (billingStatus === 'active') {
    patch.billingPastDueSinceAt = '';
    patch.billingSuspendedAt = '';
  }
  if (billingStatus === 'canceled') {
    patch.billingSuspendedAt = nowIso;
  }

  return patch;
}

module.exports = {
  buildTenantPatchFromStripeSubscription,
  mapStripeSubscriptionStatusToBillingStatus,
  readStripeInvoicePeriodBounds,
  readStripeSubscriptionCycle,
  readStripeSubscriptionLineItems,
  readStripeSubscriptionPeriodBounds,
  readStripeSubscriptionPeriodFromInvoices,
  readStripeSubscriptionPriceId,
};
