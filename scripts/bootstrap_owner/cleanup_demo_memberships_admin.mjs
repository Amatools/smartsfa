import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const DEMO_TENANT_ID = process.env.DEMO_TENANT_ID || 'smartsfa_demo';
const TARGET_DEFAULT_TENANT =
  process.env.TARGET_DEFAULT_TENANT ||
  'self_zRRv3iXurFbl4PecT4S53HeAHjH2_representacoes-a';
const EMAILS = [
  'owner@smartsfa.com.br',
  'representante@smartsfa.com.br',
  'vendedor@smartsfa.com.br',
];

function loadServiceAccount() {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const keyPath = path.resolve(
    scriptDir,
    process.env.SERVICE_ACCOUNT_KEY_PATH ||
      './smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json',
  );
  return JSON.parse(fs.readFileSync(keyPath, 'utf8'));
}

async function cleanupUser(email) {
  const auth = getAuth();
  const db = getFirestore();
  const user = await auth.getUserByEmail(email);
  const uid = user.uid;

  const memberships = await db
    .collection('tenant_memberships')
    .where('uid', '==', uid)
    .get();

  const batch = db.batch();
  for (const doc of memberships.docs) {
    const data = doc.data();
    if (data.tenantId === DEMO_TENANT_ID) {
      batch.set(
        doc.ref,
        {
          ativo: false,
          state: 'revoked',
          defaultTenant: false,
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
    } else if (data.tenantId === TARGET_DEFAULT_TENANT) {
      batch.set(
        doc.ref,
        {
          defaultTenant: true,
          ativo: true,
          state: 'active',
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
    } else {
      batch.set(
        doc.ref,
        {
          defaultTenant: false,
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
    }
  }

  batch.set(
    db.collection('usuarios').doc(uid),
    {
      defaultTenantId: TARGET_DEFAULT_TENANT,
      lastSelectedTenantId: TARGET_DEFAULT_TENANT,
      updatedAt: new Date().toISOString(),
    },
    { merge: true },
  );

  await batch.commit();
  console.log(`Limpeza concluida para ${email} (${uid}).`);
}

async function main() {
  initializeApp({ credential: cert(loadServiceAccount()) });
  for (const email of EMAILS) {
    await cleanupUser(email);
  }
  console.log('Limpeza de memberships demo concluida.');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
