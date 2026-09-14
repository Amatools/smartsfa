import fs from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const sa = JSON.parse(fs.readFileSync('./smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json', 'utf8'));
initializeApp({ credential: cert(sa) });

const emails = ['owner@smartsfa.com.br','representante@smartsfa.com.br','vendedor@smartsfa.com.br'];
for (const email of emails) {
  const user = await getAuth().getUserByEmail(email);
  const uid = user.uid;
  const userDoc = await getFirestore().collection('usuarios').doc(uid).get();
  const userData = userDoc.data() || {};
  console.log('\n===', email, uid);
  console.log('accountContractLock=', userData.accountContractLock, 'defaultTenantId=', userData.defaultTenantId, 'lastSelectedTenantId=', userData.lastSelectedTenantId);

  const ms = await getFirestore().collection('tenant_memberships').where('uid','==',uid).where('ativo','==',true).where('state','==','active').get();
  for (const m of ms.docs) {
    const d = m.data();
    const t = await getFirestore().collection('tenants').doc(d.tenantId).get();
    const td = t.data() || {};
    console.log('-', d.tenantId, '| role=', d.role, '| workspaceType=', td.workspaceType, '| tenantName=', td.nomeFantasia, '| hierarchyModel=', td.hierarchyModel);
  }
}
