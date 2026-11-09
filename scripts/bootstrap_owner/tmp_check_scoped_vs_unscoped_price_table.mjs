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

const UNSCOPED_TABLE_ID =
  'pt_default_self_T8oqTD0UBtWATPbITOGsqAEZt3d2_smartsfa-enterprise-teste';
const SCOPED_TABLE_ID =
  'pt_default_self_T8oqTD0UBtWATPbITOGsqAEZt3d2_smartsfa-enterprise-teste_enterprise_default_self_T8oqTD0UBtWATPbITOGsqAEZt3d2_smartsfa-enterprise-teste';

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
  const firestore = getFirestore();

  console.log('# tenantId:', tenantId);
  console.log(
    '# tenant.defaultPriceTableIds:',
    JSON.stringify(tenant.defaultPriceTableIds ?? null),
  );

  const companiesSnap = await firestore
    .collection('represented_companies')
    .where('tenantId', '==', tenantId)
    .get();
  console.log(`# represented_companies count: ${companiesSnap.size}`);
  for (const doc of companiesSnap.docs) {
    console.log('  -', doc.id, JSON.stringify(doc.data()));
  }

  for (const tableId of [UNSCOPED_TABLE_ID, SCOPED_TABLE_ID]) {
    const tabelaDoc = await firestore.collection('tabelas_preco').doc(tableId).get();
    const pricesSnap = await firestore
      .collection('product_base_prices')
      .where('tenantId', '==', tenantId)
      .where('priceTableId', '==', tableId)
      .get();
    console.log(
      `# tableId=${tableId} | tabelaExists=${tabelaDoc.exists} | basePricesCount=${pricesSnap.size}`,
    );
  }
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
