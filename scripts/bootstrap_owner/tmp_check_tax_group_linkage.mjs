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
  const targetProductId = `erp_prod_${tenantId}_490454`;
  const targetGroupId = `erp_group_${tenantId}_d92c546dd633f84f`;

  console.log('# tenantId:', tenantId);
  console.log('# produtoId alvo:', targetProductId);
  console.log('# grupoTributarioId alvo:', targetGroupId);

  const groupDoc = await firestore.collection('tax_rule_groups').doc(targetGroupId).get();
  console.log('# tax_rule_groups doc:', JSON.stringify(groupDoc.data() ?? null, null, 2));

  const rulesByGroupSnap = await firestore
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .where('taxGroupId', '==', targetGroupId)
    .get();
  console.log(`# tax_rules com taxGroupId=alvo: ${rulesByGroupSnap.size}`);
  for (const doc of rulesByGroupSnap.docs) {
    console.log('  -', JSON.stringify(doc.data(), null, 2));
  }

  const rulesByNcmSnap = await firestore
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .where('ncm', '==', '85414122')
    .get();
  console.log(`# tax_rules com ncm=85414122: ${rulesByNcmSnap.size}`);
  for (const doc of rulesByNcmSnap.docs) {
    console.log('  -', JSON.stringify(doc.data(), null, 2));
  }

  // Verifica se existe alguma regra cujo campo representa o grupo via outro nome
  // (ex.: grupoFiscalId em vez de taxGroupId) para o mesmo grupo alvo.
  const rulesByGrupoFiscalSnap = await firestore
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .where('grupoFiscalId', '==', targetGroupId)
    .get();
  console.log(`# tax_rules com grupoFiscalId=alvo: ${rulesByGrupoFiscalSnap.size}`);
  for (const doc of rulesByGrupoFiscalSnap.docs) {
    console.log('  -', JSON.stringify(doc.data(), null, 2));
  }
}

run().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
