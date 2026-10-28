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

  const produtosSnap = await firestore
    .collection('produtos')
    .where('tenantId', '==', tenantId)
    .get();

  console.log(`# total produtos no tenant: ${produtosSnap.size}`);

  const basePricesSnap = await firestore
    .collection('product_base_prices')
    .where('tenantId', '==', tenantId)
    .get();
  console.log(`# total product_base_prices no tenant: ${basePricesSnap.size}`);

  const basePricesByProduct = new Map();
  for (const doc of basePricesSnap.docs) {
    const d = doc.data();
    const pid = d.productId;
    if (!basePricesByProduct.has(pid)) basePricesByProduct.set(pid, []);
    basePricesByProduct.get(pid).push(d);
  }

  for (const doc of produtosSnap.docs) {
    const p = doc.data();
    const prices = basePricesByProduct.get(doc.id) ?? [];
    const activePrices = prices.filter((pr) => pr.isActive !== false);
    console.log(
      JSON.stringify({
        id: doc.id,
        descricao: p.descricao,
        ncm: p.ncm,
        grupoTributarioId: p.grupoTributarioId ?? null,
        valorBruto: p.valorBruto,
        aliquotaIpiBase: p.aliquotaIpiBase ?? null,
        qtdPrecoBaseAtivo: activePrices.length,
        amostraPrecoBase: activePrices.slice(0, 3).map((pr) => ({
          priceTableId: pr.priceTableId,
          regionId: pr.regionId,
          basePrice: pr.basePrice,
          isActive: pr.isActive,
        })),
      }),
    );
  }
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
