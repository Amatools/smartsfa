import fs from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const sa = JSON.parse(fs.readFileSync('./smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json', 'utf8'));
initializeApp({ credential: cert(sa) });
const db = getFirestore();
const tenantId = 'self_zRRv3iXurFbl4PecT4S53HeAHjH2_representacoes-a';
const d = (await db.collection('tenants').doc(tenantId).get()).data() || {};
console.log(JSON.stringify(d, null, 2));
