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
    const tenant = (
      await getFirestore().collection('tenants').doc(tenantId).get()
    ).data() ?? {};
    if (tenant.erpIntegration?.credentials?.accessToken) {
      return tenantId;
    }
  }
  return null;
}

async function run() {
  const tenantId = await resolveTenantId();
  if (!tenantId) throw new Error('tenant nao encontrado');

  const snapshot = await getFirestore()
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .where('origin', '==', 'erp')
    .get();

  console.log(`# total regras erp: ${snapshot.size}`);

  const fieldsNonZero = {
    aliquotaDestino: 0,
    aliquotaCredito: 0,
    aliquotaDifal: 0,
    aliquotaFcp: 0,
    aliquotaFcpSt: 0,
    mvaIva: 0,
    stBaseReductionPercent: 0,
    taxGroupId: 0,
    ncm: 0,
    cest: 0,
    stPriceForCalculation: 0,
  };

  let allFieldsZeroCount = 0;
  const allZeroSamples = [];

  for (const doc of snapshot.docs) {
    const d = doc.data();
    for (const f of Object.keys(fieldsNonZero)) {
      const v = d[f];
      if (f === 'taxGroupId' || f === 'ncm' || f === 'cest') {
        if (v) fieldsNonZero[f] += 1;
      } else if ((v ?? 0) > 0) {
        fieldsNonZero[f] += 1;
      }
    }
    const numericFields = [
      'aliquotaDestino', 'aliquotaCredito', 'aliquotaDifal', 'aliquotaFcp',
      'aliquotaFcpSt', 'mvaIva', 'stBaseReductionPercent', 'stPriceForCalculation',
    ];
    const allZero = numericFields.every((f) => (d[f] ?? 0) <= 0);
    if (allZero) {
      allFieldsZeroCount += 1;
      if (allZeroSamples.length < 5) {
        allZeroSamples.push({ id: doc.id, ncm: d.ncm, cest: d.cest, cstCsosn: d.cstCsosn, grupoFiscalId: d.grupoFiscalId });
      }
    }
  }
  console.log('# contagem de docs com valor não-zero/preenchido por campo:');
  console.log(JSON.stringify(fieldsNonZero, null, 2));
  console.log(`\n# docs com TODOS os campos numericos (aliquota/mva/st/fcp/difal) zerados/nulos: ${allFieldsZeroCount} de ${snapshot.size}`);
  console.log(JSON.stringify(allZeroSamples, null, 2));


  console.log('\n# amostra de 10 docs completos:');
  for (const doc of snapshot.docs.slice(0, 10)) {
    const d = doc.data();
    console.log(
      JSON.stringify({
        id: doc.id,
        ncm: d.ncm,
        cest: d.cest,
        ufOrigem: d.ufOrigem,
        ufDestino: d.ufDestino,
        aliquotaDestino: d.aliquotaDestino,
        aliquotaCredito: d.aliquotaCredito,
        aliquotaDifal: d.aliquotaDifal,
        aliquotaFcp: d.aliquotaFcp,
        aliquotaFcpSt: d.aliquotaFcpSt,
        mvaIva: d.mvaIva,
        grupoFiscalId: d.grupoFiscalId,
        taxGroupId: d.taxGroupId,
        stCalculationType: d.stCalculationType,
        cstCsosn: d.cstCsosn,
      }),
    );
  }
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
