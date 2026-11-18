const test = require('node:test');
const assert = require('node:assert/strict');

const {
  enforceTenantSeatAllowanceForTenant,
} = require('../../src/billing/seat_enforcement_runtime_helpers');

function createSeatEnforcementFirestore({ tenantId, tenantData, memberships }) {
  const tenantWrites = [];
  const membershipWrites = [];

  const firestore = {
    collection(name) {
      if (name === 'tenants') {
        return {
          doc(id) {
            return {
              async get() {
                if (id !== tenantId) {
                  return {
                    exists: false,
                    data: () => undefined,
                    ref: {
                      async set() {},
                    },
                  };
                }
                return {
                  exists: true,
                  data: () => ({ ...tenantData }),
                  ref: {
                    async set(patch, options) {
                      tenantWrites.push({ id, patch, options });
                    },
                  },
                };
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
            const byTenant = filters.find(([field]) => field === 'tenantId');
            const byActive = filters.find(([field]) => field === 'ativo');
            const expectedTenantId = byTenant ? String(byTenant[1] ?? '') : '';
            const expectedAtivo = byActive ? Boolean(byActive[1]) : false;

            const docs = memberships
              .filter((item) => {
                if (String(item.data.tenantId ?? '') !== expectedTenantId) {
                  return false;
                }
                if (expectedAtivo && item.data.ativo !== true) {
                  return false;
                }
                return true;
              })
              .map((item) => ({
                id: item.id,
                data: () => ({ ...item.data }),
                ref: {
                  async set(patch, options) {
                    membershipWrites.push({ id: item.id, patch, options });
                  },
                },
              }));

            return { docs };
          },
        };
        return chain;
      }

      throw new Error(`Unexpected collection: ${name}`);
    },
  };

  return {
    firestore,
    tenantWrites,
    membershipWrites,
  };
}

function parseDateToUnixMs(value) {
  const ms = Date.parse(String(value ?? '').trim());
  return Number.isFinite(ms) ? ms : 0;
}

test('enforceTenantSeatAllowanceForTenant returns skipped for missing tenant id', async () => {
  const result = await enforceTenantSeatAllowanceForTenant({
    firestore: {},
    tenantId: '',
    shouldEnforceTenantSeatAllowance: () => true,
    readTenantSeatAllowance: () => ({ configuredLimit: 1, includedSeats: 1, addonSeats: 0 }),
    readMembershipOrderingMs: () => 0,
    parseDateToUnixMs,
    writeTenantMembershipAuditEvent: async () => {},
    seatGraceDays: 3,
    seatEnforcementActorUid: 'system',
  });

  assert.equal(result.state, 'skipped');
  assert.equal(result.reason, 'missing_tenant_id');
});

test('enforceTenantSeatAllowanceForTenant skips when billing is not enforceable', async () => {
  const { firestore, tenantWrites, membershipWrites } = createSeatEnforcementFirestore({
    tenantId: 'tenant_skip',
    tenantData: {
      billingStatus: 'no_plan',
    },
    memberships: [],
  });

  const result = await enforceTenantSeatAllowanceForTenant({
    firestore,
    tenantId: 'tenant_skip',
    shouldEnforceTenantSeatAllowance: () => false,
    readTenantSeatAllowance: () => ({ configuredLimit: 1, includedSeats: 1, addonSeats: 0 }),
    readMembershipOrderingMs: () => 0,
    parseDateToUnixMs,
    writeTenantMembershipAuditEvent: async () => {},
    seatGraceDays: 3,
    seatEnforcementActorUid: 'system',
  });

  assert.equal(result.state, 'skipped');
  assert.equal(result.reason, 'billing_not_enforceable');
  assert.equal(tenantWrites.length, 0);
  assert.equal(membershipWrites.length, 0);
});

test('enforceTenantSeatAllowanceForTenant puts overflow member in grace period', async () => {
  const auditCalls = [];
  const nowDate = new Date('2026-11-18T00:00:00.000Z');
  const { firestore, tenantWrites, membershipWrites } = createSeatEnforcementFirestore({
    tenantId: 'tenant_grace',
    tenantData: {
      ownerUid: 'uid_owner',
    },
    memberships: [
      {
        id: 'm_owner',
        data: {
          tenantId: 'tenant_grace',
          uid: 'uid_owner',
          role: 'owner',
          state: 'active',
          ativo: true,
          seatAccessState: 'regular',
          order: 1,
        },
      },
      {
        id: 'm_viewer',
        data: {
          tenantId: 'tenant_grace',
          uid: 'uid_viewer',
          role: 'viewer',
          state: 'active',
          ativo: true,
          order: 2,
        },
      },
    ],
  });

  const result = await enforceTenantSeatAllowanceForTenant({
    firestore,
    tenantId: 'tenant_grace',
    nowDate,
    shouldEnforceTenantSeatAllowance: () => true,
    readTenantSeatAllowance: () => ({ configuredLimit: 1, includedSeats: 1, addonSeats: 0 }),
    readMembershipOrderingMs: (doc) => Number(doc.data().order ?? 0),
    parseDateToUnixMs,
    writeTenantMembershipAuditEvent: async (payload) => {
      auditCalls.push(payload);
    },
    seatGraceDays: 3,
    seatEnforcementActorUid: 'system_seat_enforcement',
  });

  assert.equal(result.state, 'over_limit_grace');
  assert.equal(result.graceCount, 1);
  assert.equal(result.deactivatedCount, 0);
  assert.equal(result.overLimitBy, 1);

  assert.equal(auditCalls.length, 1);
  assert.equal(auditCalls[0].action, 'membership_seat_grace_started');

  const viewerPatch = membershipWrites.find((item) => item.id === 'm_viewer')?.patch;
  assert.ok(viewerPatch);
  assert.equal(viewerPatch.seatAccessState, 'over_limit_grace');

  assert.equal(tenantWrites.length, 1);
  assert.equal(tenantWrites[0].patch.seatEnforcementState, 'over_limit_grace');
});

test('enforceTenantSeatAllowanceForTenant deactivates member when grace is expired', async () => {
  const auditCalls = [];
  const nowDate = new Date('2026-11-18T00:00:00.000Z');
  const { firestore, tenantWrites, membershipWrites } = createSeatEnforcementFirestore({
    tenantId: 'tenant_deactivate',
    tenantData: {
      ownerUid: 'uid_owner',
    },
    memberships: [
      {
        id: 'm_owner',
        data: {
          tenantId: 'tenant_deactivate',
          uid: 'uid_owner',
          role: 'owner',
          state: 'active',
          ativo: true,
          seatAccessState: 'regular',
          order: 1,
        },
      },
      {
        id: 'm_old_grace',
        data: {
          tenantId: 'tenant_deactivate',
          uid: 'uid_old',
          role: 'viewer',
          state: 'active',
          ativo: true,
          seatAccessState: 'over_limit_grace',
          seatGraceUntilAt: '2026-11-01T00:00:00.000Z',
          order: 2,
        },
      },
    ],
  });

  const result = await enforceTenantSeatAllowanceForTenant({
    firestore,
    tenantId: 'tenant_deactivate',
    nowDate,
    shouldEnforceTenantSeatAllowance: () => true,
    readTenantSeatAllowance: () => ({ configuredLimit: 1, includedSeats: 1, addonSeats: 0 }),
    readMembershipOrderingMs: (doc) => Number(doc.data().order ?? 0),
    parseDateToUnixMs,
    writeTenantMembershipAuditEvent: async (payload) => {
      auditCalls.push(payload);
    },
    seatGraceDays: 3,
    seatEnforcementActorUid: 'system_seat_enforcement',
  });

  assert.equal(result.state, 'over_limit_enforced');
  assert.equal(result.graceCount, 0);
  assert.equal(result.deactivatedCount, 1);

  const deactivatedPatch = membershipWrites.find((item) => item.id === 'm_old_grace')?.patch;
  assert.ok(deactivatedPatch);
  assert.equal(deactivatedPatch.ativo, false);
  assert.equal(deactivatedPatch.state, 'inactive');
  assert.equal(deactivatedPatch.seatAccessState, 'over_limit_deactivated');

  assert.equal(auditCalls.length, 1);
  assert.equal(auditCalls[0].action, 'membership_deactivated');
  assert.equal(tenantWrites[0].patch.seatEnforcementState, 'over_limit_enforced');
});
