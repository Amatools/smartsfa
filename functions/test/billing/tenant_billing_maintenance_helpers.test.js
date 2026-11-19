const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeExpireTenantGraceDailyAction,
  executeEnforceTenantSeatAllowanceHourlyAction,
  executeExpireBillingQuotesHourlyAction,
  executeExpireLegacyOpenBillingQuotesDailyAction,
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

function createQuoteDoc(data, setWrites) {
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

function createQuotesFirestore(quoteDocs) {
  return {
    collection(name) {
      assert.equal(name, 'billing_quotes');
      return {
        where(field, operator, value) {
          assert.equal(field, 'status');
          assert.equal(operator, '==');
          assert.equal(value, 'open');
          return {
            async get() {
              return { docs: quoteDocs };
            },
          };
        },
      };
    },
  };
}

test('executeExpireBillingQuotesHourlyAction expires only open quotes past due', async () => {
  const setWrites = [];
  const quoteDocs = [
    createQuoteDoc({}, setWrites),
    createQuoteDoc({ expiresAt: 'invalid-date' }, setWrites),
    createQuoteDoc({ expiresAt: '2026-11-19T13:30:00.000Z' }, setWrites),
    createQuoteDoc({ expiresAt: '2026-11-19T11:59:59.000Z' }, setWrites),
  ];

  const nowDate = new Date('2026-11-19T12:00:00.000Z');
  const result = await executeExpireBillingQuotesHourlyAction({
    firestore: createQuotesFirestore(quoteDocs),
    nowDate,
  });

  assert.equal(result.processed, 4);
  assert.equal(result.expired, 1);
  assert.equal(result.skippedMissingExpiresAt, 1);
  assert.equal(result.skippedInvalidExpiresAt, 1);
  assert.equal(result.skippedNotExpiredYet, 1);
  assert.equal(result.updatedAt, '2026-11-19T12:00:00.000Z');

  assert.equal(setWrites.length, 1);
  assert.equal(setWrites[0].payload.status, 'expired');
  assert.equal(setWrites[0].payload.expiredAt, '2026-11-19T12:00:00.000Z');
  assert.equal(setWrites[0].payload.expirationReason, 'ttl_elapsed');
  assert.deepEqual(setWrites[0].options, { merge: true });
});

test('executeExpireLegacyOpenBillingQuotesDailyAction sanitizes only legacy open quotes with missing or invalid expiresAt', async () => {
  const setWrites = [];
  const quoteDocs = [
    createQuoteDoc({}, setWrites),
    createQuoteDoc({ expiresAt: 'not-a-date' }, setWrites),
    createQuoteDoc({ expiresAt: '2026-11-19T13:30:00.000Z' }, setWrites),
  ];

  const nowDate = new Date('2026-11-19T12:00:00.000Z');
  const result = await executeExpireLegacyOpenBillingQuotesDailyAction({
    firestore: createQuotesFirestore(quoteDocs),
    nowDate,
  });

  assert.equal(result.processed, 3);
  assert.equal(result.expiredLegacyMissingExpiresAt, 1);
  assert.equal(result.expiredLegacyInvalidExpiresAt, 1);
  assert.equal(result.skippedHasValidExpiresAt, 1);
  assert.equal(result.updatedAt, '2026-11-19T12:00:00.000Z');

  assert.equal(setWrites.length, 2);
  assert.equal(setWrites[0].payload.status, 'expired');
  assert.equal(setWrites[0].payload.expirationReason, 'legacy_missing_expires_at');
  assert.equal(setWrites[0].payload.sanitationAction, 'expire_legacy_open_quotes_daily');
  assert.deepEqual(setWrites[0].options, { merge: true });

  assert.equal(setWrites[1].payload.status, 'expired');
  assert.equal(setWrites[1].payload.expirationReason, 'legacy_invalid_expires_at');
  assert.equal(setWrites[1].payload.sanitationAction, 'expire_legacy_open_quotes_daily');
  assert.deepEqual(setWrites[1].options, { merge: true });
});
