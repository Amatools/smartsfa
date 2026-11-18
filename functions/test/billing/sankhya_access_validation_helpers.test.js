const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeValidateEnterpriseOwnerAccess,
} = require('../../src/billing/sankhya_access_validation_helpers');

function createFirestoreTenant(tenantData) {
  return {
    collection(name) {
      assert.equal(name, 'tenants');
      return {
        doc(id) {
          return {
            async get() {
              if (!tenantData) {
                return { exists: false, data: () => ({}) };
              }
              return { exists: true, id, data: () => tenantData };
            },
          };
        },
      };
    },
  };
}

test('executeValidateEnterpriseOwnerAccess requires bearer auth header', async () => {
  const result = await executeValidateEnterpriseOwnerAccess({
    firestore: createFirestoreTenant(null),
    request: { headers: {} },
    tenantId: 'tenant_1',
    verifyIdToken: async () => ({ uid: 'uid_1' }),
    loadTenantMembershipByTenantAndUser: async () => null,
  });

  assert.equal(result.allowed, false);
  assert.equal(result.status, 401);
  assert.equal(result.error, 'missing_firebase_auth');
});

test('executeValidateEnterpriseOwnerAccess maps verifyIdToken failure', async () => {
  const result = await executeValidateEnterpriseOwnerAccess({
    firestore: createFirestoreTenant(null),
    request: { headers: { authorization: 'Bearer token' } },
    tenantId: 'tenant_1',
    verifyIdToken: async () => {
      throw new Error('bad token');
    },
    loadTenantMembershipByTenantAndUser: async () => null,
  });

  assert.equal(result.allowed, false);
  assert.equal(result.status, 401);
  assert.equal(result.error, 'firebase_auth_failed');
});

test('executeValidateEnterpriseOwnerAccess rejects non-enterprise workspace', async () => {
  const result = await executeValidateEnterpriseOwnerAccess({
    firestore: createFirestoreTenant({ workspaceType: 'seller_workspace' }),
    request: { headers: { authorization: 'Bearer token' } },
    tenantId: 'tenant_1',
    verifyIdToken: async () => ({ uid: 'uid_1' }),
    loadTenantMembershipByTenantAndUser: async () => ({
      role: 'owner',
      state: 'active',
      ativo: true,
    }),
  });

  assert.equal(result.allowed, false);
  assert.equal(result.status, 403);
  assert.equal(result.error, 'workspace_not_allowed');
});

test('executeValidateEnterpriseOwnerAccess requires active owner membership', async () => {
  const result = await executeValidateEnterpriseOwnerAccess({
    firestore: createFirestoreTenant({ workspaceType: 'brand_owner_workspace' }),
    request: { headers: { authorization: 'Bearer token' } },
    tenantId: 'tenant_1',
    verifyIdToken: async () => ({ uid: 'uid_1' }),
    loadTenantMembershipByTenantAndUser: async () => ({
      role: 'manager',
      state: 'active',
      ativo: true,
    }),
  });

  assert.equal(result.allowed, false);
  assert.equal(result.status, 403);
  assert.equal(result.error, 'owner_required');
});

test('executeValidateEnterpriseOwnerAccess allows active owner on enterprise workspace', async () => {
  const membershipCalls = [];

  const result = await executeValidateEnterpriseOwnerAccess({
    firestore: createFirestoreTenant({ workspaceType: 'brand_owner_workspace' }),
    request: { headers: { authorization: 'Bearer token' } },
    tenantId: 'tenant_1',
    verifyIdToken: async () => ({ uid: 'uid_1' }),
    loadTenantMembershipByTenantAndUser: async (input) => {
      membershipCalls.push(input);
      return {
        role: 'owner',
        state: 'active',
        ativo: true,
      };
    },
  });

  assert.equal(result.allowed, true);
  assert.equal(result.status, 200);
  assert.equal(membershipCalls.length, 1);
  assert.equal(membershipCalls[0].tenantId, 'tenant_1');
  assert.equal(membershipCalls[0].uid, 'uid_1');
});
