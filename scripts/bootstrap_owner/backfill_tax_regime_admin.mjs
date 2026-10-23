import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import { cert, initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SERVICE_ACCOUNT_PATH = path.join(
  __dirname,
  'smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json',
);

const TAX_REGIMES = new Set([
  'simples_nacional',
  'lucro_presumido',
  'lucro_real',
]);

const DEFAULT_TAX_REGIME = 'simples_nacional';

function normalizeTaxRegime(value) {
  const normalized = String(value ?? '').trim().toLowerCase();
  return TAX_REGIMES.has(normalized) ? normalized : '';
}

function parseArgs() {
  const args = process.argv.slice(2);
  let dryRun = false;
  let tenantId = '';

  for (const arg of args) {
    const item = String(arg || '').trim();
    if (!item) {
      continue;
    }
    if (item === '--dry-run') {
      dryRun = true;
      continue;
    }
    if (item.startsWith('--tenant=')) {
      tenantId = item.substring('--tenant='.length).trim();
      continue;
    }
  }

  return { dryRun, tenantId };
}

async function updateInBatches(docs, applyUpdate) {
  const batchSize = 400;
  let updated = 0;

  for (let i = 0; i < docs.length; i += batchSize) {
    const slice = docs.slice(i, i + batchSize);
    const batch = db.batch();
    let batchMutations = 0;

    for (const item of slice) {
      const changed = applyUpdate(batch, item);
      if (changed) {
        batchMutations += 1;
      }
    }

    if (batchMutations > 0) {
      if (!options.dryRun) {
        await batch.commit();
      }
      updated += batchMutations;
    }
  }

  return updated;
}

const options = parseArgs();
const serviceAccount = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

async function run() {
  let tenantQuery = db.collection('tenants');
  if (options.tenantId) {
    tenantQuery = tenantQuery.where('tenantId', '==', options.tenantId);
  }

  const tenantSnap = await tenantQuery.get();
  const tenantDocs = tenantSnap.docs;

  let representedQuery = db.collection('tenant_represented_companies');
  if (options.tenantId) {
    representedQuery = representedQuery.where('tenantId', '==', options.tenantId);
  }

  const representedSnap = await representedQuery.get();
  const representedDocs = representedSnap.docs;

  let clientesQuery = db.collection('clientes');
  if (options.tenantId) {
    clientesQuery = clientesQuery.where('tenantId', '==', options.tenantId);
  }
  const clientesSnap = await clientesQuery.get();
  const clientesDocs = clientesSnap.docs;

  let preCadastrosQuery = db.collection('cliente_pre_cadastros');
  if (options.tenantId) {
    preCadastrosQuery = preCadastrosQuery.where('tenantId', '==', options.tenantId);
  }
  const preCadastrosSnap = await preCadastrosQuery.get();
  const preCadastrosDocs = preCadastrosSnap.docs;

  const tenantsUpdated = await updateInBatches(tenantDocs, (batch, docSnap) => {
    const data = docSnap.data() || {};
    const current = normalizeTaxRegime(data.taxRegime);
    if (current) {
      return false;
    }

    batch.set(
      docSnap.ref,
      {
        taxRegime: DEFAULT_TAX_REGIME,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return true;
  });

  const representedUpdated = await updateInBatches(
    representedDocs,
    (batch, docSnap) => {
      const data = docSnap.data() || {};
      const current = normalizeTaxRegime(data.taxRegime);
      if (current) {
        return false;
      }

      batch.set(
        docSnap.ref,
        {
          taxRegime: DEFAULT_TAX_REGIME,
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
      return true;
    },
  );

  const clientesUpdated = await updateInBatches(clientesDocs, (batch, docSnap) => {
    const data = docSnap.data() || {};
    const current = normalizeTaxRegime(data.taxRegime);
    if (current) {
      return false;
    }

    batch.set(
      docSnap.ref,
      {
        taxRegime: DEFAULT_TAX_REGIME,
        updatedAt: new Date().toISOString(),
      },
      { merge: true },
    );
    return true;
  });

  const preCadastrosUpdated = await updateInBatches(
    preCadastrosDocs,
    (batch, docSnap) => {
      const data = docSnap.data() || {};
      const current = normalizeTaxRegime(data.taxRegime);
      if (current) {
        return false;
      }

      batch.set(
        docSnap.ref,
        {
          taxRegime: DEFAULT_TAX_REGIME,
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
      return true;
    },
  );

  console.log(
    JSON.stringify(
      {
        dryRun: options.dryRun,
        tenantFilter: options.tenantId || null,
        totals: {
          tenantsScanned: tenantDocs.length,
          representedScanned: representedDocs.length,
          clientesScanned: clientesDocs.length,
          preCadastrosScanned: preCadastrosDocs.length,
          tenantsUpdated,
          representedUpdated,
          clientesUpdated,
          preCadastrosUpdated,
        },
        defaultTaxRegime: DEFAULT_TAX_REGIME,
      },
      null,
      2,
    ),
  );
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
