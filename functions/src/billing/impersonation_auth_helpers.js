async function verifyFirebaseAuthFromRequest({
  request,
  verifyIdToken,
}) {
  const authHeader = String(request.headers?.authorization ?? '').trim();
  if (!authHeader.toLowerCase().startsWith('bearer ')) {
    return {
      ok: false,
      status: 401,
      error: 'missing_firebase_auth',
      message: 'Envie Authorization: Bearer <Firebase ID token>.',
      uid: '',
      email: '',
    };
  }

  const idToken = authHeader.substring(7).trim();
  if (!idToken) {
    return {
      ok: false,
      status: 401,
      error: 'invalid_firebase_auth',
      message: 'Token Firebase invalido ou ausente.',
      uid: '',
      email: '',
    };
  }

  try {
    const decodedToken = await verifyIdToken(idToken);
    const uid = String(decodedToken?.uid ?? '').trim();
    if (!uid) {
      return {
        ok: false,
        status: 401,
        error: 'missing_uid',
        message: 'Usuario autenticado sem UID valido.',
        uid: '',
        email: '',
      };
    }

    return {
      ok: true,
      status: 200,
      error: '',
      message: '',
      uid,
      email: String(decodedToken?.email ?? '').trim(),
    };
  } catch (_) {
    return {
      ok: false,
      status: 401,
      error: 'firebase_auth_failed',
      message: 'Falha ao validar autenticacao Firebase.',
      uid: '',
      email: '',
    };
  }
}

function normalizeLaunchOrigin(rawOrigin, request) {
  const directOrigin = String(rawOrigin ?? '').trim();
  if (isValidHttpOrigin(directOrigin)) {
    return stripTrailingSlash(directOrigin);
  }

  const headerOrigin = String(request.headers?.origin ?? '').trim();
  if (isValidHttpOrigin(headerOrigin)) {
    return stripTrailingSlash(headerOrigin);
  }

  const host = String(request.headers?.host ?? '').trim();
  if (!host) {
    return '';
  }

  const protocol =
    String(request.headers?.['x-forwarded-proto'] ?? 'https').trim() ||
    'https';
  return stripTrailingSlash(`${protocol}://${host}`);
}

function isValidHttpOrigin(value) {
  if (!value) {
    return false;
  }
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

function stripTrailingSlash(value) {
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

function resolveRequestIp(request) {
  const forwarded = String(request.headers?.['x-forwarded-for'] ?? '').trim();
  if (forwarded) {
    return forwarded.split(',')[0].trim();
  }

  return String(request.ip ?? request.connection?.remoteAddress ?? '').trim();
}

function sha256Hex(value, { crypto }) {
  return crypto.createHash('sha256').update(String(value ?? '')).digest('hex');
}

function resolveUserDisplayLabel(userData, fallbackEmail, fallbackUid) {
  const preferred = String(
    userData.displayName ?? userData.name ?? userData.nome ?? '',
  ).trim();
  if (preferred) {
    return preferred;
  }

  const email = String(fallbackEmail ?? '').trim();
  if (email) {
    return email;
  }

  return String(fallbackUid ?? '').trim();
}

function assertImpersonationSessionConsumable({ data, sessionKeyHash, nowDate }) {
  const status = String(data.status ?? '').trim().toLowerCase();
  const consumedAt = data.consumedAt ?? null;
  const revokedAt = data.revokedAt ?? null;
  const expiresAt = data.expiresAt;
  const expiresAtDate =
    expiresAt && typeof expiresAt.toDate === 'function'
      ? expiresAt.toDate()
      : null;
  const storedHash = String(data.sessionKeyHash ?? '').trim();

  if (revokedAt != null) {
    throw new Error('session_revoked');
  }
  if (status !== 'issued' || consumedAt != null) {
    throw new Error('session_already_consumed');
  }
  if (!storedHash || storedHash !== sessionKeyHash) {
    throw new Error('invalid_session_key');
  }
  if (!expiresAtDate || expiresAtDate.getTime() <= nowDate.getTime()) {
    throw new Error('session_expired');
  }
}

function mapImpersonationConsumeError(code) {
  switch (String(code ?? '').trim()) {
    case 'session_not_found':
      return {
        status: 404,
        error: 'session_not_found',
        message: 'Sessao de acesso assistido nao encontrada.',
      };
    case 'session_revoked':
      return {
        status: 403,
        error: 'session_revoked',
        message: 'Sessao de acesso assistido revogada.',
      };
    case 'session_already_consumed':
      return {
        status: 409,
        error: 'session_already_consumed',
        message: 'Sessao de acesso assistido ja consumida.',
      };
    case 'invalid_session_key':
      return {
        status: 403,
        error: 'invalid_session_key',
        message: 'Chave da sessao de acesso assistido invalida.',
      };
    case 'session_expired':
      return {
        status: 410,
        error: 'session_expired',
        message: 'Sessao de acesso assistido expirada.',
      };
    default:
      return {
        status: 500,
        error: 'session_consume_failed',
        message: 'Falha ao consumir sessao de acesso assistido.',
      };
  }
}

module.exports = {
  verifyFirebaseAuthFromRequest,
  normalizeLaunchOrigin,
  resolveRequestIp,
  sha256Hex,
  resolveUserDisplayLabel,
  assertImpersonationSessionConsumable,
  mapImpersonationConsumeError,
  isValidHttpOrigin,
  stripTrailingSlash,
};
