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

  const produtosSnap = await firestore
    .collection('produtos')
    .where('tenantId', '==', tenantId)
    .get();

  const rulesSnap = await firestore
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .get();
  const rules = rulesSnap.docs.map((d) => d.data());

  console.log(`# produtos=${produtosSnap.size} regras=${rules.length}`);

  for (const doc of produtosSnap.docs) {
    const produto = doc.data();
    const ncm = normalizeNcm(produto.ncm);
    const taxGroupId = (produto.grupoTributarioId ?? '').trim();

    const byProduto = rules.filter(
      (r) => (r.produtoId ?? '').trim() === doc.id && r.status === 'active' && !r.deletedAt,
    );
    const byGroup = rules.filter(
      (r) =>
        taxGroupId &&
        (r.taxGroupId ?? '').trim() === taxGroupId &&
        r.status === 'active' &&
        !r.deletedAt,
    );
    const byNcm = rules.filter(
      (r) => normalizeNcm(r.ncm) === ncm && ncm !== '' && r.status === 'active' && !r.deletedAt,
    );
    const generic = rules.filter(
      (r) =>
        !r.produtoId &&
        !r.taxGroupId &&
        !r.ncm &&
        r.status === 'active' &&
        !r.deletedAt,
    );

    console.log(
      `- produtoId=${doc.id} ncm=${produto.ncm} taxGroupId=${taxGroupId || '-'} ` +
        `=> byProduto=${byProduto.length} byGroup=${byGroup.length} byNcm=${byNcm.length} generic=${generic.length}`,
    );
  }
}

run().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
