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

  const syntheticScopeKey = `enterprise_default_${tenantId}`;

  console.log('# tenantId:', tenantId);
  console.log('# synthetic scopeKey esperado (mobile/web enterprise):', syntheticScopeKey);

  const adjustmentsRoot = tenant.representedCommercialAdjustments ?? {};
  console.log('# representedCommercialAdjustments keys:', Object.keys(adjustmentsRoot));
  for (const [key, value] of Object.entries(adjustmentsRoot)) {
    const count = Array.isArray(value) ? value.length : 'n/a';
    console.log(`  - scopeKey="${key}" rulesCount=${count}`);
  }

  const discountRoot = tenant.representedOrderDiscountPolicy ?? {};
  console.log('# representedOrderDiscountPolicy keys:', Object.keys(discountRoot));
  for (const [key, value] of Object.entries(discountRoot)) {
    const fieldsCount = Array.isArray(value?.fields) ? value.fields.length : 'n/a';
    console.log(`  - scopeKey="${key}" fieldsCount=${fieldsCount}`, JSON.stringify(value));
  }

  console.log('# paymentConditionRules (legado tenant-level) presente?', 'paymentConditionRules' in tenant);
  console.log('# representedPaymentConditionRules keys:', Object.keys(tenant.representedPaymentConditionRules ?? {}));
}

run().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
