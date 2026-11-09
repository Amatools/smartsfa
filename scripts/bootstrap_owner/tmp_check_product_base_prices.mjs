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

function buildDefaultPriceTableDocId(tenantId) {
  return `pt_default_${tenantId}`;
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
  const defaultTableId = buildDefaultPriceTableDocId(tenantId);

  console.log('# tenantId:', tenantId);
  console.log('# defaultPriceTableId esperado:', defaultTableId);

  const produtosSnap = await firestore
    .collection('produtos')
    .where('tenantId', '==', tenantId)
    .get();

  console.log(`# produtos count: ${produtosSnap.size}`);

  const basePricesSnap = await firestore
    .collection('product_base_prices')
    .where('tenantId', '==', tenantId)
    .where('priceTableId', '==', defaultTableId)
    .get();

  const byProductId = new Map();
  for (const doc of basePricesSnap.docs) {
    const data = doc.data();
    byProductId.set(data.productId, data);
  }

  console.log(`# product_base_prices (defaultTableId) count: ${basePricesSnap.size}`);

  for (const doc of produtosSnap.docs) {
    const produto = doc.data();
    const preco = byProductId.get(doc.id);
    console.log(
      `  - produtoId=${doc.id} desc=${produto.descricao} ncm=${produto.ncm} grupoTributarioId=${produto.grupoTributarioId} cest=${produto.cest} => basePrice=${preco ? preco.basePrice : 'FALTANDO'} regionId=${preco ? preco.regionId : '-'} updatedAt=${preco ? preco.updatedAt : '-'}`,
    );
  }
}

run().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
