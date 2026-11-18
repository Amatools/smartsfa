const test = require('node:test');
const assert = require('node:assert/strict');

const {
  assertPlatformAdminActor,
  assertTenantBillingActorPermission,
} = require('../../src/billing/actor_permission_helpers');

function createFirestore({ usersByUid = {}, membershipByDocId = {}, membershipByUid = {} }) {
  return {
    collection(name) {
      if (name === 'usuarios') {
        return {
          doc(uid) {
            return {
              async get() {
                const data = usersByUid[uid];
                return {
                  exists: data !== undefined,
                  data: () => (data ? { ...data } : undefined),
                };
              },
            };
          },
        };
      }

      if (name === 'tenant_memberships') {
        return {
          doc(id) {
            return {
              async get() {
                const data = membershipByDocId[id];
                return {
                  exists: data !== undefined,
                  data: () => (data ? { ...data } : undefined),
                };
              },
            };
          },
          where(field, op, value) {
            assert.equal(field, 'uid');
            assert.equal(op, '==');
            return {
              limit() {
                return {
                  async get() {
                    const rows = membershipByUid[value] || [];
                    return {
                      docs: rows.map((row) => ({
                        data: () => ({ ...row }),
                      })),
                    };
                  },
                };
              },
            };
          },
        };
      }

      throw new Error(`Unexpected collection ${name}`);
    },
  };
}

test('assertPlatformAdminActor validates missing uid and missing user', async () => {
  const firestore = createFirestore({ usersByUid: {} });

  const missingUid = await assertPlatformAdminActor({ firestore, uid: '' });
  assert.equal(missingUid.allowed, false);
  assert.equal(missingUid.error, 'missing_uid');

  const userNotFound = await assertPlatformAdminActor({
    firestore,
    uid: 'uid_x',
  });
  assert.equal(userNotFound.allowed, false);
  assert.equal(userNotFound.error, 'user_not_found');
});

test('assertPlatformAdminActor allows only active platform admin with console enabled', async () => {
  const firestoreForbidden = createFirestore({
    usersByUid: {
      uid_1: {
        platformRole: 'viewer',
        ativoGlobal: true,
        maintainerConsoleEnabled: true,
      },
    },
  });

  const forbidden = await assertPlatformAdminActor({
    firestore: firestoreForbidden,
    uid: 'uid_1',
  });
  assert.equal(forbidden.allowed, false);
  assert.equal(forbidden.error, 'forbidden');

  const firestoreAllowed = createFirestore({
    usersByUid: {
      uid_admin: {
        platformRole: 'platform_admin',
        ativoGlobal: true,
        maintainerConsoleEnabled: true,
      },
    },
  });

  const allowed = await assertPlatformAdminActor({
    firestore: firestoreAllowed,
    uid: 'uid_admin',
  });
  assert.equal(allowed.allowed, true);
  assert.equal(allowed.status, 200);
});

test('assertTenantBillingActorPermission allows platform admin even without membership', async () => {
  const firestore = createFirestore({
    usersByUid: {
      uid_admin: {
        platformRole: 'platform_admin',
        ativoGlobal: true,
        maintainerConsoleEnabled: true,
      },
    },
  });

  const result = await assertTenantBillingActorPermission({
    firestore,
    uid: 'uid_admin',
    tenantId: 'tenant_1',
  });

  assert.equal(result.allowed, true);
});

test('assertTenantBillingActorPermission enforces owner active membership for non-admin', async () => {
  const firestoreMissingMembership = createFirestore({
    usersByUid: {
      uid_owner: {
        platformRole: 'viewer',
      },
    },
  });

  const missingMembership = await assertTenantBillingActorPermission({
    firestore: firestoreMissingMembership,
    uid: 'uid_owner',
    tenantId: 'tenant_1',
  });
  assert.equal(missingMembership.allowed, false);
  assert.equal(missingMembership.error, 'membership_not_found');

  const firestoreNotOwner = createFirestore({
    usersByUid: {
      uid_member: {
        platformRole: 'viewer',
      },
    },
    membershipByDocId: {
      tenant_1_uid_member: {
        tenantId: 'tenant_1',
        uid: 'uid_member',
        role: 'viewer',
        state: 'active',
        ativo: true,
      },
    },
  });

  const notOwner = await assertTenantBillingActorPermission({
    firestore: firestoreNotOwner,
    uid: 'uid_member',
    tenantId: 'tenant_1',
  });
  assert.equal(notOwner.allowed, false);
  assert.equal(notOwner.error, 'owner_required');

  const firestoreOwner = createFirestore({
    usersByUid: {
      uid_owner_ok: {
        platformRole: 'viewer',
      },
    },
    membershipByUid: {
      uid_owner_ok: [
        {
          tenantId: 'tenant_1',
          uid: 'uid_owner_ok',
          role: 'owner',
          state: 'active',
          ativo: true,
        },
      ],
    },
  });

  const ownerAllowed = await assertTenantBillingActorPermission({
    firestore: firestoreOwner,
    uid: 'uid_owner_ok',
    tenantId: 'tenant_1',
  });
  assert.equal(ownerAllowed.allowed, true);
  assert.equal(ownerAllowed.status, 200);
});
