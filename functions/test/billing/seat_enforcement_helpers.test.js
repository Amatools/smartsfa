const test = require('node:test');
const assert = require('node:assert/strict');

const {
  parseDateToUnixMs,
  readMembershipOrderingMs,
  readTenantSeatAllowance,
  resolveDefaultIncludedSeatsForTenant,
  shouldEnforceTenantSeatAllowance,
} = require('../../src/billing/seat_enforcement_helpers');

test('parseDateToUnixMs supports date, timestamp-like and string values', () => {
  const iso = '2026-01-02T03:04:05.000Z';
  const expected = new Date(iso).getTime();

  assert.equal(parseDateToUnixMs(new Date(iso)), expected);
  assert.equal(parseDateToUnixMs({ toDate: () => new Date(iso) }), expected);
  assert.equal(parseDateToUnixMs(123), 123);
  assert.equal(parseDateToUnixMs(0), 0);
  assert.equal(parseDateToUnixMs(iso), expected);
  assert.equal(parseDateToUnixMs('invalid-date'), 0);
  assert.equal(parseDateToUnixMs(null), 0);
});

test('readMembershipOrderingMs picks first valid date candidate', () => {
  const nowMs = Date.now();
  const activatedIso = '2026-04-10T10:00:00.000Z';
  const updatedIso = '2026-04-12T10:00:00.000Z';
  const createTimeIso = '2026-04-13T10:00:00.000Z';

  const membershipDoc = {
    data: () => ({
      activatedAt: activatedIso,
      updatedAt: updatedIso,
    }),
    createTime: { toDate: () => new Date(createTimeIso) },
  };

  assert.equal(
    readMembershipOrderingMs(membershipDoc, nowMs),
    new Date(activatedIso).getTime(),
  );
});

test('readMembershipOrderingMs falls back to createTime and then nowMs', () => {
  const nowMs = Date.now();
  const createTimeIso = '2026-04-13T10:00:00.000Z';

  const withCreateTime = {
    data: () => ({ activatedAt: '' }),
    createTime: { toDate: () => new Date(createTimeIso) },
  };
  assert.equal(
    readMembershipOrderingMs(withCreateTime, nowMs),
    new Date(createTimeIso).getTime(),
  );

  const withoutDates = {
    data: () => ({}),
    createTime: null,
  };
  assert.equal(readMembershipOrderingMs(withoutDates, nowMs), nowMs);
});

test('resolveDefaultIncludedSeatsForTenant uses planTier seats when present', () => {
  assert.equal(
    resolveDefaultIncludedSeatsForTenant({ planTier: 'enterprise_8_seats' }),
    8,
  );
});

test('resolveDefaultIncludedSeatsForTenant maps workspace and plan defaults', () => {
  assert.equal(
    resolveDefaultIncludedSeatsForTenant({ workspaceType: 'brand_owner_workspace' }),
    3,
  );
  assert.equal(
    resolveDefaultIncludedSeatsForTenant({ billingPlanKey: 'enterprise' }),
    3,
  );
  assert.equal(
    resolveDefaultIncludedSeatsForTenant({ workspaceType: 'seller_solo_workspace' }),
    1,
  );
  assert.equal(resolveDefaultIncludedSeatsForTenant({}), 1);
});

test('readTenantSeatAllowance computes configured limits with fallback', () => {
  assert.deepEqual(
    readTenantSeatAllowance({
      billingSeatsIncluded: 2,
      billingSeatsAddon: 3,
    }),
    {
      includedSeats: 2,
      addonSeats: 3,
      configuredLimit: 5,
    },
  );

  assert.deepEqual(
    readTenantSeatAllowance({
      planTier: 'enterprise_4',
      billingSeatAddons: 2,
    }),
    {
      includedSeats: 4,
      addonSeats: 2,
      configuredLimit: 6,
    },
  );
});

test('shouldEnforceTenantSeatAllowance requires active billing status and plan', () => {
  assert.equal(
    shouldEnforceTenantSeatAllowance({
      billingStatus: 'active',
      billingPlanKey: 'solo',
    }),
    true,
  );
  assert.equal(
    shouldEnforceTenantSeatAllowance({
      billingStatus: 'trial',
      billingPlanKey: 'enterprise',
    }),
    true,
  );
  assert.equal(
    shouldEnforceTenantSeatAllowance({
      billingStatus: 'canceled',
      billingPlanKey: 'solo',
    }),
    false,
  );
  assert.equal(
    shouldEnforceTenantSeatAllowance({
      billingStatus: 'active',
      billingPlanKey: '',
    }),
    false,
  );
});
