async function executeExpireTenantGraceDailyAction({
  firestore,
  nowDate,
}) {
  const nowMs = nowDate.getTime();
  const nowIso = nowDate.toISOString();

  const graceSnapshot = await firestore
    .collection('tenants')
    .where('billingStatus', '==', 'grace')
    .get();

  let processed = 0;
  let convertedNoPlan = 0;
  let skippedMissingGraceUntil = 0;
  let skippedNotExpiredYet = 0;
  let skippedHasStripeSubscription = 0;

  for (const tenantDoc of graceSnapshot.docs) {
    processed += 1;
    const tenantData = tenantDoc.data() || {};

    const graceUntilIso = String(tenantData.billingGraceUntilAt ?? '').trim();
    if (!graceUntilIso) {
      skippedMissingGraceUntil += 1;
      continue;
    }

    const graceUntilDate = new Date(graceUntilIso);
    const graceUntilMs = graceUntilDate.getTime();
    if (!Number.isFinite(graceUntilMs)) {
      skippedMissingGraceUntil += 1;
      continue;
    }

    if (graceUntilMs > nowMs) {
      skippedNotExpiredYet += 1;
      continue;
    }

    const stripeSubscriptionId = String(
      tenantData.stripeSubscriptionId ?? '',
    ).trim();
    if (stripeSubscriptionId) {
      skippedHasStripeSubscription += 1;
      continue;
    }

    await tenantDoc.ref.set(
      {
        billingStatus: 'no_plan',
        billingAccountState: 'inactive',
        billingPlanKey: '',
        billingCycle: '',
        stripePriceId: '',
        stripeCheckoutSessionId: '',
        billingCurrentPeriodStartAt: '',
        billingCurrentPeriodEndAt: '',
        billingGraceUntilAt: '',
        billingPastDueSinceAt: '',
        billingSuspendedAt: nowIso,
        billingDelinquencyStage: 'none',
        billingUpdatedAt: nowIso,
        billingLastAutoAction: 'grace_expired_blocked',
        billingLastAutoAt: nowIso,
      },
      { merge: true },
    );

    convertedNoPlan += 1;
  }

  return {
    processed,
    convertedNoPlan,
    skippedMissingGraceUntil,
    skippedNotExpiredYet,
    skippedHasStripeSubscription,
    updatedAt: nowIso,
  };
}

async function executeEnforceTenantSeatAllowanceHourlyAction({
  firestore,
  nowDate,
  enforceTenantSeatAllowanceForTenant,
  loggerInfo,
}) {
  const nowIso = nowDate.toISOString();

  const tenantsSnapshot = await firestore.collection('tenants').get();
  let processed = 0;
  let skipped = 0;
  let overLimitGrace = 0;
  let deactivated = 0;
  const failures = [];

  for (const tenantDoc of tenantsSnapshot.docs) {
    processed += 1;
    try {
      const summary = await enforceTenantSeatAllowanceForTenant({
        firestore,
        tenantId: tenantDoc.id,
        tenantDoc,
        nowDate,
      });
      if (summary.state === 'skipped') {
        skipped += 1;
      }
      if (summary.state === 'over_limit_grace') {
        overLimitGrace += 1;
      }
      if (summary.deactivatedCount > 0) {
        deactivated += summary.deactivatedCount;
      }
    } catch (error) {
      failures.push({
        tenantId: tenantDoc.id,
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  loggerInfo('enforceTenantSeatAllowanceHourly', {
    processed,
    skipped,
    overLimitGrace,
    deactivated,
    failures: failures.length,
    updatedAt: nowIso,
  });

  return {
    processed,
    skipped,
    overLimitGrace,
    deactivated,
    failures,
    updatedAt: nowIso,
  };
}

async function executeExpireBillingQuotesHourlyAction({
  firestore,
  nowDate,
}) {
  const nowMs = nowDate.getTime();
  const nowIso = nowDate.toISOString();

  const quoteSnapshot = await firestore
    .collection('billing_quotes')
    .where('status', '==', 'open')
    .get();

  let processed = 0;
  let expired = 0;
  let skippedMissingExpiresAt = 0;
  let skippedInvalidExpiresAt = 0;
  let skippedNotExpiredYet = 0;

  for (const quoteDoc of quoteSnapshot.docs) {
    processed += 1;
    const quoteData = quoteDoc.data() || {};

    const expiresAtIso = String(quoteData.expiresAt ?? '').trim();
    if (!expiresAtIso) {
      skippedMissingExpiresAt += 1;
      continue;
    }

    const expiresAtDate = new Date(expiresAtIso);
    const expiresAtMs = expiresAtDate.getTime();
    if (!Number.isFinite(expiresAtMs)) {
      skippedInvalidExpiresAt += 1;
      continue;
    }

    if (expiresAtMs > nowMs) {
      skippedNotExpiredYet += 1;
      continue;
    }

    await quoteDoc.ref.set(
      {
        status: 'expired',
        expiredAt: nowIso,
        updatedAt: nowIso,
        expirationReason: 'ttl_elapsed',
      },
      { merge: true },
    );

    expired += 1;
  }

  return {
    processed,
    expired,
    skippedMissingExpiresAt,
    skippedInvalidExpiresAt,
    skippedNotExpiredYet,
    updatedAt: nowIso,
  };
}

async function executeExpireLegacyOpenBillingQuotesDailyAction({
  firestore,
  nowDate,
}) {
  const nowIso = nowDate.toISOString();

  const quoteSnapshot = await firestore
    .collection('billing_quotes')
    .where('status', '==', 'open')
    .get();

  let processed = 0;
  let expiredLegacyMissingExpiresAt = 0;
  let expiredLegacyInvalidExpiresAt = 0;
  let skippedHasValidExpiresAt = 0;

  for (const quoteDoc of quoteSnapshot.docs) {
    processed += 1;
    const quoteData = quoteDoc.data() || {};

    const expiresAtIso = String(quoteData.expiresAt ?? '').trim();
    if (!expiresAtIso) {
      await quoteDoc.ref.set(
        {
          status: 'expired',
          expiredAt: nowIso,
          updatedAt: nowIso,
          expirationReason: 'legacy_missing_expires_at',
          sanitationAction: 'expire_legacy_open_quotes_daily',
        },
        { merge: true },
      );
      expiredLegacyMissingExpiresAt += 1;
      continue;
    }

    const expiresAtDate = new Date(expiresAtIso);
    const expiresAtMs = expiresAtDate.getTime();
    if (!Number.isFinite(expiresAtMs)) {
      await quoteDoc.ref.set(
        {
          status: 'expired',
          expiredAt: nowIso,
          updatedAt: nowIso,
          expirationReason: 'legacy_invalid_expires_at',
          sanitationAction: 'expire_legacy_open_quotes_daily',
        },
        { merge: true },
      );
      expiredLegacyInvalidExpiresAt += 1;
      continue;
    }

    skippedHasValidExpiresAt += 1;
  }

  return {
    processed,
    expiredLegacyMissingExpiresAt,
    expiredLegacyInvalidExpiresAt,
    skippedHasValidExpiresAt,
    updatedAt: nowIso,
  };
}

module.exports = {
  executeExpireTenantGraceDailyAction,
  executeEnforceTenantSeatAllowanceHourlyAction,
  executeExpireBillingQuotesHourlyAction,
  executeExpireLegacyOpenBillingQuotesDailyAction,
};
