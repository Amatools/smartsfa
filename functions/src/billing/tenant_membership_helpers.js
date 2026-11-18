async function loadTenantMembershipByTenantAndUser({ firestore, tenantId, uid }) {
  const memberships = firestore.collection('tenant_memberships');
  const patternDoc = await memberships.doc(`${tenantId}_${uid}`).get();
  if (patternDoc.exists) {
    return patternDoc.data() || null;
  }

  const byUidSnapshot = await memberships.where('uid', '==', uid).limit(20).get();
  for (const doc of byUidSnapshot.docs) {
    const data = doc.data() || {};
    const rowTenantId = String(data.tenantId ?? '').trim();
    if (rowTenantId === tenantId) {
      return data;
    }
  }

  return null;
}

module.exports = {
  loadTenantMembershipByTenantAndUser,
};
