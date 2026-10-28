import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const serviceAccountPath = path.join(
  __dirname,
  'smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json',
);
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
initializeApp({ credential: cert(serviceAccount) });

async function resolveCreds() {
  const user = await getAuth().getUserByEmail('enterprise@smartsfa.com.br');
  const memberships = await getFirestore()
    .collection('tenant_memberships')
    .where('uid', '==', user.uid)
    .get();

  for (const membership of memberships.docs) {
    const tenantId = membership.data().tenantId;
    const tenant = (
      await getFirestore().collection('tenants').doc(tenantId).get()
    ).data() ?? {};
    const c = tenant.erpIntegration?.credentials ?? {};
    if (c.username && c.password && c.accessToken) {
      return {
        tenantId,
        environment: String(tenant.erpIntegration?.environment ?? 'prod').trim().toLowerCase(),
        clientId: String(c.username).trim(),
        clientSecret: String(c.password).trim(),
        xToken: String(c.accessToken).trim(),
      };
    }
  }
  return null;
}

async function wipeCollection({ firestore, collectionName, filterFn, label }) {
  const snapshot = await firestore.collection(collectionName).get();
  const writer = firestore.bulkWriter();
  writer.onWriteError((error) => error.failedAttempts < 3);
  let deleted = 0;
  for (const doc of snapshot.docs) {
    if (filterFn && !filterFn(doc)) {
      continue;
    }
    writer.delete(doc.ref);
    deleted += 1;
  }
  await writer.close();
  console.log(`# ${label}: ${deleted} documento(s) apagado(s) (de ${snapshot.size} lidos).`);
  return deleted;
}

async function run() {
  const creds = await resolveCreds();
  if (!creds) {
    throw new Error('Credenciais ERP nao encontradas.');
  }

  const firestore = getFirestore();

  console.log(`# Zerando matriz tributaria do tenant ${creds.tenantId}...`);
  await wipeCollection({
    firestore,
    collectionName: 'tax_rules',
    filterFn: (doc) => doc.data().tenantId === creds.tenantId,
    label: 'tax_rules (todas as origens) apagadas',
  });
  await wipeCollection({
    firestore,
    collectionName: 'tax_rule_groups',
    filterFn: (doc) => doc.data().tenantId === creds.tenantId && doc.data().source === 'erp_sync',
    label: 'tax_rule_groups (source=erp_sync) apagados',
  });

  const functionUrl =
    'https://us-central1-smart-sfa.cloudfunctions.net/syncSankhyaCatalogModule';

  console.log('# Disparando sync de tax_rules...');
  const response = await fetch(functionUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      tenantId: creds.tenantId,
      module: 'tax_rules',
      environment: creds.environment,
      clientId: creds.clientId,
      clientSecret: creds.clientSecret,
      xToken: creds.xToken,
    }),
  });

  const text = await response.text();
  let payload = {};
  try {
    payload = JSON.parse(text);
  } catch {
    payload = { raw: text };
  }

  console.log('# sync result:', JSON.stringify({ status: response.status, ...payload }, null, 2));

  const rulesSnapshot = await firestore
    .collection('tax_rules')
    .where('tenantId', '==', creds.tenantId)
    .get();
  const groupsSnapshot = await firestore
    .collection('tax_rule_groups')
    .where('tenantId', '==', creds.tenantId)
    .get();

  const withTaxGroupId = rulesSnapshot.docs.filter((doc) => doc.data().taxGroupId);
  const withNcmOnly = rulesSnapshot.docs.filter(
    (doc) => doc.data().ncm && !doc.data().taxGroupId,
  );
  const genericRows = rulesSnapshot.docs.filter(
    (doc) => !doc.data().ncm && !doc.data().taxGroupId,
  );

  console.log(`# total tax_rules apos sync: ${rulesSnapshot.size}`);
  console.log(`#   com taxGroupId (grupo): ${withTaxGroupId.length}`);
  console.log(`#   com ncm, sem grupo (singleton): ${withNcmOnly.length}`);
  console.log(`#   genericas por UF (sem ncm/grupo): ${genericRows.length}`);
  console.log(`# total tax_rule_groups apos sync: ${groupsSnapshot.size}`);

  for (const doc of groupsSnapshot.docs.slice(0, 5)) {
    const d = doc.data();
    console.log(
      JSON.stringify({
        groupId: doc.id,
        name: d.name,
        memberNcmCount: d.memberNcmCount,
        source: d.source,
      }),
    );
  }
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
