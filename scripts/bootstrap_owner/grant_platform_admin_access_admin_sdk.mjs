import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const SERVICE_ACCOUNT_PATH =
  process.env.SERVICE_ACCOUNT_KEY_PATH ||
  './smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json';

const TARGET_EMAIL = (process.env.TARGET_EMAIL ?? '').trim().toLowerCase();
const TARGET_PLATFORM_ROLE = (
  process.env.TARGET_PLATFORM_ROLE ?? 'platform_admin'
)
  .trim()
  .toLowerCase();

const MAINTAINER_CONSOLE_ENABLED = parseBool(
  process.env.MAINTAINER_CONSOLE_ENABLED,
  true,
);
const MAINTAINER_MFA_REQUIRED = parseBool(
  process.env.MAINTAINER_MFA_REQUIRED,
  false,
);
const MAINTAINER_MFA_VERIFIED = parseBool(
  process.env.MAINTAINER_MFA_VERIFIED,
  false,
);

function parseBool(rawValue, defaultValue) {
  if (rawValue == null || rawValue === '') {
    return defaultValue;
  }

  const normalized = String(rawValue).trim().toLowerCase();
  if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) {
    return true;
  }
  if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) {
    return false;
  }
  return defaultValue;
}

function resolveServiceAccountPath() {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const resolved = path.resolve(scriptDir, SERVICE_ACCOUNT_PATH);
  if (!fs.existsSync(resolved)) {
    throw new Error(`Service account nao encontrada: ${resolved}`);
  }
  return resolved;
}

function assertInputs() {
  if (!TARGET_EMAIL) {
    throw new Error('Defina TARGET_EMAIL com o e-mail da conta alvo.');
  }

  const allowedRoles = new Set([
    'platform_admin',
    'platform_observer',
    'platform_operator',
    'none',
  ]);
  if (!allowedRoles.has(TARGET_PLATFORM_ROLE)) {
    throw new Error(
      'TARGET_PLATFORM_ROLE invalido. Use platform_admin, platform_observer, platform_operator ou none.',
    );
  }
}

async function ensureUserDocument({ uid, email, displayName }) {
  const db = getFirestore();
  const userRef = db.collection('usuarios').doc(uid);
  const snapshot = await userRef.get();
  const now = new Date().toISOString();
  const existing = snapshot.data() ?? {};

  const patch = {
    ...existing,
    uid,
    email,
    displayName:
      (existing.displayName ?? existing.name ?? displayName ?? email.split('@')[0])
          .toString(),
    platformRole: TARGET_PLATFORM_ROLE,
    ativoGlobal: existing.ativoGlobal == false ? false : true,
    maintainerConsoleEnabled: MAINTAINER_CONSOLE_ENABLED,
    maintainerMfaRequired: MAINTAINER_MFA_REQUIRED,
    maintainerMfaVerified: MAINTAINER_MFA_VERIFIED,
    maintainerMfaPolicy: MAINTAINER_MFA_REQUIRED ? 'required' : 'recommended',
    maintainerAccessUpdatedAt: now,
    updatedAt: now,
  };

  await userRef.set(patch, { merge: true });
}

async function countActiveMemberships(uid) {
  const db = getFirestore();
  const snapshot = await db
    .collection('tenant_memberships')
    .where('uid', '==', uid)
    .where('ativo', '==', true)
    .where('state', '==', 'active')
    .get();
  return snapshot.size;
}

async function run() {
  assertInputs();

  const servicePath = resolveServiceAccountPath();
  const credentials = JSON.parse(fs.readFileSync(servicePath, 'utf8'));

  initializeApp({
    credential: cert(credentials),
  });

  const auth = getAuth();
  const user = await auth.getUserByEmail(TARGET_EMAIL);

  await ensureUserDocument({
    uid: user.uid,
    email: (user.email ?? TARGET_EMAIL).trim().toLowerCase(),
    displayName: user.displayName ?? undefined,
  });

  const membershipCount = await countActiveMemberships(user.uid);

  console.log('Acesso de plataforma atualizado com sucesso.');
  console.log(`uid: ${user.uid}`);
  console.log(`email: ${user.email ?? TARGET_EMAIL}`);
  console.log(`platformRole: ${TARGET_PLATFORM_ROLE}`);
  console.log(`maintainerConsoleEnabled: ${MAINTAINER_CONSOLE_ENABLED}`);
  console.log(`maintainerMfaRequired: ${MAINTAINER_MFA_REQUIRED}`);
  console.log(`maintainerMfaVerified: ${MAINTAINER_MFA_VERIFIED}`);
  console.log(`activeMemberships: ${membershipCount}`);

  if (membershipCount === 0) {
    console.log(
      'Aviso: usuario sem membership ativo. No fluxo de mantenedor isso nao bloqueia acesso quando a URL for entry=maintainer.',
    );
  }
}

run().catch((error) => {
  console.error('Falha ao conceder acesso de plataforma:', error.message);
  process.exitCode = 1;
});
