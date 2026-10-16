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

const DOMAIN_FILTER = (process.env.BACKFILL_DOMAIN_FILTER || 'smartsfa.com.br')
  .trim()
  .toLowerCase();

function resolveServiceAccountPath() {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const normalized = path.resolve(scriptDir, SERVICE_ACCOUNT_PATH);
  if (!fs.existsSync(normalized)) {
    throw new Error(`Service account nao encontrada: ${normalized}`);
  }
  return normalized;
}

function titleCaseFromEmailPrefix(emailPrefix) {
  return emailPrefix
    .replace(/[._-]+/g, ' ')
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
    .join(' ');
}

function deriveDisplayName({ authDisplayName, userDocName, userDocDisplayName, email }) {
  const normalizedAuth = (authDisplayName || '').trim();
  if (normalizedAuth.length > 0) {
    return normalizedAuth;
  }

  const normalizedDocDisplay = (userDocDisplayName || '').trim();
  if (normalizedDocDisplay.length > 0) {
    return normalizedDocDisplay;
  }

  const normalizedDocName = (userDocName || '').trim();
  if (normalizedDocName.length > 0) {
    return normalizedDocName;
  }

  const normalizedEmail = (email || '').trim().toLowerCase();
  if (normalizedEmail.length === 0 || !normalizedEmail.includes('@')) {
    return '';
  }

  const prefix = (normalizedEmail.split('@')[0] || '').trim();
  if (prefix.length > 0) {
    return titleCaseFromEmailPrefix(prefix);
  }

  return '';
}

async function listAllUsers() {
  const auth = getAuth();
  const users = [];
  let pageToken;

  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);

  return users;
}

async function main() {
  const servicePath = resolveServiceAccountPath();
  const credentials = JSON.parse(fs.readFileSync(servicePath, 'utf8'));

  initializeApp({ credential: cert(credentials) });

  const auth = getAuth();
  const db = getFirestore();
  const users = await listAllUsers();

  let updatedUsers = 0;
  let updatedMemberships = 0;

  for (const user of users) {
    const email = (user.email || '').trim().toLowerCase();
    if (DOMAIN_FILTER && !email.endsWith(`@${DOMAIN_FILTER}`)) {
      continue;
    }

    const userRef = db.collection('usuarios').doc(user.uid);
    const userSnapshot = await userRef.get();
    const userData = userSnapshot.data() || {};

    const displayName = deriveDisplayName({
      authDisplayName: user.displayName,
      userDocName: userData.name,
      userDocDisplayName: userData.displayName,
      email,
    });

    if (!displayName) {
      continue;
    }

    await userRef.set(
      {
        uid: user.uid,
        email,
        displayName,
        name: displayName,
        updatedAt: new Date().toISOString(),
      },
      { merge: true },
    );
    updatedUsers += 1;

    const memberships = await db
      .collection('tenant_memberships')
      .where('uid', '==', user.uid)
      .get();

    if (!memberships.empty) {
      const batch = db.batch();
      for (const membership of memberships.docs) {
        batch.set(
          membership.ref,
          {
            userName: displayName,
            userEmail: email,
            updatedAt: new Date().toISOString(),
          },
          { merge: true },
        );
        updatedMemberships += 1;
      }
      await batch.commit();
    }

    // Keep Auth profile aligned when missing.
    if (!(user.displayName || '').trim()) {
      try {
        await auth.updateUser(user.uid, { displayName });
      } catch (_) {
        // Best effort only.
      }
    }
  }

  console.log('Backfill concluido.');
  console.log(`usuarios atualizados: ${updatedUsers}`);
  console.log(`memberships atualizados: ${updatedMemberships}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
