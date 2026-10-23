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

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID ?? 'smart-sfa';
const TARGET_EMAIL = String(
  process.env.ENTERPRISE_EMAIL ?? 'enterprise@smartsfa.com.br',
)
  .trim()
  .toLowerCase();

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
    throw new Error('Nao foi possivel resolver tenantId do usuario alvo.');
  }

  const tenantSnap = await db.collection('tenants').doc(tenantId).get();
  const tenantData = tenantSnap.data() || {};
  const integration =
    tenantData.erpIntegration && typeof tenantData.erpIntegration === 'object'
      ? tenantData.erpIntegration
      : {};
  const credentialsMap =
    integration.credentials && typeof integration.credentials === 'object'
      ? integration.credentials
      : {};

  const environment = String(integration.environment ?? 'prod')
    .trim()
    .toLowerCase();
  const clientId = String(credentialsMap.username ?? '').trim();
  const clientSecret = String(credentialsMap.password ?? '').trim();
  const xToken = String(credentialsMap.accessToken ?? '').trim();

  if (!clientId || !clientSecret || !xToken) {
    throw new Error('Credenciais ERP incompletas no tenant alvo.');
  }

  const functionUrl =
    `https://us-central1-${PROJECT_ID}.cloudfunctions.net/syncSankhyaCatalogModule`;

  const response = await fetch(functionUrl, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      tenantId,
      module: 'tax_rules',
      environment,
      clientId,
      clientSecret,
      xToken,
    }),
  });

  const text = await response.text();
  let payload = {};
  try {
    payload = JSON.parse(text);
  } catch {
    payload = { raw: text };
  }

  console.log(
    JSON.stringify(
      {
        tenantId,
        environment,
        status: response.status,
        response: payload,
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
