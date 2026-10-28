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

const codigosArg = process.argv[2];
const codigosFiltro = (codigosArg ? codigosArg.split(',') : ['191', '1887', '1231'])
  .map((c) => c.trim())
  .filter(Boolean);

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

  console.log(`# Disparando sync de teste de clientes (restrito aos CODPARC: ${codigosFiltro.join(', ')})...`);
  const response = await fetch(functionUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      tenantId: creds.tenantId,
      module: 'clientes',
      environment: creds.environment,
      clientId: creds.clientId,
      clientSecret: creds.clientSecret,
      xToken: creds.xToken,
      codigosFiltro,
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

  for (const codigo of codigosFiltro) {
    const docId = `erp_cliente_${creds.tenantId}_${codigo}`;
    const snapshot = await firestore.collection('clientes').doc(docId).get();
    console.log(`# doc ${codigo} exists:`, snapshot.exists);
    console.log(`# doc ${codigo} data:`, JSON.stringify(snapshot.data() ?? null, null, 2));
  }
}

run()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('# ERRO:', error);
    process.exit(1);
  });
