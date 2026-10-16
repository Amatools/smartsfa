import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const SERVICE_ACCOUNT_PATH =
  process.env.SERVICE_ACCOUNT_KEY_PATH ||
  './smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json';

const TARGET_TENANT_ID =
  process.env.INSPECT_TENANT_ID ||
  'self_zRRv3iXurFbl4PecT4S53HeAHjH2_representacoes-a';

const EMAIL_DOMAIN_FILTER = (process.env.INSPECT_EMAIL_DOMAIN || 'smartsfa.com.br')
  .trim()
  .toLowerCase();

function resolveServiceAccountPath() {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const normalized = path.resolve(scriptDir, SERVICE_ACCOUNT_PATH);
  if (!fs.existsSync(normalized)) {
    throw new Error(`Service account nao encontrada: ${normalized}`);
  }
  return normalized;
}

async function listAllAuthUsers() {
  const auth = getAuth();
  const users = [];
  let pageToken;

  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);

  return users;
}

function domainMatches(email) {
  return email.toLowerCase().endsWith(`@${EMAIL_DOMAIN_FILTER}`);
}

async function main() {
  const servicePath = resolveServiceAccountPath();
  const credentials = JSON.parse(fs.readFileSync(servicePath, 'utf8'));
  initializeApp({ credential: cert(credentials) });

  const db = getFirestore();
  const auth = getAuth();

  const tenantDoc = await db.collection('tenants').doc(TARGET_TENANT_ID).get();
  const tenantData = tenantDoc.data() || {};

  const membershipSnapshot = await db
    .collection('tenant_memberships')
    .where('tenantId', '==', TARGET_TENANT_ID)
    .get();

  const tenantMembers = [];
  const tenantUids = new Set();

  for (const doc of membershipSnapshot.docs) {
    const data = doc.data();
    const uid = (data.uid || '').toString();
    tenantUids.add(uid);

    let email = '(sem email no Auth)';
    try {
      const user = await auth.getUser(uid);
      email = user.email || email;
    } catch (_) {
      // Keep fallback label when auth user is missing.
    }

    tenantMembers.push({
      membershipId: doc.id,
      uid,
      email,
      role: (data.role || '').toString(),
      ativo: data.ativo === true,
      state: (data.state || '').toString(),
      defaultTenant: data.defaultTenant === true,
    });
  }

  tenantMembers.sort((a, b) => a.email.localeCompare(b.email));

  const authUsers = await listAllAuthUsers();
  const domainUsers = authUsers.filter((user) => {
    const email = (user.email || '').trim();
    return email && domainMatches(email);
  });

  const outsideTenant = [];
  for (const user of domainUsers) {
    if (tenantUids.has(user.uid)) {
      continue;
    }

    const activeMemberships = await db
      .collection('tenant_memberships')
      .where('uid', '==', user.uid)
      .where('ativo', '==', true)
      .where('state', '==', 'active')
      .get();

    const contexts = activeMemberships.docs.map((doc) => {
      const data = doc.data();
      return `${(data.tenantId || '').toString()}:${(data.role || '').toString()}`;
    });

    outsideTenant.push({
      email: user.email || '',
      uid: user.uid,
      activeContexts: contexts.length > 0 ? contexts : ['(sem memberships ativos)'],
    });
  }

  outsideTenant.sort((a, b) => a.email.localeCompare(b.email));

  console.log('=== Tenant alvo ===');
  console.log(JSON.stringify({
    tenantId: TARGET_TENANT_ID,
    tenantName: tenantData.nomeFantasia || '',
    workspaceType: tenantData.workspaceType || '',
    ownerUid: tenantData.ownerUid || '',
    membershipsCount: tenantMembers.length,
  }, null, 2));

  console.log('\n=== Membros do tenant (com email) ===');
  for (const member of tenantMembers) {
    console.log(JSON.stringify(member));
  }

  console.log('\n=== Contas de dominio fora do tenant ===');
  console.log(`domain=${EMAIL_DOMAIN_FILTER} total=${outsideTenant.length}`);
  for (const user of outsideTenant) {
    console.log(JSON.stringify(user));
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
