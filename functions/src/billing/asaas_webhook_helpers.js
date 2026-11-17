const { normalizeBillingPlanKey } = require('./shared_helpers');

function mapAsaasSubscriptionStatusToBillingStatus(rawStatus) {
  const normalized = String(rawStatus ?? '').trim().toUpperCase();
  if (!normalized) {
    return '';
  }

  if (normalized === 'ACTIVE') {
    return 'active';
  }
  if (normalized === 'INACTIVE') {
    return 'suspended';
  }
  if (normalized === 'EXPIRED' || normalized === 'CANCELED') {
    return 'canceled';
  }
  return '';
}

function mapBillingStatusToAccountState(billingStatus) {
  const normalized = String(billingStatus ?? '').trim().toLowerCase();
  if (!normalized) {
    return '';
  }
  if (normalized === 'active' || normalized === 'trial') {
    return 'active';
  }
  if (normalized === 'past_due') {
    return 'past_due';
  }
  if (normalized === 'grace') {
    return 'grace';
  }
  if (normalized === 'suspended') {
    return 'suspended';
  }
  return 'inactive';
}

function mapAsaasCycleToBillingCycle(rawCycle) {
  const normalized = String(rawCycle ?? '').trim().toUpperCase();
  if (!normalized) {
    return '';
  }
  if (normalized === 'MONTHLY') {
    return 'month';
  }
  if (normalized === 'YEARLY') {
    return 'year';
  }
  if (normalized === 'WEEKLY') {
    return 'week';
  }
  if (normalized === 'BIWEEKLY') {
    return 'biweek';
  }
  return normalized.toLowerCase();
}

function normalizeAsaasDateToIso(rawValue) {
  const text = String(rawValue ?? '').trim();
  if (!text) {
    return '';
  }

  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    return new Date(`${text}T00:00:00.000Z`).toISOString();
  }

  const normalizedText = text.includes(' ') ? text.replace(' ', 'T') : text;
  const parsedDate = new Date(normalizedText);
  const time = parsedDate.getTime();
  if (!Number.isFinite(time)) {
    return '';
  }
  return parsedDate.toISOString();
}

function extractAsaasReferenceInfo(rawValue) {
  const text = String(rawValue ?? '').trim();
  if (!text) {
    return {
      tenantId: '',
      billingPlanKey: '',
    };
  }

  let tenantId = '';
  let billingPlanKey = '';

  if (text.startsWith('{') && text.endsWith('}')) {
    try {
      const parsed = JSON.parse(text);
      tenantId = String(
        parsed?.tenantId ?? parsed?.tenant_id ?? parsed?.tenant ?? '',
      ).trim();
      billingPlanKey = normalizeBillingPlanKey(
        parsed?.billingPlanKey ?? parsed?.billing_plan_key ?? parsed?.plan ?? '',
      );
    } catch (_) {
      // Ignore invalid JSON and continue trying query-like parsing.
    }
  }

  if (!tenantId || !billingPlanKey) {
    const queryLike = text.includes('?') ? text.split('?').pop() : text;
    const params = new URLSearchParams(queryLike || '');
    if (!tenantId) {
      tenantId = String(
        params.get('tenantId') || params.get('tenant_id') || params.get('tenant') || '',
      ).trim();
    }
    if (!billingPlanKey) {
      billingPlanKey = normalizeBillingPlanKey(
        params.get('billingPlanKey') || params.get('plan') || params.get('billing_plan_key') || '',
      );
    }
  }

  if (!tenantId && !text.includes('=') && !text.includes('&') && text.length <= 120) {
    tenantId = text;
  }

  return {
    tenantId,
    billingPlanKey,
  };
}

module.exports = {
  extractAsaasReferenceInfo,
  mapAsaasCycleToBillingCycle,
  mapAsaasSubscriptionStatusToBillingStatus,
  mapBillingStatusToAccountState,
  normalizeAsaasDateToIso,
};
