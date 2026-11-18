const test = require('node:test');
const assert = require('node:assert/strict');

const {
  loadTenantMembershipByTenantAndUser,
} = require('../../src/billing/tenant_membership_helpers');

function createMembershipFirestore({ byDocId = {}, byUid = {} }) {
  return {
    collection(name) {
      assert.equal(name, 'tenant_memberships');
      return {
        doc(id) {
          return {
            async get() {
              const data = byDocId[id];
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
                  const entries = byUid[value] || [];
                  return {
                    docs: entries.map((item) => ({
                      data: () => ({ ...item }),
                    })),
                  };
                },
              };
            },
          };
        },
      };
    },
  };
}

test('loadTenantMembershipByTenantAndUser returns pattern document when present', async () => {
  const firestore = createMembershipFirestore({
    byDocId: {
      tenant_1_uid_1: {
        tenantId: 'tenant_1',
        uid: 'uid_1',
        role: 'owner',
      },
    },
  });

  const membership = await loadTenantMembershipByTenantAndUser({
    firestore,
    tenantId: 'tenant_1',
    uid: 'uid_1',
  });

  assert.equal(membership.tenantId, 'tenant_1');
  assert.equal(membership.uid, 'uid_1');
});

test('loadTenantMembershipByTenantAndUser falls back to query by uid', async () => {
  const firestore = createMembershipFirestore({
    byUid: {
      uid_2: [
        { tenantId: 'tenant_other', uid: 'uid_2', role: 'viewer' },
        { tenantId: 'tenant_target', uid: 'uid_2', role: 'owner' },
      ],
    },
  });

  const membership = await loadTenantMembershipByTenantAndUser({
    firestore,
    tenantId: 'tenant_target',
    uid: 'uid_2',
  });

  assert.equal(membership.tenantId, 'tenant_target');
  assert.equal(membership.role, 'owner');
});

test('loadTenantMembershipByTenantAndUser returns null when no membership matches tenant', async () => {
  const firestore = createMembershipFirestore({
    byUid: {
      uid_3: [
        { tenantId: 'tenant_other', uid: 'uid_3', role: 'owner' },
      ],
    },
  });

  const membership = await loadTenantMembershipByTenantAndUser({
    firestore,
    tenantId: 'tenant_missing',
    uid: 'uid_3',
  });

  assert.equal(membership, null);
});
