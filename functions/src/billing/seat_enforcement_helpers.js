const {
  normalizeBillingPlanKey,
  readNonNegativeInteger,
} = require('./shared_helpers');

const TENANT_SEAT_ENFORCEMENT_ACTIVE_BILLING_STATUSES = new Set([
  'active',
  'trial',
  'past_due',
  'grace',
]);

function normalizeSeatBillingStatus(rawStatus) {
  return String(rawStatus ?? '').trim().toLowerCase();
}

function parseDateToUnixMs(raw) {
  if (!raw) {
    return 0;
  }
  if (raw instanceof Date) {
    return raw.getTime();
  }
  if (typeof raw?.toDate === 'function') {
    try {
      const asDate = raw.toDate();
      if (asDate instanceof Date) {
        return asDate.getTime();
      }
    } catch (_) {
      return 0;
    }
  }
  if (typeof raw === 'number') {
    return Number.isFinite(raw) ? raw : 0;
  }
  if (typeof raw === 'string') {
    const date = new Date(raw);
    const time = date.getTime();
    return Number.isFinite(time) ? time : 0;
  }
  return 0;
}

function readMembershipOrderingMs(membershipDoc, nowMs) {
  const data = membershipDoc.data() || {};
  const dateCandidates = [
    data.activatedAt,
    data.lastSyncedAt,
    data.createdAt,
    data.updatedAt,
  ];

  for (const candidate of dateCandidates) {
    const ms = parseDateToUnixMs(candidate);
    if (ms > 0) {
      return ms;
    }
  }

  const createTimeMs = parseDateToUnixMs(membershipDoc.createTime);
  if (createTimeMs > 0) {
    return createTimeMs;
  }

  return nowMs;
}

function resolveDefaultIncludedSeatsForTenant(tenantData) {
  const workspaceType = String(tenantData.workspaceType ?? '')
    .trim()
    .toLowerCase();
  const billingPlanKey = normalizeBillingPlanKey(tenantData.billingPlanKey);
  const planTier = String(tenantData.planTier ?? '').trim().toLowerCase();

  const tierMatch = /(\d+)/.exec(planTier);
  if (tierMatch) {
    const parsedTierSeats = Number(tierMatch[1]);
    if (Number.isFinite(parsedTierSeats) && parsedTierSeats > 0) {
      return Math.floor(parsedTierSeats);
    }
  }

  if (workspaceType === 'brand_owner_workspace' || billingPlanKey === 'enterprise') {
    return 3;
  }

  if (workspaceType === 'seller_solo_workspace' || billingPlanKey === 'solo') {
    return 1;
  }

  return 1;
}

function readTenantSeatAllowance(tenantData) {
  const fallbackIncludedSeats = resolveDefaultIncludedSeatsForTenant(tenantData);
  const includedSeats = readNonNegativeInteger(
    tenantData.billingSeatsIncluded,
    fallbackIncludedSeats,
  );
  const addonSeats = readNonNegativeInteger(
    tenantData.billingSeatsAddon,
    readNonNegativeInteger(tenantData.billingSeatAddons, 0),
  );

  const configuredLimit = Math.max(1, includedSeats + addonSeats);
  return {
    includedSeats,
    addonSeats,
    configuredLimit,
  };
}

function shouldEnforceTenantSeatAllowance(tenantData) {
  const billingStatus = normalizeSeatBillingStatus(tenantData.billingStatus);
  if (!TENANT_SEAT_ENFORCEMENT_ACTIVE_BILLING_STATUSES.has(billingStatus)) {
    return false;
  }

  const billingPlanKey = normalizeBillingPlanKey(tenantData.billingPlanKey);
  return Boolean(billingPlanKey);
}

module.exports = {
  parseDateToUnixMs,
  readMembershipOrderingMs,
  readTenantSeatAllowance,
  resolveDefaultIncludedSeatsForTenant,
  shouldEnforceTenantSeatAllowance,
};
