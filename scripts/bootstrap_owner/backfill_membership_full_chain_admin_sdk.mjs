import { readFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultCredentialsPath = path.resolve(
  __dirname,
  'smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json',
);

const credentialsPath =
  process.env.FIREBASE_ADMIN_CREDENTIALS_PATH ?? defaultCredentialsPath;
const explicitProjectId = process.env.FIREBASE_PROJECT_ID ?? '';
const dryRun = (process.env.DRY_RUN ?? 'false').toLowerCase() === 'true';

function normalizeRole(value) {
  return String(value ?? '').trim().toLowerCase();
}

function buildPatch({ membership, workspaceType, ownerUid }) {
  if (workspaceType === 'seller_solo_workspace') {
    return null;
  }

  const role = normalizeRole(membership.role);
  const uid = String(membership.uid ?? '').trim();
  if (!role || !uid) {
    return null;
  }

  const currentOwnerId = String(membership.ownerId ?? '').trim();
  const currentGerenteId = String(membership.gerenteId ?? '').trim();
  const currentRepresentanteId = String(membership.representanteId ?? '').trim();
  const currentVendedorId = String(membership.vendedorId ?? '').trim();

  const ownerFallback = currentOwnerId || String(ownerUid ?? '').trim() || uid;
  const managerFallback = currentGerenteId || ownerFallback;
  const representativeFallback =
    currentRepresentanteId || (role === 'vendedor' ? ownerFallback : uid) || ownerFallback;

  let desiredOwnerId = currentOwnerId;
  let desiredGerenteId = currentGerenteId;
  let desiredRepresentanteId = currentRepresentanteId;
  let desiredVendedorId = currentVendedorId;

  if (role === 'owner') {
    desiredOwnerId = uid;
    desiredGerenteId = uid;
    desiredRepresentanteId = uid;
    desiredVendedorId = uid;
  } else if (role === 'gerente') {
    desiredOwnerId = ownerFallback;
    desiredGerenteId = uid;
    desiredRepresentanteId = uid;
    desiredVendedorId = uid;
  } else if (role === 'representante') {
    desiredOwnerId = ownerFallback;
    desiredGerenteId = managerFallback;
    desiredRepresentanteId = uid;
    desiredVendedorId = uid;
  } else if (role === 'vendedor') {
    desiredOwnerId = ownerFallback;
    desiredGerenteId = managerFallback;
    desiredRepresentanteId = representativeFallback;
    desiredVendedorId = uid;
  } else {
    return null;
  }

  const patch = {};
  if (currentOwnerId !== desiredOwnerId) {
    patch.ownerId = desiredOwnerId;
  }
  if (currentGerenteId !== desiredGerenteId) {
    patch.gerenteId = desiredGerenteId;
  }
  if (currentRepresentanteId !== desiredRepresentanteId) {
    patch.representanteId = desiredRepresentanteId;
  }
  if (currentVendedorId !== desiredVendedorId) {
    patch.vendedorId = desiredVendedorId;
  }

  if (Object.keys(patch).length === 0) {
    return null;
  }

  patch.updatedAt = FieldValue.serverTimestamp();
  return patch;
}

async function initializeFirebaseAdmin() {
  const credentialsRaw = await readFile(credentialsPath, 'utf8');
  const credentials = JSON.parse(credentialsRaw);
  const projectId = explicitProjectId || credentials.project_id || 'smart-sfa';

  if (getApps().length === 0) {
    initializeApp({
      credential: cert(credentials),
      projectId,
    });
  }

  return getFirestore();
}

async function run() {
  console.log(`Iniciando backfill full-chain via Admin SDK${dryRun ? ' (dry-run)' : ''}...`);
  console.log(`Credenciais: ${credentialsPath}`);

  const db = await initializeFirebaseAdmin();
  const tenantsSnapshot = await db.collection('tenants').get();

  let processedTenants = 0;
  let processedMemberships = 0;
  let updatedMemberships = 0;
  let unchangedMemberships = 0;

  let batch = db.batch();
  let batchOps = 0;

  for (const tenantDoc of tenantsSnapshot.docs) {
    const tenant = tenantDoc.data() ?? {};
    const tenantId = String(tenant.tenantId ?? tenantDoc.id).trim();
    const workspaceType = String(tenant.workspaceType ?? '').trim();
    const ownerUid = String(tenant.ownerUid ?? '').trim();

    if (!tenantId) {
      continue;
    }

    if (workspaceType === 'seller_solo_workspace') {
      continue;
    }

    processedTenants += 1;
    const membershipsSnapshot = await db
      .collection('tenant_memberships')
      .where('tenantId', '==', tenantId)
      .get();

    for (const membershipDoc of membershipsSnapshot.docs) {
      const membership = membershipDoc.data() ?? {};
      processedMemberships += 1;

      const patch = buildPatch({
        membership,
        workspaceType,
        ownerUid,
      });

      if (!patch) {
        unchangedMemberships += 1;
        continue;
      }

      updatedMemberships += 1;
      if (dryRun) {
        continue;
      }

      batch.update(membershipDoc.ref, patch);
      batchOps += 1;

      if (batchOps >= 400) {
        await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    }
  }

  if (!dryRun && batchOps > 0) {
    await batch.commit();
  }

  console.log('Backfill full-chain concluido.');
  console.log(`tenants processados: ${processedTenants}`);
  console.log(`memberships processados: ${processedMemberships}`);
  console.log(`memberships atualizados: ${updatedMemberships}`);
  console.log(`memberships sem mudanca: ${unchangedMemberships}`);
}

run().catch((error) => {
  console.error('Falha no backfill full-chain:', error.message);
  process.exitCode = 1;
});
