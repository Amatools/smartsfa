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

  const functionUrl =
    'https://us-central1-smart-sfa.cloudfunctions.net/syncSankhyaCatalogModule';

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

  // Verifica amostra de regras com DIFAL/FCP derivados recem-sincronizadas
  const snapshot = await getFirestore()
    .collection('tax_rules')
    .where('tenantId', '==', creds.tenantId)
    .where('origin', '==', 'erp')
    .get();

  const withDifal = snapshot.docs.filter((doc) => (doc.data().aliquotaDifal ?? 0) > 0);
  const withFcp = snapshot.docs.filter((doc) => (doc.data().aliquotaFcp ?? 0) > 0);

  console.log(`# total regras erp: ${snapshot.size}`);
  console.log(`# regras com aliquotaDifal > 0: ${withDifal.length}`);
  console.log(`# regras com aliquotaFcp > 0: ${withFcp.length}`);
  for (const doc of withDifal.slice(0, 5)) {
    const d = doc.data();
    console.log(
      JSON.stringify({
        id: doc.id,
        ncm: d.ncm,
        ufOrigem: d.ufOrigem,
        ufDestino: d.ufDestino,
        aliquotaDestino: d.aliquotaDestino,
        aliquotaCredito: d.aliquotaCredito,
        aliquotaDifal: d.aliquotaDifal,
        aliquotaFcp: d.aliquotaFcp ?? null,
        aliquotaFcpSt: d.aliquotaFcpSt ?? null,
      }),
    );
  }
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
