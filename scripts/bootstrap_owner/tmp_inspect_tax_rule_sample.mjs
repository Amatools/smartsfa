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
  const snap = await firestore
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .limit(10)
    .get();

  for (const doc of snap.docs) {
    const d = doc.data();
    console.log(
      JSON.stringify({
        id: doc.id,
        ufOrigem: d.ufOrigem,
        ufDestino: d.ufDestino,
        ncm: d.ncm,
        aliquotaDestino: d.aliquotaDestino,
        aliquotaCredito: d.aliquotaCredito,
        aliquotaIcms: d.aliquotaIcms,
        aliquotaSt: d.aliquotaSt,
        mvaIva: d.mvaIva,
        aliquotaDifal: d.aliquotaDifal,
      }),
    );
  }

  // mesmo UF (origem == destino) deveria ter aliquota interna "cheia" (ex. 18%, 17%, 12%)
  const sameUfSnap = await firestore
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .where('ufOrigem', '==', 'SP')
    .where('ufDestino', '==', 'SP')
    .limit(5)
    .get();
  console.log('--- SP->SP ---');
  for (const doc of sameUfSnap.docs) {
    const d = doc.data();
    console.log(
      JSON.stringify({
        id: doc.id,
        ncm: d.ncm,
        aliquotaDestino: d.aliquotaDestino,
        aliquotaCredito: d.aliquotaCredito,
      }),
    );
  }
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
