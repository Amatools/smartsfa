import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const DEMO_TENANT_ID = process.env.DEMO_TENANT_ID || 'smartsfa_demo';
const FALLBACK_TENANT_ID =
  process.env.FALLBACK_TENANT_ID ||
  'self_zRRv3iXurFbl4PecT4S53HeAHjH2_representacoes-a';

const TARGET_EMAILS = [
  'owner@smartsfa.com.br',
  'representante@smartsfa.com.br',
  'vendedor@smartsfa.com.br',
  'gerente@smartsfa.com.br',
  'vendas@smartsfa.com.br',
];

const TENANT_SCOPED_COLLECTIONS = [
  'tenant_memberships',
  'tenant_invitations',
  'clientes',
  'cliente_pre_cadastros',
  'produtos',
  'tabelas_preco',
  'pedidos',
  'solicitacoes_acesso',
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

async function runBatchedDeletes(db, refs) {
  let deleted = 0;
  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    const slice = refs.slice(i, i + 400);
    for (const ref of slice) {
      batch.delete(ref);
    }
    await batch.commit();
    deleted += slice.length;
  }
  return deleted;
}

async function deleteTenantReferences(db) {
  const stats = [];
  for (const col of TENANT_SCOPED_COLLECTIONS) {
    const querySnapshot = await db
      .collection(col)
      .where('tenantId', '==', DEMO_TENANT_ID)
      .get();
    const refs = querySnapshot.docs.map((doc) => doc.ref);
    const deleted = await runBatchedDeletes(db, refs);
    stats.push({ collection: col, deleted });
  }

  const tenantRef = db.collection('tenants').doc(DEMO_TENANT_ID);
  const tenantSnap = await tenantRef.get();
  if (tenantSnap.exists) {
    await tenantRef.delete();
    stats.push({ collection: 'tenants', deleted: 1 });
  } else {
    stats.push({ collection: 'tenants', deleted: 0 });
  }

  return stats;
}

async function updateUsers(auth, db) {
  for (const email of TARGET_EMAILS) {
    try {
      const user = await auth.getUserByEmail(email);
      const uid = user.uid;
      const userRef = db.collection('usuarios').doc(uid);
      const userSnap = await userRef.get();
      const data = userSnap.data() || {};

      const patch = { updatedAt: new Date().toISOString() };
      if (data.defaultTenantId === DEMO_TENANT_ID) {
        patch.defaultTenantId = FALLBACK_TENANT_ID;
      }
      if (data.lastSelectedTenantId === DEMO_TENANT_ID) {
        patch.lastSelectedTenantId = FALLBACK_TENANT_ID;
      }

      await userRef.set(patch, { merge: true });
      console.log(`Usuario ajustado: ${email} (${uid})`);
    } catch (error) {
      if (error && error.code === 'auth/user-not-found') {
        console.log(`Usuario nao encontrado: ${email}`);
      } else {
        throw error;
      }
    }
  }
}

async function verify(db, auth) {
  console.log('\nVerificacao de referencias restantes por colecao:');
  for (const col of TENANT_SCOPED_COLLECTIONS) {
    const snapshot = await db
      .collection(col)
      .where('tenantId', '==', DEMO_TENANT_ID)
      .get();
    console.log(`- ${col}: ${snapshot.size}`);
  }
  const tenantSnap = await db.collection('tenants').doc(DEMO_TENANT_ID).get();
  console.log(`- tenants/${DEMO_TENANT_ID}: ${tenantSnap.exists ? 1 : 0}`);

  console.log('\nVerificacao de memberships para gerente e vendas:');
  for (const email of ['gerente@smartsfa.com.br', 'vendas@smartsfa.com.br']) {
    try {
      const user = await auth.getUserByEmail(email);
      const uid = user.uid;
      const m = await db
        .collection('tenant_memberships')
        .where('uid', '==', uid)
        .where('tenantId', '==', DEMO_TENANT_ID)
        .get();
      console.log(`- ${email}: ${m.size}`);
    } catch (error) {
      if (error && error.code === 'auth/user-not-found') {
        console.log(`- ${email}: usuario inexistente`);
      } else {
        throw error;
      }
    }
  }
}

async function main() {
  initializeApp({ credential: cert(loadServiceAccount()) });
  const db = getFirestore();
  const auth = getAuth();

  await updateUsers(auth, db);

  const stats = await deleteTenantReferences(db);
  console.log('\nRegistros removidos:');
  for (const item of stats) {
    console.log(`- ${item.collection}: ${item.deleted}`);
  }

  await verify(db, auth);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
