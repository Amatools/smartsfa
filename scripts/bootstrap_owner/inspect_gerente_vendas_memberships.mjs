import fs from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const serviceAccount = JSON.parse(
  fs.readFileSync('./smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json', 'utf8'),
);
initializeApp({ credential: cert(serviceAccount) });

const auth = getAuth();
const db = getFirestore();

for (const email of ['gerente@smartsfa.com.br', 'vendas@smartsfa.com.br']) {
  const user = await auth.getUserByEmail(email);
  const uid = user.uid;
  const memberships = await db
    .collection('tenant_memberships')
    .where('uid', '==', uid)
    .where('ativo', '==', true)
    .get();

  console.log(`\n${email} (${uid})`);
  if (memberships.empty) {
    console.log('- sem memberships ativos');
  }

  for (const doc of memberships.docs) {
    const data = doc.data();
    console.log(`- tenantId=${data.tenantId} role=${data.role} state=${data.state}`);
  }
}
