const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const {
  verifyFirebaseAuthFromRequest,
  normalizeLaunchOrigin,
  resolveRequestIp,
  sha256Hex,
  resolveUserDisplayLabel,
  assertImpersonationSessionConsumable,
  mapImpersonationConsumeError,
  isValidHttpOrigin,
  stripTrailingSlash,
} = require('../../src/billing/impersonation_auth_helpers');

test('verifyFirebaseAuthFromRequest validates bearer header and uid', async () => {
  const missingHeader = await verifyFirebaseAuthFromRequest({
    request: { headers: {} },
    verifyIdToken: async () => ({ uid: 'u1' }),
  });
  assert.equal(missingHeader.error, 'missing_firebase_auth');

  const firebaseAuthFailed = await verifyFirebaseAuthFromRequest({
    request: { headers: { authorization: 'Bearer token_1' } },
    verifyIdToken: async () => {
      throw new Error('bad_token');
    },
  });
  assert.equal(firebaseAuthFailed.error, 'firebase_auth_failed');

  const missingUid = await verifyFirebaseAuthFromRequest({
    request: { headers: { authorization: 'Bearer token_1' } },
    verifyIdToken: async () => ({ uid: '' }),
  });
  assert.equal(missingUid.error, 'missing_uid');
});

test('verifyFirebaseAuthFromRequest returns ok payload on success', async () => {
  const result = await verifyFirebaseAuthFromRequest({
    request: { headers: { authorization: 'Bearer token_ok' } },
    verifyIdToken: async () => ({ uid: 'user_1', email: 'a@b.com' }),
  });

  assert.equal(result.ok, true);
  assert.equal(result.uid, 'user_1');
  assert.equal(result.email, 'a@b.com');
});

test('normalizeLaunchOrigin resolves direct, header and host fallback', () => {
  const direct = normalizeLaunchOrigin('https://portal.example.com/', { headers: {} });
  assert.equal(direct, 'https://portal.example.com');

  const header = normalizeLaunchOrigin('', {
    headers: { origin: 'http://localhost:3000/' },
  });
  assert.equal(header, 'http://localhost:3000');

  const hostFallback = normalizeLaunchOrigin('', {
    headers: { host: 'app.example.com', 'x-forwarded-proto': 'https' },
  });
  assert.equal(hostFallback, 'https://app.example.com');
});

test('url and ip helper utilities keep expected behavior', () => {
  assert.equal(isValidHttpOrigin('https://x.y'), true);
  assert.equal(isValidHttpOrigin('ftp://x.y'), false);
  assert.equal(stripTrailingSlash('https://x.y/'), 'https://x.y');

  const ip1 = resolveRequestIp({ headers: { 'x-forwarded-for': '10.0.0.1, 1.1.1.1' } });
  assert.equal(ip1, '10.0.0.1');
  const ip2 = resolveRequestIp({ headers: {}, ip: '127.0.0.1' });
  assert.equal(ip2, '127.0.0.1');
});

test('sha256Hex and resolveUserDisplayLabel keep expected contract', () => {
  assert.equal(
    sha256Hex('abc', { crypto }),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
  );

  assert.equal(
    resolveUserDisplayLabel({ displayName: 'Maria' }, 'x@y.com', 'uid1'),
    'Maria',
  );
  assert.equal(resolveUserDisplayLabel({}, 'x@y.com', 'uid1'), 'x@y.com');
  assert.equal(resolveUserDisplayLabel({}, '', 'uid1'), 'uid1');
});

test('assertImpersonationSessionConsumable validates session states', () => {
  const nowDate = new Date('2026-11-18T10:00:00.000Z');
  const validData = {
    status: 'issued',
    consumedAt: null,
    revokedAt: null,
    sessionKeyHash: 'h1',
    expiresAt: {
      toDate() {
        return new Date('2026-11-18T10:10:00.000Z');
      },
    },
  };

  assert.doesNotThrow(() =>
    assertImpersonationSessionConsumable({ data: validData, sessionKeyHash: 'h1', nowDate }),
  );

  assert.throws(
    () =>
      assertImpersonationSessionConsumable({
        data: { ...validData, revokedAt: {} },
        sessionKeyHash: 'h1',
        nowDate,
      }),
    /session_revoked/,
  );

  assert.throws(
    () =>
      assertImpersonationSessionConsumable({
        data: { ...validData, consumedAt: {} },
        sessionKeyHash: 'h1',
        nowDate,
      }),
    /session_already_consumed/,
  );

  assert.throws(
    () =>
      assertImpersonationSessionConsumable({
        data: validData,
        sessionKeyHash: 'invalid',
        nowDate,
      }),
    /invalid_session_key/,
  );
});

test('mapImpersonationConsumeError maps known and default errors', () => {
  assert.equal(mapImpersonationConsumeError('session_not_found').status, 404);
  assert.equal(mapImpersonationConsumeError('session_revoked').status, 403);
  assert.equal(mapImpersonationConsumeError('session_already_consumed').status, 409);
  assert.equal(mapImpersonationConsumeError('invalid_session_key').status, 403);
  assert.equal(mapImpersonationConsumeError('session_expired').status, 410);
  assert.equal(mapImpersonationConsumeError('unknown').status, 500);
});
