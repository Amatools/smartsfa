const test = require('node:test');
const assert = require('node:assert/strict');

const {
  writeTenantMembershipAuditEvent,
} = require('../../src/billing/tenant_membership_audit_helpers');

test('writeTenantMembershipAuditEvent writes normalized audit payload', async () => {
  const writes = [];
  const firestore = {
    collection(name) {
      assert.equal(name, 'tenant_membership_audit');
      return {
        async add(payload) {
          writes.push(payload);
        },
      };
    },
  };

  await writeTenantMembershipAuditEvent({
    firestore,
    tenantId: 'tenant_1',
    membershipId: 'membership_1',
    action: 'membership_deactivated',
    actorUid: 'system',
    details: { reason: 'seat_limit_exceeded' },
    createdAtIso: '2026-01-01T00:00:00.000Z',
  });

  assert.equal(writes.length, 1);
  assert.deepEqual(writes[0], {
    tenantId: 'tenant_1',
    membershipId: 'membership_1',
    action: 'membership_deactivated',
    actorUid: 'system',
    actorLabel: 'system',
    details: { reason: 'seat_limit_exceeded' },
    createdAt: '2026-01-01T00:00:00.000Z',
  });
});
