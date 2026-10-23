import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SERVICE_ACCOUNT_PATH = path.join(
  __dirname,
  'smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json',
);

const TARGET_EMAIL = String(
  process.env.ENTERPRISE_EMAIL ?? 'enterprise@smartsfa.com.br',
)
  .trim()
  .toLowerCase();

function normalizeDigits(value) {
  return String(value ?? '').replace(/[^0-9]/g, '');
}

function isZeroDigits(value) {
  const digits = normalizeDigits(value);
  return digits.length > 0 && /^0+$/.test(digits);
}

function pickTenantId(userData, memberships) {
  const fromUser = String(
    userData.lastSelectedTenantId ?? userData.defaultTenantId ?? '',
  ).trim();
  if (fromUser) {
    return fromUser;
  }
  const active = memberships.find((item) => {
    return (
      item.ativo === true &&
      String(item.state ?? '').trim().toLowerCase() === 'active'
    );
  });
  if (active) {
    return String(active.tenantId ?? '').trim();
  }
  return String(memberships[0]?.tenantId ?? '').trim();
}

async function run() {
  const credentials = JSON.parse(
    fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'),
  );
  initializeApp({ credential: cert(credentials) });

  const auth = getAuth();
  const db = getFirestore();

  const user = await auth.getUserByEmail(TARGET_EMAIL);
  const uid = user.uid;

  const userSnap = await db.collection('usuarios').doc(uid).get();
  const userData = userSnap.data() || {};

  const membershipsSnap = await db
    .collection('tenant_memberships')
    .where('uid', '==', uid)
    .get();
  const memberships = membershipsSnap.docs.map((doc) => doc.data() || {});

  const tenantId = pickTenantId(userData, memberships);
  if (!tenantId) {
    throw new Error('Nao foi possivel resolver tenantId para o usuario alvo.');
  }

  const tenantSnap = await db.collection('tenants').doc(tenantId).get();
  const tenantData = tenantSnap.data() || {};

  const taxRulesSnap = await db
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .get();

  let total = 0;
  let ncmEmpty = 0;
  let ncmAllZero = 0;
  let cestEmpty = 0;
  let cestAllZero = 0;
  let aliquotaDestinoZero = 0;
  let aliquotaCreditoZero = 0;

  const sample = [];

  for (const doc of taxRulesSnap.docs) {
    total += 1;
    const data = doc.data() || {};
    const ncm = data.ncm ?? null;
    const cest = data.cest ?? null;
    const aliqDest = Number(data.aliquotaDestino ?? data.aliquotaSt ?? 0);
    const aliqCred = Number(data.aliquotaCredito ?? data.aliquotaIcms ?? 0);

    const ncmDigits = normalizeDigits(ncm);
    const cestDigits = normalizeDigits(cest);

    if (!ncmDigits) {
      ncmEmpty += 1;
    } else if (/^0+$/.test(ncmDigits)) {
      ncmAllZero += 1;
    }

    if (!cestDigits) {
      cestEmpty += 1;
    } else if (/^0+$/.test(cestDigits)) {
      cestAllZero += 1;
    }

    if (!Number.isFinite(aliqDest) || aliqDest === 0) {
      aliquotaDestinoZero += 1;
    }
    if (!Number.isFinite(aliqCred) || aliqCred === 0) {
      aliquotaCreditoZero += 1;
    }

    if (sample.length < 20) {
      sample.push({
        id: doc.id,
        ncm,
        cest,
        ufOrigem: data.ufOrigem ?? null,
        ufDestino: data.ufDestino ?? null,
        aliquotaDestino: data.aliquotaDestino ?? data.aliquotaSt ?? null,
        aliquotaCredito: data.aliquotaCredito ?? data.aliquotaIcms ?? null,
        fiscalException: data.fiscalException ?? null,
        representedCompanyId: data.representedCompanyId ?? null,
        origin: data.origin ?? null,
      });
    }
  }

  console.log(
    JSON.stringify(
      {
        email: TARGET_EMAIL,
        uid,
        tenantId,
        total,
        ncmEmpty,
        ncmAllZero,
        cestEmpty,
        cestAllZero,
        aliquotaDestinoZero,
        aliquotaCreditoZero,
        tenantSyncState: {
          lastTaxRulesSyncAt: tenantData.lastTaxRulesSyncAt ?? null,
          lastTaxRulesSourceCount: tenantData.lastTaxRulesSourceCount ?? null,
          lastTaxRulesImportedCount:
            tenantData.lastTaxRulesImportedCount ?? null,
          lastTaxRulesSkippedMissingNcmCount:
            tenantData.lastTaxRulesSkippedMissingNcmCount ?? null,
          lastTaxRulesImportedMissingCestCount:
            tenantData.lastTaxRulesImportedMissingCestCount ?? null,
          lastTaxRulesPrunedLegacyMissingNcmCount:
            tenantData.lastTaxRulesPrunedLegacyMissingNcmCount ?? null,
          lastTaxRulesEndpoint: tenantData.lastTaxRulesEndpoint ?? null,
        },
        sample,
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
