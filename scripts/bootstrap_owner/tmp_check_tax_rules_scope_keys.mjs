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

async function resolveTenantId() {
  const user = await getAuth().getUserByEmail('enterprise@smartsfa.com.br');
  const memberships = await getFirestore()
    .collection('tenant_memberships')
    .where('uid', '==', user.uid)
    .get();
  for (const membership of memberships.docs) {
    const tenantId = membership.data().tenantId;
    const tenant = (await getFirestore().collection('tenants').doc(tenantId).get()).data() ?? {};
    if (tenant.erpIntegration?.credentials?.username) {
      return { tenantId, tenant };
    }
  }
  return null;
}

async function run() {
  const resolved = await resolveTenantId();
  if (!resolved) throw new Error('tenant nao encontrado');
  const { tenantId, tenant } = resolved;
  const syntheticId = `enterprise_default_${tenantId}`;

  console.log('# tenantId:', tenantId);
  console.log('# workspaceType:', tenant.workspaceType);
  console.log('# erpIntegration.environment:', tenant.erpIntegration?.environment);
  console.log('# synthetic representedCompanyId esperado:', syntheticId);

  const snap = await getFirestore()
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .get();

  console.log(`# tax_rules count: ${snap.size}`);
  const byScope = new Map();
  for (const doc of snap.docs) {
    const data = doc.data();
    const scope = (data.representedCompanyId ?? '').toString().trim();
    const key = scope === '' ? '(vazio)' : scope;
    byScope.set(key, (byScope.get(key) ?? 0) + 1);
  }
  for (const [scope, count] of byScope) {
    console.log(`  - scope=${JSON.stringify(scope)} count=${count}`);
  }

  // Mostra um exemplo completo de regra, se houver, pra conferir campos usados no matcher.
  if (snap.size > 0) {
    const sample = snap.docs[0].data();
    console.log('# exemplo de regra (primeiro doc):');
    console.log(JSON.stringify(sample, null, 2));
  }
}

run().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
