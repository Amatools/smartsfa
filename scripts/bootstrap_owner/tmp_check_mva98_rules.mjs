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
  return memberships.docs[0]?.data()?.tenantId ?? null;
}

async function run() {
  const db = getFirestore();
  const tenantId = await resolveTenantId();
  if (!tenantId) throw new Error('tenantId nao encontrado');

  const snap = await db.collection('tax_rules').where('tenantId', '==', tenantId).get();
  const rows = snap.docs.map((d) => ({ id: d.id, ...(d.data() || {}) }));

  const withMva98 = rows.filter((r) => Number(r.mvaIva ?? 0) >= 97.9 && Number(r.mvaIva ?? 0) <= 98.1);
  const spSpMva98 = withMva98.filter((r) => r.ufOrigem === 'SP' && r.ufDestino === 'SP');

  const byNcm = new Map();
  for (const r of spSpMva98) {
    const ncm = String(r.ncm ?? 'ANY');
    if (!byNcm.has(ncm)) byNcm.set(ncm, 0);
    byNcm.set(ncm, byNcm.get(ncm) + 1);
  }

  console.log(JSON.stringify({
    tenantId,
    totalRules: rows.length,
    totalWithMva98: withMva98.length,
    spSpWithMva98: spSpMva98.length,
    sampleSpSp: spSpMva98.slice(0, 10).map((r) => ({
      id: r.id,
      ncm: r.ncm ?? null,
      cest: r.cest ?? null,
      aliquotaIcms: r.aliquotaIcms ?? null,
      aliquotaSt: r.aliquotaSt ?? null,
      mvaIva: r.mvaIva ?? null,
      prioridade: r.priority ?? null,
    })),
    ncmCounts: Array.from(byNcm.entries()).slice(0, 20),
  }, null, 2));
}

run().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exitCode = 1;
});
