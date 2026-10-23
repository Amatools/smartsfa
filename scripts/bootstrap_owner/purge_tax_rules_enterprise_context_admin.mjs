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

function toLowerToken(value) {
  return String(value ?? '').trim().toLowerCase();
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

  const first = memberships[0];
  if (first) {
    return String(first.tenantId ?? '').trim();
  }

  return '';
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
  const memberships = membershipsSnap.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));

  const tenantId = pickTenantId(userData, memberships);
  if (!tenantId) {
    throw new Error('Nao foi possivel resolver o tenantId do usuario alvo.');
  }

  const representedCandidates = [
    String(userData.lastSelectedRepresentedCompanyId ?? '').trim(),
    String(userData.selectedRepresentedCompanyId ?? '').trim(),
    `enterprise_default_${tenantId}`,
  ].filter(Boolean);
  const representedScopeSet = new Set(
    representedCandidates.map((item) => toLowerToken(item)),
  );

  const taxRulesSnapshot = await db
    .collection('tax_rules')
    .where('tenantId', '==', tenantId)
    .get();

  let totalTenantRules = 0;
  let deletedGlobalCount = 0;
  let deletedRepresentedCount = 0;
  let untouchedOtherScopeCount = 0;
  const refsToDelete = [];

  for (const doc of taxRulesSnapshot.docs) {
    totalTenantRules += 1;
    const payload = doc.data() || {};
    const scope = String(payload.representedCompanyId ?? '').trim();
    const scopeToken = toLowerToken(scope);

    if (!scopeToken) {
      deletedGlobalCount += 1;
      refsToDelete.push(doc.ref);
      continue;
    }

    if (representedScopeSet.has(scopeToken)) {
      deletedRepresentedCount += 1;
      refsToDelete.push(doc.ref);
      continue;
    }

    untouchedOtherScopeCount += 1;
  }

  const writer = db.bulkWriter();
  writer.onWriteError((error) => {
    if (error.failedAttempts < 3) {
      return true;
    }
    console.error(
      '[purge_tax_rules_enterprise_context_admin] delete_failed',
      JSON.stringify({
        code: error.code,
        message: error.message,
        documentPath: error.documentRef?.path || null,
        failedAttempts: error.failedAttempts,
      }),
    );
    return false;
  });

  for (const ref of refsToDelete) {
    writer.delete(ref);
  }
  await writer.close();

  console.log(
    JSON.stringify(
      {
        email: TARGET_EMAIL,
        uid,
        tenantId,
        representedCandidates,
        totalTenantRules,
        deletedCount: refsToDelete.length,
        deletedGlobalCount,
        deletedRepresentedCount,
        untouchedOtherScopeCount,
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
