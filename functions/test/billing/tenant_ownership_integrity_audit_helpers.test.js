const test = require('node:test');
const assert = require('node:assert/strict');

const {
  auditTenantOwnershipIntegrityDaily,
} = require('../../src/billing/tenant_ownership_integrity_audit_helpers');

function createAuditFirestore({ tenantsById, membershipsByTenant, usersByUid }) {
  const writes = [];

  const firestore = {
    collection(name) {
      if (name === 'tenants') {
        return {
          async get() {
            return {
              docs: Object.entries(tenantsById).map(([id, data]) => ({
                id,
                data: () => ({ ...data }),
              })),
            };
          },
          doc(id) {
            return {
              async set(patch, options) {
                writes.push({ id, patch, options });
              },
            };
          },
        };
      }

      if (name === 'tenant_memberships') {
        const filters = [];
        const chain = {
          where(field, _op, value) {
            filters.push([field, value]);
            return chain;
          },
          async get() {
            const tenantFilter = filters.find(([field]) => field === 'tenantId');
            const activeFilter = filters.find(([field]) => field === 'ativo');
            const tenantId = tenantFilter ? String(tenantFilter[1] ?? '') : '';
            const requireActive = Boolean(activeFilter ? activeFilter[1] : false);
            const rows = (membershipsByTenant[tenantId] || []).filter((row) => {
              if (!requireActive) {
                return true;
              }
              return row.ativo === true;
            });
            return {
              docs: rows.map((row) => ({
                data: () => ({ ...row }),
              })),
            };
          },
        };
        return chain;
      }

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

      throw new Error(`Unexpected collection: ${name}`);
    },
  };

  return { firestore, writes };
}

test('auditTenantOwnershipIntegrityDaily patches healthy and orphan tenants', async () => {
  const nowIso = '2026-11-18T10:00:00.000Z';
  const { firestore, writes } = createAuditFirestore({
    tenantsById: {
      tenant_ok: {
        ownerUid: '',
        billingOwnerUid: '',
      },
      tenant_orphan: {
        ownerUid: 'uid_last_owner',
      },
    },
    membershipsByTenant: {
      tenant_ok: [
        {
          uid: 'uid_owner',
          role: 'owner',
          state: 'active',
          ativo: true,
        },
      ],
      tenant_orphan: [
        {
          uid: 'uid_member',
          role: 'viewer',
          state: 'active',
          ativo: true,
        },
      ],
    },
    usersByUid: {
      uid_owner: {
        email: 'owner@example.com',
      },
      uid_last_owner: {
        userEmail: 'last.owner@example.com',
      },
    },
  });

  const summary = await auditTenantOwnershipIntegrityDaily({
    firestore,
    nowIso,
  });

  assert.equal(summary.processed, 2);
  assert.equal(summary.violations, 1);
  assert.equal(writes.length, 2);

  const okPatch = writes.find((entry) => entry.id === 'tenant_ok')?.patch;
  assert.ok(okPatch);
  assert.equal(okPatch.workspaceIntegrityState, 'ok');
  assert.equal(okPatch.workspaceAbandoned, false);
  assert.equal(okPatch.ownerUid, 'uid_owner');
  assert.equal(okPatch.billingOwnerUid, 'uid_owner');
  assert.equal(okPatch.billingOwnerEmail, 'owner@example.com');

  const orphanPatch = writes.find((entry) => entry.id === 'tenant_orphan')?.patch;
  assert.ok(orphanPatch);
  assert.equal(orphanPatch.workspaceIntegrityState, 'orphan_violation');
  assert.equal(orphanPatch.workspaceAbandoned, true);
  assert.equal(orphanPatch.workspaceIntegrityViolationAt, nowIso);
  assert.equal(orphanPatch.ownerRetentionSnapshot.lastKnownOwnerUid, 'uid_last_owner');
  assert.equal(
    orphanPatch.ownerRetentionSnapshot.lastKnownOwnerEmail,
    'last.owner@example.com',
  );
  assert.equal(orphanPatch.ownerRetentionSnapshot.capturedAt, nowIso);
  assert.equal(
    orphanPatch.ownerRetentionSnapshot.reason,
    'no_active_owner_membership',
  );
});
