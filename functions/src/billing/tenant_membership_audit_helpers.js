async function writeTenantMembershipAuditEvent({
  firestore,
  tenantId,
  membershipId,
  action,
  actorUid,
  details,
  createdAtIso,
}) {
  await firestore.collection('tenant_membership_audit').add({
    tenantId,
    membershipId,
    action,
    actorUid,
    actorLabel: actorUid,
    details: details || {},
    createdAt: createdAtIso,
  });
}

module.exports = {
  writeTenantMembershipAuditEvent,
};
