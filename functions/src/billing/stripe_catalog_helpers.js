const {
  normalizeBillingPlanKey,
  parseBillingPlanKeyParts,
  sanitizeStripeMetadataValue,
} = require('./shared_helpers');

function buildStripeRecommendedLookupKey({
  billingPlanKey,
  currency,
  recurringInterval,
  recurringIntervalCount,
}) {
  const normalizedPlanKey = normalizeBillingPlanKey(billingPlanKey).replace(
    /[^a-z0-9_-]+/g,
    '_',
  );
  if (!normalizedPlanKey) {
    return '';
  }

  const normalizedCurrency = String(currency ?? '').trim().toLowerCase();
  const normalizedInterval = String(recurringInterval ?? '').trim().toLowerCase();
  const normalizedCount = Number.isFinite(Number(recurringIntervalCount))
    ? Math.max(1, Math.floor(Number(recurringIntervalCount)))
    : 1;
  const countSuffix = normalizedCount > 1 ? `x${normalizedCount}` : '';

  const raw = `smartsfa_${normalizedPlanKey}_${normalizedCurrency}_${normalizedInterval}${countSuffix}`;
  const compact = raw
    .replace(/[^a-z0-9_]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '');
  return compact.length <= 120 ? compact : compact.slice(0, 120);
}

function buildStripeCatalogPlanMetadata({
  billingPlanKey,
  amountMinorUnits,
  currency,
  recurringInterval,
  recurringIntervalCount,
  lookupKey,
  actorUid,
  actorEmail,
}) {
  const parts = parseBillingPlanKeyParts(billingPlanKey);
  return {
    source: 'smartsfa_admin_console',
    billingPlanKey: sanitizeStripeMetadataValue(billingPlanKey),
    billingPlanPrefix: sanitizeStripeMetadataValue(parts.prefix),
    billingPlanSlug: sanitizeStripeMetadataValue(parts.slug),
    amountMinorUnits: sanitizeStripeMetadataValue(String(amountMinorUnits ?? '')),
    currency: sanitizeStripeMetadataValue(String(currency ?? '').toLowerCase(), 12),
    recurringInterval: sanitizeStripeMetadataValue(
      String(recurringInterval ?? '').toLowerCase(),
      20,
    ),
    recurringIntervalCount: sanitizeStripeMetadataValue(
      String(recurringIntervalCount ?? ''),
      8,
    ),
    lookupKey: sanitizeStripeMetadataValue(lookupKey),
    createdByUid: sanitizeStripeMetadataValue(actorUid),
    createdByEmail: sanitizeStripeMetadataValue(actorEmail),
  };
}

module.exports = {
  buildStripeCatalogPlanMetadata,
  buildStripeRecommendedLookupKey,
};
