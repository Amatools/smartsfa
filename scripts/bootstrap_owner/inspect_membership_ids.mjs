import fs from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const sa = JSON.parse(fs.readFileSync('./smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json', 'utf8'));
initializeApp({ credential: cert(sa) });
const db = getFirestore();
const auth = getAuth();
const tenantId = 'self_zRRv3iXurFbl4PecT4S53HeAHjH2_representacoes-a';
for (const email of ['owner@smartsfa.com.br','representante@smartsfa.com.br','vendedor@smartsfa.com.br']) {
  const { uid } = await auth.getUserByEmail(email);
  const q = await db.collection('tenant_memberships').where('uid','==',uid).where('tenantId','==',tenantId).get();
  console.log('\n', email, uid);
  for (const d of q.docs) {
    console.log('docId=', d.id, 'ativo=', d.data().ativo, 'role=', d.data().role);
  }
  console.log('expected=', `${tenantId}_${uid}`);
}
