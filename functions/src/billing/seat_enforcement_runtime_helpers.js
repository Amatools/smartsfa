async function enforceTenantSeatAllowanceForTenant({
  firestore,
  tenantId,
  tenantDoc = null,
  nowDate = new Date(),
  shouldEnforceTenantSeatAllowance,
  readTenantSeatAllowance,
  readMembershipOrderingMs,
  parseDateToUnixMs,
  writeTenantMembershipAuditEvent,
  seatGraceDays,
  seatEnforcementActorUid,
}) {
  const normalizedTenantId = String(tenantId ?? '').trim();
  if (!normalizedTenantId) {
    return {
      tenantId: '',
      state: 'skipped',
      reason: 'missing_tenant_id',
      activeMembers: 0,
      configuredLimit: 0,
      overLimitBy: 0,
      graceCount: 0,
      deactivatedCount: 0,
    };
  }

  const tenantSnapshot =
    tenantDoc ||
    (await firestore.collection('tenants').doc(normalizedTenantId).get());

  if (!tenantSnapshot?.exists) {
    return {
      tenantId: normalizedTenantId,
      state: 'skipped',
      reason: 'tenant_not_found',
      activeMembers: 0,
      configuredLimit: 0,
      overLimitBy: 0,
      graceCount: 0,
      deactivatedCount: 0,
    };
  }

  const tenantData = tenantSnapshot.data() || {};
  const nowMs = nowDate.getTime();
  const nowIso = nowDate.toISOString();

  if (!shouldEnforceTenantSeatAllowance(tenantData)) {
    const membershipsSnapshot = await firestore
      .collection('tenant_memberships')
      .where('tenantId', '==', normalizedTenantId)
      .where('ativo', '==', true)
      .get();

    const activeMemberships = membershipsSnapshot.docs
      .map((doc) => {
        const data = doc.data() || {};
        const state = String(data.state || 'active').trim().toLowerCase();
        const uid = String(data.uid || '').trim();
        const role = String(data.role || '').trim().toLowerCase();
        return {
          doc,
          data,
          id: doc.id,
          uid,
          role,
          state,
          orderingMs: readMembershipOrderingMs(doc, nowMs),
        };
      })
      .filter((item) => item.uid && item.state === 'active');

    activeMemberships.sort((a, b) => {
      if (a.orderingMs !== b.orderingMs) {
        return a.orderingMs - b.orderingMs;
      }
      return a.uid.localeCompare(b.uid);
    });

    const ownerUid = String(tenantData.ownerUid || '').trim();
    const protectedMembershipIds = new Set(
      activeMemberships
        .filter((item) => {
          if (ownerUid && item.uid === ownerUid) {
            return true;
          }
          return item.role === 'owner';
        })
        .map((item) => item.id),
    );

    // Keep one active member for billing recovery if owner metadata is inconsistent.
    if (!protectedMembershipIds.size && activeMemberships.length > 0) {
      protectedMembershipIds.add(activeMemberships[0].id);
    }

    let irregularCount = 0;
    let deactivatedCount = 0;

    for (const membership of activeMemberships) {
      const currentState = String(membership.data.seatAccessState || '')
        .trim()
        .toLowerCase();
      const hasGraceTrail =
        String(membership.data.seatGraceUntilAt || '').trim().length > 0 ||
        String(membership.data.seatGraceStartedAt || '').trim().length > 0 ||
        String(membership.data.seatGraceReason || '').trim().length > 0 ||
        String(membership.data.seatGraceExpiredAt || '').trim().length > 0;

      if (protectedMembershipIds.has(membership.id)) {
        irregularCount += 1;
        if (currentState !== 'irregular_billing_inactive' || hasGraceTrail) {
          await membership.doc.ref.set(
            {
              seatAccessState: 'irregular_billing_inactive',
              seatGraceStartedAt: '',
              seatGraceUntilAt: '',
              seatGraceReason: 'billing_inactive_no_plan',
              seatGraceExpiredAt: '',
              seatStatusUpdatedAt: nowIso,
              updatedAt: nowIso,
            },
            { merge: true },
          );
        }
        continue;
      }

      deactivatedCount += 1;
      await membership.doc.ref.set(
        {
          ativo: false,
          state: 'inactive',
          revokedByUid: seatEnforcementActorUid,
          revokedReason: 'billing_inactive_no_plan',
          revokedAt: nowIso,
          seatAccessState: 'billing_inactive_deactivated',
          seatGraceStartedAt: '',
          seatGraceUntilAt: '',
          seatGraceReason: 'billing_inactive_no_plan',
          seatGraceExpiredAt: nowIso,
          seatStatusUpdatedAt: nowIso,
          updatedAt: nowIso,
        },
        { merge: true },
      );

      await writeTenantMembershipAuditEvent({
        firestore,
        tenantId: normalizedTenantId,
        membershipId: membership.id,
        action: 'membership_deactivated',
        actorUid: seatEnforcementActorUid,
        details: {
          reason: 'billing_inactive_no_plan',
          billingStatus: String(tenantData.billingStatus || '').trim(),
          billingPlanKey: String(tenantData.billingPlanKey || '').trim(),
        },
        createdAtIso: nowIso,
      });
    }

    await tenantSnapshot.ref.set(
      {
        seatEnforcementState: 'billing_inactive_enforced',
        seatEnforcementReason: 'billing_not_enforceable',
        seatEnforcementGraceDays: seatGraceDays,
        seatEnforcementLimitConfigured: 0,
        seatEnforcementIncludedSeats: 0,
        seatEnforcementAddonSeats: 0,
        seatEnforcementActiveMembers: irregularCount,
        seatEnforcementIrregularCount: irregularCount,
        seatEnforcementOverLimitBy: 0,
        seatEnforcementProtectedOwnerCount: irregularCount,
        seatEnforcementGraceCount: 0,
        seatEnforcementDeactivatedCount: deactivatedCount,
        seatEnforcementUpdatedAt: nowIso,
      },
      { merge: true },
    );

    return {
      tenantId: normalizedTenantId,
      state: 'billing_inactive_enforced',
      reason: 'billing_not_enforceable',
      activeMembers: irregularCount,
      configuredLimit: 0,
      overLimitBy: 0,
      graceCount: 0,
      deactivatedCount,
      irregularCount,
    };
  }

  const graceUntilIso = new Date(
    nowMs + seatGraceDays * 24 * 60 * 60 * 1000,
  ).toISOString();

  const seatConfig = readTenantSeatAllowance(tenantData);
  const membershipsSnapshot = await firestore
    .collection('tenant_memberships')
    .where('tenantId', '==', normalizedTenantId)
    .where('ativo', '==', true)
    .get();

  const activeMemberships = membershipsSnapshot.docs
    .map((doc) => {
      const data = doc.data() || {};
      const state = String(data.state || 'active').trim().toLowerCase();
      const uid = String(data.uid || '').trim();
      const role = String(data.role || '').trim().toLowerCase();
      return {
        doc,
        data,
        id: doc.id,
        uid,
        role,
        state,
        orderingMs: readMembershipOrderingMs(doc, nowMs),
      };
    })
    .filter((item) => item.uid && item.state === 'active');

  activeMemberships.sort((a, b) => {
    if (a.orderingMs !== b.orderingMs) {
      return a.orderingMs - b.orderingMs;
    }
    return a.uid.localeCompare(b.uid);
  });

  const ownerUid = String(tenantData.ownerUid || '').trim();
  const protectedOwnerMemberships = activeMemberships.filter((item) => {
    if (ownerUid && item.uid === ownerUid) {
      return true;
    }
    return item.role === 'owner';
  });
  const protectedOwnerMembershipIds = new Set(
    protectedOwnerMemberships.map((item) => item.id),
  );

  const nonOwnerMemberships = activeMemberships.filter(
    (item) => !protectedOwnerMembershipIds.has(item.id),
  );

  const availableNonOwnerSlots = Math.max(
    seatConfig.configuredLimit - protectedOwnerMemberships.length,
    0,
  );
  const keptNonOwnerMemberships = nonOwnerMemberships.slice(
    0,
    availableNonOwnerSlots,
  );

  const keptMembershipIds = new Set(
    [...protectedOwnerMemberships, ...keptNonOwnerMemberships].map(
      (item) => item.id,
    ),
  );

  let graceCount = 0;
  let deactivatedCount = 0;

  for (const membership of activeMemberships) {
    const currentState = String(membership.data.seatAccessState || '')
      .trim()
      .toLowerCase();
    const shouldRemainActive = keptMembershipIds.has(membership.id);

    if (shouldRemainActive) {
      const hasGraceTrail =
        String(membership.data.seatGraceUntilAt || '').trim().length > 0 ||
        String(membership.data.seatGraceStartedAt || '').trim().length > 0 ||
        String(membership.data.seatGraceReason || '').trim().length > 0 ||
        String(membership.data.seatGraceExpiredAt || '').trim().length > 0;

      if (currentState !== 'regular' || hasGraceTrail) {
        await membership.doc.ref.set(
          {
            seatAccessState: 'regular',
            seatGraceStartedAt: '',
            seatGraceUntilAt: '',
            seatGraceReason: '',
            seatGraceExpiredAt: '',
            seatStatusUpdatedAt: nowIso,
            updatedAt: nowIso,
          },
          { merge: true },
        );
      }
      continue;
    }

    const existingGraceUntilIso = String(
      membership.data.seatGraceUntilAt || '',
    ).trim();
    const existingGraceUntilMs = parseDateToUnixMs(existingGraceUntilIso);

    if (!existingGraceUntilMs || existingGraceUntilMs <= nowMs) {
      if (!existingGraceUntilMs) {
        graceCount += 1;
        await membership.doc.ref.set(
          {
            seatAccessState: 'over_limit_grace',
            seatGraceStartedAt: nowIso,
            seatGraceUntilAt: graceUntilIso,
            seatGraceReason: 'seat_limit_exceeded',
            seatStatusUpdatedAt: nowIso,
            updatedAt: nowIso,
          },
          { merge: true },
        );

        await writeTenantMembershipAuditEvent({
          firestore,
          tenantId: normalizedTenantId,
          membershipId: membership.id,
          action: 'membership_seat_grace_started',
          actorUid: seatEnforcementActorUid,
          details: {
            reason: 'seat_limit_exceeded',
            configuredLimit: seatConfig.configuredLimit,
            includedSeats: seatConfig.includedSeats,
            addonSeats: seatConfig.addonSeats,
            graceDays: seatGraceDays,
            graceUntilAt: graceUntilIso,
          },
          createdAtIso: nowIso,
        });
        continue;
      }

      deactivatedCount += 1;
      await membership.doc.ref.set(
        {
          ativo: false,
          state: 'inactive',
          revokedByUid: seatEnforcementActorUid,
          revokedReason: 'seat_limit_exceeded_grace_expired',
          revokedAt: nowIso,
          seatAccessState: 'over_limit_deactivated',
          seatGraceExpiredAt: nowIso,
          seatStatusUpdatedAt: nowIso,
          updatedAt: nowIso,
        },
        { merge: true },
      );

      await writeTenantMembershipAuditEvent({
        firestore,
        tenantId: normalizedTenantId,
        membershipId: membership.id,
        action: 'membership_deactivated',
        actorUid: seatEnforcementActorUid,
        details: {
          reason: 'seat_limit_exceeded_grace_expired',
          configuredLimit: seatConfig.configuredLimit,
          includedSeats: seatConfig.includedSeats,
          addonSeats: seatConfig.addonSeats,
          graceUntilAt: existingGraceUntilIso,
        },
        createdAtIso: nowIso,
      });
      continue;
    }

    graceCount += 1;
    if (currentState !== 'over_limit_grace') {
      await membership.doc.ref.set(
        {
          seatAccessState: 'over_limit_grace',
          seatGraceReason: 'seat_limit_exceeded',
          seatStatusUpdatedAt: nowIso,
          updatedAt: nowIso,
        },
        { merge: true },
      );
    }
  }

  const overLimitBy = Math.max(
    activeMemberships.length - seatConfig.configuredLimit,
    0,
  );
  const seatEnforcementState =
    overLimitBy <= 0
      ? 'within_limit'
      : deactivatedCount > 0
        ? 'over_limit_enforced'
        : 'over_limit_grace';

  await tenantSnapshot.ref.set(
    {
      seatEnforcementState,
      seatEnforcementGraceDays: seatGraceDays,
      seatEnforcementLimitConfigured: seatConfig.configuredLimit,
      seatEnforcementIncludedSeats: seatConfig.includedSeats,
      seatEnforcementAddonSeats: seatConfig.addonSeats,
      seatEnforcementActiveMembers: activeMemberships.length,
      seatEnforcementOverLimitBy: overLimitBy,
      seatEnforcementProtectedOwnerCount: protectedOwnerMemberships.length,
      seatEnforcementGraceCount: graceCount,
      seatEnforcementDeactivatedCount: deactivatedCount,
      seatEnforcementUpdatedAt: nowIso,
    },
    { merge: true },
  );

  return {
    tenantId: normalizedTenantId,
    state: seatEnforcementState,
    reason: '',
    activeMembers: activeMemberships.length,
    configuredLimit: seatConfig.configuredLimit,
    overLimitBy,
    graceCount,
    deactivatedCount,
  };
}

module.exports = {
  enforceTenantSeatAllowanceForTenant,
};
