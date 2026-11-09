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

function normalizeNcm(ncm) {
  return (ncm ?? '').toString().replace(/\D/g, '');
}

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

  const rulesSnap = await firestore
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .get();

  const matches = rulesSnap.docs
    .map((d) => d.data())
    .filter((r) => normalizeNcm(r.ncm) === '85414122');

  console.log(`# regras com NCM normalizado = 85414122: ${matches.length}`);
  for (const r of matches) {
    console.log(JSON.stringify(r, null, 2));
  }

  // tambem lista regras "generic" (sem ncm/grupo/produto) que caibam em SP->SP,
  // ativas, sem deletedAt, dentro da janela de validade.
  const now = new Date();
  const genericSp = rulesSnap.docs
    .map((d) => d.data())
    .filter((r) => {
      if (r.deletedAt || r.status !== 'active') return false;
      if (r.ncm || r.taxGroupId || r.produtoId) return false;
      const origem = (r.ufOrigem ?? '').toUpperCase();
      const destino = (r.ufDestino ?? '').toUpperCase();
      const origemOk = !origem || origem === 'ANY' || origem === 'SP';
      const destinoOk = !destino || destino === 'ANY' || destino === 'SP';
      return origemOk && destinoOk;
    });
  console.log(`# regras genericas compativeis com SP->SP: ${genericSp.length}`);
  for (const r of genericSp.slice(0, 3)) {
    console.log(JSON.stringify(r, null, 2));
  }
}

run().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
