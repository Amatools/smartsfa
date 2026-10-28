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

async function run() {
  const creds = await resolveCreds();
  if (!creds) {
    throw new Error('Credenciais ERP nao encontradas.');
  }

  const firestore = getFirestore();
  const functionUrl =
    'https://us-central1-smart-sfa.cloudfunctions.net/syncSankhyaCatalogModule';

  console.log('# Disparando sync de tax_rules (SEM wipe, so re-sync com o fix de aliquota)...');
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

  const zeroAliquota = rulesSnapshot.docs.filter((doc) => {
    const d = doc.data();
    return !(d.aliquotaIcms > 0) && !(d.aliquotaSt > 0);
  });
  const nonZeroSample = rulesSnapshot.docs.filter((doc) => {
    const d = doc.data();
    return d.aliquotaIcms > 0 || d.aliquotaSt > 0;
  });

  console.log(`# total tax_rules: ${rulesSnapshot.size}`);
  console.log(`# com aliquotaIcms/aliquotaSt ambos zero/ausentes: ${zeroAliquota.length}`);
  console.log(`# com alguma aliquota > 0: ${nonZeroSample.length}`);

  console.log('# amostra (5) com aliquota > 0:');
  for (const doc of nonZeroSample.slice(0, 5)) {
    const d = doc.data();
    console.log(
      JSON.stringify({
        id: doc.id,
        ufOrigem: d.ufOrigem,
        ufDestino: d.ufDestino,
        ncm: d.ncm,
        aliquotaIcms: d.aliquotaIcms,
        aliquotaSt: d.aliquotaSt,
        mvaIva: d.mvaIva,
        aliquotaDifal: d.aliquotaDifal,
      }),
    );
  }

  console.log('# amostra (5) SP->SP:');
  const spSp = rulesSnapshot.docs.filter((doc) => {
    const d = doc.data();
    return d.ufOrigem === 'SP' && d.ufDestino === 'SP';
  });
  for (const doc of spSp.slice(0, 5)) {
    const d = doc.data();
    console.log(
      JSON.stringify({
        id: doc.id,
        ncm: d.ncm,
        aliquotaIcms: d.aliquotaIcms,
        aliquotaSt: d.aliquotaSt,
      }),
    );
  }
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
