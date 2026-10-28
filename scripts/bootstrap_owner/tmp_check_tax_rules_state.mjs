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

async function run() {
  const user = await getAuth().getUserByEmail('enterprise@smartsfa.com.br');
  const memberships = await getFirestore()
    .collection('tenant_memberships')
    .where('uid', '==', user.uid)
    .get();
  const tenantId = memberships.docs[0].data().tenantId;

  const firestore = getFirestore();
  const rulesSnapshot = await firestore
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .get();
  const groupsSnapshot = await firestore
    .collection('tax_rule_groups')
    .where('tenantId', '==', tenantId)
    .get();

  const withTaxGroupId = rulesSnapshot.docs.filter((doc) => doc.data().taxGroupId);
  const withNcmOnly = rulesSnapshot.docs.filter(
    (doc) => doc.data().ncm && !doc.data().taxGroupId,
  );
  const genericRows = rulesSnapshot.docs.filter(
    (doc) => !doc.data().ncm && !doc.data().taxGroupId,
  );

  console.log(`tenantId: ${tenantId}`);
  console.log(`total tax_rules: ${rulesSnapshot.size}`);
  console.log(`  com taxGroupId (grupo): ${withTaxGroupId.length}`);
  console.log(`  com ncm, sem grupo (singleton): ${withNcmOnly.length}`);
  console.log(`  genericas por UF (sem ncm/grupo): ${genericRows.length}`);
  console.log(`total tax_rule_groups: ${groupsSnapshot.size}`);

  for (const doc of groupsSnapshot.docs.slice(0, 5)) {
    const d = doc.data();
    console.log(
      JSON.stringify({
        groupId: doc.id,
        name: d.name,
        memberNcmCount: d.memberNcmCount,
        source: d.source,
      }),
    );
  }
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
