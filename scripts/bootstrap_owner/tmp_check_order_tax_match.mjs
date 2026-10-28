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
      return tenantId;
    }
  }
  return null;
}

async function run() {
  const tenantId = await resolveTenantId();
  if (!tenantId) throw new Error('tenant nao encontrado');
  const firestore = getFirestore();

  const clientesSnap = await firestore
    .collection('clientes')
    .where('tenantId', '==', tenantId)
    .limit(5)
    .get();
  console.log('# amostra de clientes (UF):');
  for (const doc of clientesSnap.docs) {
    const c = doc.data();
    console.log(JSON.stringify({ id: doc.id, nome: c.nome, estado: c.estado }));
  }

  const ncmsToCheck = ['90309090', '83026000', '85414122'];
  const groupId = 'erp_group_self_T8oqTD0UBtWATPbITOGsqAEZt3d2_smartsfa-enterprise-teste_d92c546dd633f84f';

  const rulesSnap = await firestore
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .get();

  console.log(`\n# total tax_rules: ${rulesSnap.size}`);

  for (const ncm of ncmsToCheck) {
    const ncmMasked = `${ncm.slice(0, 4)}.${ncm.slice(4, 6)}.${ncm.slice(6, 8)}`;
    const matches = rulesSnap.docs.filter((doc) => doc.data().ncm === ncmMasked);
    console.log(`\n# regras para NCM ${ncmMasked}: ${matches.length}`);
    for (const doc of matches.slice(0, 6)) {
      const d = doc.data();
      console.log(
        JSON.stringify({
          id: doc.id,
          ufOrigem: d.ufOrigem,
          ufDestino: d.ufDestino,
          aliquotaIcms: d.aliquotaIcms,
          aliquotaSt: d.aliquotaSt,
          aliquotaDifal: d.aliquotaDifal,
          aliquotaFcp: d.aliquotaFcp,
          taxGroupId: d.taxGroupId ?? null,
        }),
      );
    }
  }

  const groupMatches = rulesSnap.docs.filter((doc) => doc.data().taxGroupId === groupId);
  console.log(`\n# regras do grupo ${groupId}: ${groupMatches.length}`);
  for (const doc of groupMatches.slice(0, 6)) {
    const d = doc.data();
    console.log(
      JSON.stringify({
        id: doc.id,
        ufOrigem: d.ufOrigem,
        ufDestino: d.ufDestino,
        aliquotaIcms: d.aliquotaIcms,
        aliquotaSt: d.aliquotaSt,
      }),
    );
  }

  // fallback generica por UF (sem ncm) para origem SP
  const genericSpOrigin = rulesSnap.docs.filter(
    (doc) => doc.data().ufOrigem === 'SP' && !doc.data().ncm && !doc.data().taxGroupId,
  );
  console.log(`\n# regras genericas (sem ncm/grupo) com ufOrigem=SP: ${genericSpOrigin.length}`);
  for (const doc of genericSpOrigin.slice(0, 5)) {
    const d = doc.data();
    console.log(
      JSON.stringify({
        id: doc.id,
        ufDestino: d.ufDestino,
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
