import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SERVICE_ACCOUNT_PATH = path.join(
  __dirname,
  'smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json',
);
const WEB_API_KEY =
  process.env.FIREBASE_WEB_API_KEY ?? 'AIzaSyDFXV_T5_WfN2xrl-qi814i_AwReyGjXKs';
const OWNER_EMAIL = process.env.OWNER_EMAIL ?? 'owner@smartsfa.com.br';
const MANAGE_BILLING_URL =
  process.env.MANAGE_BILLING_URL ??
  'https://us-central1-smart-sfa.cloudfunctions.net/manageTenantBillingState';

function readServiceAccount() {
  return JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
}

async function exchangeCustomTokenForIdToken(customToken) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${WEB_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    },
  );

  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload?.idToken) {
    throw new Error(
      `Falha ao obter idToken. HTTP ${response.status}: ${JSON.stringify(payload)}`,
    );
  }

  return String(payload.idToken);
}

async function resolveOwnerTenantId(ownerUid, db) {
  const membershipsSnapshot = await db
    .collection('tenant_memberships')
    .where('uid', '==', ownerUid)
    .where('ativo', '==', true)
    .get();

  if (membershipsSnapshot.empty) {
    throw new Error(`Nenhuma membership ativa encontrada para uid=${ownerUid}`);
  }

  const candidates = membershipsSnapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));

  const byDefault = candidates.find((item) => item.defaultTenant === true);
  if (byDefault?.tenantId) {
    return String(byDefault.tenantId);
  }

  const byOwnerRole = candidates.find(
    (item) => String(item.role ?? '').trim().toLowerCase() === 'owner',
  );
  if (byOwnerRole?.tenantId) {
    return String(byOwnerRole.tenantId);
  }

  const fallback = candidates.find((item) => String(item.tenantId ?? '').trim());
  if (fallback?.tenantId) {
    return String(fallback.tenantId);
  }

  throw new Error(`Nao foi possivel resolver tenantId para uid=${ownerUid}`);
}

async function resolvePlatformAdminUid(db) {
  const snapshot = await db
    .collection('usuarios')
    .where('platformRole', '==', 'platform_admin')
    .where('ativoGlobal', '==', true)
    .limit(1)
    .get();

  if (snapshot.empty) {
    throw new Error('Nenhum usuario platform_admin ativo encontrado.');
  }

  return snapshot.docs[0].id;
}

async function callClearPlanLink(idToken, tenantId) {
  const response = await fetch(MANAGE_BILLING_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({
      tenantId,
      action: 'clear_plan_link',
      reason: 'manual_cleanup_after_duplicate_subscriptions',
    }),
  });

  const payload = await response.json().catch(() => ({}));
  return {
    status: response.status,
    payload,
  };
}

async function main() {
  if (!getApps().length) {
    initializeApp({
      credential: cert(readServiceAccount()),
      projectId: 'smart-sfa',
    });
  }

  const auth = getAuth();
  const db = getFirestore();

  const ownerUser = await auth.getUserByEmail(OWNER_EMAIL);
  const tenantId = await resolveOwnerTenantId(ownerUser.uid, db);

  const platformAdminUid = await resolvePlatformAdminUid(db);
  const customToken = await auth.createCustomToken(platformAdminUid);
  const idToken = await exchangeCustomTokenForIdToken(customToken);

  const result = await callClearPlanLink(idToken, tenantId);

  console.log('ownerEmail:', OWNER_EMAIL);
  console.log('ownerUid:', ownerUser.uid);
  console.log('tenantId:', tenantId);
  console.log('platformAdminUid:', platformAdminUid);
  console.log('responseStatus:', result.status);
  console.log('responsePayload:', JSON.stringify(result.payload, null, 2));

  if (result.status !== 200) {
    throw new Error(
      `clear_plan_link falhou (HTTP ${result.status}): ${JSON.stringify(result.payload)}`,
    );
  }
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exitCode = 1;
});
