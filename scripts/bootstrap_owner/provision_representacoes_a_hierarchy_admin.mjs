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

const OWNER_EMAIL = (process.env.REP_OWNER_EMAIL || 'owner@smartsfa.com.br')
  .trim()
  .toLowerCase();
const REPRESENTANTE_EMAIL = (
  process.env.REP_REPRESENTANTE_EMAIL || 'representante@smartsfa.com.br'
)
  .trim()
  .toLowerCase();
const VENDEDOR_EMAIL = (process.env.REP_VENDEDOR_EMAIL || 'vendedor@smartsfa.com.br')
  .trim()
  .toLowerCase();

const TENANT_NAME = process.env.REP_TENANT_NAME || 'Representacoes A';
const TENANT_ID_OVERRIDE = (process.env.REP_TENANT_ID || '').trim();
const TENANT_CNPJ = (process.env.REP_TENANT_CNPJ || '').trim();
const DEFAULT_TEST_PASSWORD = process.env.TEST_ACCOUNT_PASSWORD || 'Smartsfa@123456';
const CREATE_MISSING_USERS = String(process.env.CREATE_MISSING_USERS || 'false') === 'true';

function resolveServiceAccountPath() {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const normalized = path.resolve(scriptDir, SERVICE_ACCOUNT_PATH);
  if (!fs.existsSync(normalized)) {
    throw new Error(`Service account nao encontrada: ${normalized}`);
  }
  return normalized;
}

function slugify(value) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 42);
}

async function findOrCreateUser(email, displayName) {
  try {
    return await getAuth().getUserByEmail(email);
  } catch (error) {
    if (error?.code !== 'auth/user-not-found') {
      throw error;
    }

    if (!CREATE_MISSING_USERS) {
      throw new Error(
        `Usuario ${email} nao encontrado no Auth. Defina CREATE_MISSING_USERS=true para criar automaticamente.`,
      );
    }

    return getAuth().createUser({
      email,
      displayName,
      password: DEFAULT_TEST_PASSWORD,
      emailVerified: true,
      disabled: false,
    });
  }
}

async function upsertUserDoc(uid, email, displayName, tenantId) {
  const now = new Date().toISOString();
  await getFirestore()
    .collection('usuarios')
    .doc(uid)
    .set(
      {
        uid,
        email,
        displayName,
        platformRole: 'none',
        ativoGlobal: true,
        accountContractLock: 'flexible',
        defaultTenantId: tenantId,
        lastSelectedTenantId: tenantId,
        updatedAt: now,
      },
      { merge: true },
    );
}

async function upsertMembership({
  tenantId,
  uid,
  role,
  ownerId,
  representanteId,
  vendedorId,
}) {
  const membershipId = `${tenantId}_${uid}`;
  await getFirestore()
    .collection('tenant_memberships')
    .doc(membershipId)
    .set(
      {
        membershipId,
        tenantId,
        uid,
        role,
        ativo: true,
        defaultTenant: true,
        state: 'active',
        ownerId,
        gerenteId: '',
        representanteId,
        vendedorId,
        updatedAt: new Date().toISOString(),
      },
      { merge: true },
    );
}

async function resolveRepTenantId(ownerUid) {
  if (TENANT_ID_OVERRIDE) {
    return TENANT_ID_OVERRIDE;
  }

  const db = getFirestore();
  const existingOwnerMembership = await db
    .collection('tenant_memberships')
    .where('uid', '==', ownerUid)
    .where('role', '==', 'owner')
    .where('ativo', '==', true)
    .where('state', '==', 'active')
    .limit(20)
    .get();

  for (const doc of existingOwnerMembership.docs) {
    const tenantId = (doc.data().tenantId || '').toString();
    if (!tenantId) {
      continue;
    }
    const tenantDoc = await db.collection('tenants').doc(tenantId).get();
    const workspaceType = (tenantDoc.data()?.workspaceType || '').toString();
    if (workspaceType === 'rep_workspace') {
      return tenantId;
    }
  }

  return `self_${ownerUid}_${slugify(TENANT_NAME) || 'representacoes-a'}`;
}

async function upsertRepTenant({ tenantId, ownerUid }) {
  const now = new Date().toISOString();
  await getFirestore()
    .collection('tenants')
    .doc(tenantId)
    .set(
      {
        tenantId,
        slug: tenantId,
        nomeFantasia: TENANT_NAME,
        razaoSocial: `${TENANT_NAME} LTDA`,
        ativo: true,
        plan: 'team',
        workspaceType: 'rep_workspace',
        hierarchyModel: 'rep_to_seller',
        allowInvitations: true,
        operationMode: 'manual',
        erpProvider: 'none',
        ownerUid,
        representedCompanyDocument: TENANT_CNPJ,
        cnpjBinding: 'informational_only',
        updatedAt: now,
      },
      { merge: true },
    );
}

async function main() {
  const servicePath = resolveServiceAccountPath();
  const credentials = JSON.parse(fs.readFileSync(servicePath, 'utf8'));

  initializeApp({
    credential: cert(credentials),
  });

  const owner = await findOrCreateUser(OWNER_EMAIL, 'Owner Representacoes A');
  const representante = await findOrCreateUser(
    REPRESENTANTE_EMAIL,
    'Representante Representacoes A',
  );
  const vendedor = await findOrCreateUser(VENDEDOR_EMAIL, 'Vendedor Representacoes A');

  const tenantId = await resolveRepTenantId(owner.uid);
  await upsertRepTenant({ tenantId, ownerUid: owner.uid });

  await upsertUserDoc(owner.uid, OWNER_EMAIL, owner.displayName || 'Owner Representacoes A', tenantId);
  await upsertUserDoc(
    representante.uid,
    REPRESENTANTE_EMAIL,
    representante.displayName || 'Representante Representacoes A',
    tenantId,
  );
  await upsertUserDoc(
    vendedor.uid,
    VENDEDOR_EMAIL,
    vendedor.displayName || 'Vendedor Representacoes A',
    tenantId,
  );

  await upsertMembership({
    tenantId,
    uid: owner.uid,
    role: 'owner',
    ownerId: owner.uid,
    representanteId: '',
    vendedorId: '',
  });
  await upsertMembership({
    tenantId,
    uid: representante.uid,
    role: 'representante',
    ownerId: owner.uid,
    representanteId: representante.uid,
    vendedorId: '',
  });
  await upsertMembership({
    tenantId,
    uid: vendedor.uid,
    role: 'vendedor',
    ownerId: owner.uid,
    representanteId: representante.uid || owner.uid,
    vendedorId: vendedor.uid,
  });

  console.log('Representacoes A provisionado com sucesso.');
  console.log(`tenantId: ${tenantId}`);
  console.log(`owner: ${OWNER_EMAIL} (${owner.uid})`);
  console.log(`representante: ${REPRESENTANTE_EMAIL} (${representante.uid})`);
  console.log(`vendedor: ${VENDEDOR_EMAIL} (${vendedor.uid})`);
}

main().catch((error) => {
  console.error('Falha no provisionamento de Representacoes A.');
  console.error(error);
  process.exitCode = 1;
});