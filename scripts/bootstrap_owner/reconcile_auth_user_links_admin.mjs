import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SERVICE_ACCOUNT_PATH = path.join(
  __dirname,
  process.env.SERVICE_ACCOUNT_KEY_PATH ||
    'smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json',
);

const ONLY_DOMAIN = String(process.env.RECONCILE_DOMAIN_FILTER ?? '')
  .trim()
  .toLowerCase();

function normalize(value) {
  return String(value ?? '').trim().toLowerCase();
}

function shouldIncludeUserByDomain(email) {
  if (!ONLY_DOMAIN) {
    return true;
  }
  const normalizedEmail = normalize(email);
  return normalizedEmail.endsWith(`@${ONLY_DOMAIN}`);
}

async function main() {
  const credentials = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
  initializeApp({ credential: cert(credentials), projectId: 'smart-sfa' });

  const db = getFirestore();
  const auth = getAuth();
  const nowIso = new Date().toISOString();

  const usersSnapshot = await db.collection('usuarios').get();

  const report = {
    totalUsuariosDocs: usersSnapshot.size,
    checked: 0,
    ok: 0,
    missingAuth: 0,
    skippedByDomain: 0,
    errors: 0,
  };

  for (const doc of usersSnapshot.docs) {
    const uid = String(doc.id ?? '').trim();
    if (!uid) {
      continue;
    }

    const data = doc.data() || {};
    const email = String(data.email ?? '').trim();

    if (!shouldIncludeUserByDomain(email)) {
      report.skippedByDomain += 1;
      continue;
    }

    report.checked += 1;

    try {
      await auth.getUser(uid);
      const patch = {
        authSyncStatus: 'ok',
        authLastCheckedAt: nowIso,
        authSyncMessage: '',
        authMissingSince: '',
        updatedAt: nowIso,
      };
      await doc.ref.set(patch, { merge: true });
      report.ok += 1;
    } catch (error) {
      const message = String(error?.message ?? error);
      const lower = message.toLowerCase();
      const isMissing =
        lower.includes('no user record') ||
        lower.includes('auth/user-not-found') ||
        lower.includes('not found');

      if (isMissing) {
        const currentMissingSince = String(data.authMissingSince ?? '').trim();
        const patch = {
          authSyncStatus: 'missing_auth',
          authLastCheckedAt: nowIso,
          authSyncMessage: 'Usuario inexistente no Firebase Auth.',
          authMissingSince: currentMissingSince || nowIso,
          updatedAt: nowIso,
        };
        await doc.ref.set(patch, { merge: true });
        report.missingAuth += 1;
      } else {
        await doc.ref.set(
          {
            authSyncStatus: 'error',
            authLastCheckedAt: nowIso,
            authSyncMessage: message.slice(0, 500),
            updatedAt: nowIso,
          },
          { merge: true },
        );
        report.errors += 1;
      }
    }
  }

  console.log(JSON.stringify(report, null, 2));
}

main().catch((error) => {
  console.error('RECONCILE_AUTH_USER_LINKS_ERROR', error?.message ?? String(error));
  process.exit(1);
});
