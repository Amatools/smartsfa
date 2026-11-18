async function auditTenantOwnershipIntegrityDaily({
  firestore,
  nowIso = new Date().toISOString(),
}) {
  const tenantsSnapshot = await firestore.collection('tenants').get();
  let processed = 0;
  let violations = 0;

  for (const tenantDoc of tenantsSnapshot.docs) {
    const tenantId = String(tenantDoc.id ?? '').trim();
    if (!tenantId) {
      continue;
    }

    const tenantData = tenantDoc.data() || {};
    const membershipsSnapshot = await firestore
      .collection('tenant_memberships')
      .where('tenantId', '==', tenantId)
      .where('ativo', '==', true)
      .get();

    const activeOwnerUids = [];
    for (const membershipDoc of membershipsSnapshot.docs) {
      const membership = membershipDoc.data() || {};
      const role = String(membership.role || '').trim().toLowerCase();
      const state = String(membership.state || 'active').trim().toLowerCase();
      const uid = String(membership.uid || '').trim();
      if (role === 'owner' && state === 'active' && uid) {
        activeOwnerUids.push(uid);
      }
    }

    const uniqueOwnerUids = [...new Set(activeOwnerUids)];
    const patch = {
      workspaceIntegrityUpdatedAt: nowIso,
    };

    if (uniqueOwnerUids.length > 0) {
      patch.workspaceIntegrityState = 'ok';
      patch.workspaceAbandoned = false;
      if (!String(tenantData.ownerUid || '').trim()) {
        patch.ownerUid = uniqueOwnerUids[0];
      }

      const billingOwnerUid = String(tenantData.billingOwnerUid || '').trim();
      if (!billingOwnerUid) {
        patch.billingOwnerUid = uniqueOwnerUids[0];
        const ownerDoc = await firestore
          .collection('usuarios')
          .doc(uniqueOwnerUids[0])
          .get();
        const ownerData = ownerDoc.data() || {};
        patch.billingOwnerEmail = String(
          ownerData.email || ownerData.userEmail || '',
        ).trim();
      }
    } else {
      violations += 1;
      patch.workspaceIntegrityState = 'orphan_violation';
      patch.workspaceAbandoned = true;
      patch.workspaceIntegrityViolationAt =
        String(tenantData.workspaceIntegrityViolationAt || '').trim() || nowIso;

      const lastKnownOwnerUid = String(tenantData.ownerUid || '').trim();
      let lastKnownOwnerEmail = '';
      if (lastKnownOwnerUid) {
        const ownerDoc = await firestore
          .collection('usuarios')
          .doc(lastKnownOwnerUid)
          .get();
        const ownerData = ownerDoc.data() || {};
        lastKnownOwnerEmail = String(
          ownerData.email || ownerData.userEmail || '',
        ).trim();
      }

      patch.ownerRetentionSnapshot = {
        lastKnownOwnerUid,
        lastKnownOwnerEmail,
        capturedAt: nowIso,
        reason: 'no_active_owner_membership',
      };
    }

    await firestore.collection('tenants').doc(tenantId).set(patch, {
      merge: true,
    });
    processed += 1;
  }

  return {
    processed,
    violations,
  };
}

module.exports = {
  auditTenantOwnershipIntegrityDaily,
};
