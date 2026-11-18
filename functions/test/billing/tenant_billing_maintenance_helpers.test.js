const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeExpireTenantGraceDailyAction,
  executeEnforceTenantSeatAllowanceHourlyAction,
} = require('../../src/billing/tenant_billing_maintenance_helpers');

function createGraceFirestore(tenantDocs) {
  return {
    collection(name) {
      assert.equal(name, 'tenants');
      return {
        where(field, operator, value) {
          assert.equal(field, 'billingStatus');
          assert.equal(operator, '==');
          assert.equal(value, 'grace');
          return {
            async get() {
              return { docs: tenantDocs };
            },
          };
        },
      };
    },
  };
}

function createTenantDoc(data, setWrites) {
  return {
    data() {
      return data;
    },
    ref: {
      async set(payload, options) {
        setWrites.push({ payload, options });
      },
    },
  };
}

test('executeExpireTenantGraceDailyAction converts only expired grace tenants without subscription', async () => {
  const setWrites = [];
  const tenantDocs = [
    createTenantDoc({}, setWrites),
    createTenantDoc({ billingGraceUntilAt: 'invalid-date' }, setWrites),
    createTenantDoc({ billingGraceUntilAt: '2026-11-19T00:00:00.000Z' }, setWrites),
    createTenantDoc(
      {
        billingGraceUntilAt: '2026-11-17T00:00:00.000Z',
        stripeSubscriptionId: 'sub_1',
      },
      setWrites,
    ),
    createTenantDoc(
      {
        billingGraceUntilAt: '2026-11-17T00:00:00.000Z',
        stripeSubscriptionId: '',
      },
      setWrites,
    ),
  ];

  const nowDate = new Date('2026-11-18T12:00:00.000Z');
  const result = await executeExpireTenantGraceDailyAction({
    firestore: createGraceFirestore(tenantDocs),
    nowDate,
  });

  assert.equal(result.processed, 5);
  assert.equal(result.convertedNoPlan, 1);
  assert.equal(result.skippedMissingGraceUntil, 2);
  assert.equal(result.skippedNotExpiredYet, 1);
  assert.equal(result.skippedHasStripeSubscription, 1);
  assert.equal(result.updatedAt, '2026-11-18T12:00:00.000Z');

  assert.equal(setWrites.length, 1);
  assert.equal(setWrites[0].payload.billingStatus, 'no_plan');
  assert.equal(setWrites[0].payload.billingLastAutoAction, 'grace_expired_blocked');
  assert.equal(setWrites[0].payload.billingUpdatedAt, '2026-11-18T12:00:00.000Z');
  assert.deepEqual(setWrites[0].options, { merge: true });
});

function createEnforcementFirestore(tenantDocs) {
  return {
    collection(name) {
      assert.equal(name, 'tenants');
      return {
        async get() {
          return { docs: tenantDocs };
        },
      };
    },
  };
}

test('executeEnforceTenantSeatAllowanceHourlyAction aggregates summary and failures', async () => {
  const docs = [{ id: 'tenant_a' }, { id: 'tenant_b' }, { id: 'tenant_c' }, { id: 'tenant_d' }];
  const nowDate = new Date('2026-11-18T13:00:00.000Z');
  const calls = [];
  const logs = [];

  const result = await executeEnforceTenantSeatAllowanceHourlyAction({
    firestore: createEnforcementFirestore(docs),
    nowDate,
    enforceTenantSeatAllowanceForTenant: async ({ tenantId, tenantDoc, nowDate: currentNowDate }) => {
      calls.push({ tenantId, tenantDoc, nowDate: currentNowDate });
      if (tenantId === 'tenant_a') {
        return { state: 'skipped', deactivatedCount: 0 };
      }
      if (tenantId === 'tenant_b') {
        return { state: 'over_limit_grace', deactivatedCount: 0 };
      }
      if (tenantId === 'tenant_c') {
        return { state: 'ok', deactivatedCount: 2 };
      }
      throw new Error('seat_enforcement_failed');
    },
    loggerInfo: (...args) => {
      logs.push(args);
    },
  });

  assert.equal(calls.length, 4);
  assert.equal(calls[0].nowDate, nowDate);

  assert.equal(result.processed, 4);
  assert.equal(result.skipped, 1);
  assert.equal(result.overLimitGrace, 1);
  assert.equal(result.deactivated, 2);
  assert.equal(result.failures.length, 1);
  assert.equal(result.failures[0].tenantId, 'tenant_d');
  assert.equal(result.failures[0].message, 'seat_enforcement_failed');
  assert.equal(result.updatedAt, '2026-11-18T13:00:00.000Z');

  assert.equal(logs.length, 1);
  assert.equal(logs[0][0], 'enforceTenantSeatAllowanceHourly');
  assert.equal(logs[0][1].processed, 4);
  assert.equal(logs[0][1].failures, 1);
});
