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

  const contexts = [];

  for (const membershipDoc of membershipsSnap.docs) {
    const membership = membershipDoc.data() || {};
    const tenantId = String(membership.tenantId ?? '').trim();
    if (!tenantId) {
      continue;
    }

    const expectedScope = `enterprise_default_${tenantId}`.toLowerCase();
    const taxRulesSnap = await db
      .collection('tax_rules')
      .where('tenantId', '==', tenantId)
      .get();

    let total = 0;
    let global = 0;
    let enterpriseDefault = 0;
    let otherScoped = 0;

    for (const ruleDoc of taxRulesSnap.docs) {
      total += 1;
      const scope = String(
        ruleDoc.data()?.representedCompanyId ?? '',
      ).trim().toLowerCase();

      if (!scope) {
        global += 1;
      } else if (scope === expectedScope) {
        enterpriseDefault += 1;
      } else {
        otherScoped += 1;
      }
    }

    contexts.push({
      membershipId: membershipDoc.id,
      tenantId,
      role: String(membership.role ?? ''),
      ativo: membership.ativo === true,
      state: String(membership.state ?? ''),
      totalTaxRules: total,
      globalTaxRules: global,
      enterpriseDefaultTaxRules: enterpriseDefault,
      otherScopedTaxRules: otherScoped,
    });
  }

  contexts.sort((a, b) => b.totalTaxRules - a.totalTaxRules);

  console.log(
    JSON.stringify(
      {
        email: TARGET_EMAIL,
        uid,
        userDefaultTenantId: String(userData.defaultTenantId ?? ''),
        userLastSelectedTenantId: String(userData.lastSelectedTenantId ?? ''),
        userLastSelectedRepresentedCompanyId: String(
          userData.lastSelectedRepresentedCompanyId ?? '',
        ),
        contexts,
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
