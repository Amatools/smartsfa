import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import { cert, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const SERVICE_ACCOUNT_PATH =
  process.env.SERVICE_ACCOUNT_KEY_PATH ||
  './smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json';

const TENANT_ID_FILTER = (process.env.BACKFILL_TENANT_ID || '').trim();

function resolveServiceAccountPath() {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const normalized = path.resolve(scriptDir, SERVICE_ACCOUNT_PATH);
  if (!fs.existsSync(normalized)) {
    throw new Error(`Service account nao encontrada: ${normalized}`);
  }
  return normalized;
}

function normalizeRole(value) {
  return (value || '').toString().trim().toLowerCase();
}

function isMembershipActive(data) {
  const ativo = data?.ativo === true;
  const state = (data?.state || 'active').toString().trim().toLowerCase();
  return ativo && state === 'active';
}

function readCount(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.max(0, Math.trunc(value));
  }

  if (typeof value === 'string') {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return Math.max(0, parsed);
    }
  }

  return 0;
}

function buildDesiredCountsForTenant(docs) {
  const byUid = new Map();

  for (const doc of docs) {
    const data = doc.data() || {};
    const uid = (data.uid || '').toString().trim();
    if (!uid) {
      continue;
    }
    if (!byUid.has(uid)) {
      byUid.set(uid, { seller: 0, representative: 0 });
    }
  }

  for (const doc of docs) {
    const data = doc.data() || {};
    if (!isMembershipActive(data)) {
      continue;
    }

    const role = normalizeRole(data.role);
    const uid = (data.uid || '').toString().trim();

    if (role === 'vendedor') {
      const parentUid = (data.representanteId || '').toString().trim();
      if (!parentUid || parentUid === uid) {
        continue;
      }
      const bucket = byUid.get(parentUid);
      if (bucket) {
        bucket.seller += 1;
      }
      continue;
    }

    if (role === 'representante') {
      const parentUid = (data.gerenteId || '').toString().trim();
      if (!parentUid || parentUid === uid) {
        continue;
      }
      const bucket = byUid.get(parentUid);
      if (bucket) {
        bucket.representative += 1;
      }
    }
  }

  return byUid;
}

async function commitBatch(db, operations) {
  if (operations.length === 0) {
    return;
  }

  const batch = db.batch();
  for (const operation of operations) {
    batch.set(operation.ref, operation.patch, { merge: true });
  }
  await batch.commit();
}

async function main() {
  const servicePath = resolveServiceAccountPath();
  const credentials = JSON.parse(fs.readFileSync(servicePath, 'utf8'));
  initializeApp({ credential: cert(credentials) });

  const db = getFirestore();

  const snapshot = await db.collection('tenant_memberships').get();
  if (snapshot.empty) {
    console.log('Nenhum membership encontrado.');
    return;
  }

  const byTenant = new Map();
  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const tenantId = (data.tenantId || '').toString().trim();
    if (!tenantId) {
      continue;
    }
    if (TENANT_ID_FILTER && tenantId !== TENANT_ID_FILTER) {
      continue;
    }

    if (!byTenant.has(tenantId)) {
      byTenant.set(tenantId, []);
    }
    byTenant.get(tenantId).push(doc);
  }

  if (byTenant.size === 0) {
    if (TENANT_ID_FILTER) {
      console.log(`Nenhum membership encontrado para tenant ${TENANT_ID_FILTER}.`);
      return;
    }
    console.log('Nenhum membership elegivel para backfill.');
    return;
  }

  const nowIso = new Date().toISOString();
  let touchedDocs = 0;
  let tenantCount = 0;
  const operations = [];

  for (const [tenantId, docs] of byTenant.entries()) {
    tenantCount += 1;
    const desiredCounts = buildDesiredCountsForTenant(docs);

    for (const doc of docs) {
      const data = doc.data() || {};
      const uid = (data.uid || '').toString().trim();
      const desired = desiredCounts.get(uid) || { seller: 0, representative: 0 };

      const desiredSeller = desired.seller;
      const desiredRepresentative = desired.representative;
      const desiredTotal = desiredSeller + desiredRepresentative;

      const currentSeller = readCount(data.activeSellerChildrenCount);
      const currentRepresentative = readCount(data.activeRepresentativeChildrenCount);
      const currentTotal = readCount(data.activeSubordinateCount);

      if (
        currentSeller === desiredSeller &&
        currentRepresentative === desiredRepresentative &&
        currentTotal === desiredTotal
      ) {
        continue;
      }

      operations.push({
        ref: doc.ref,
        patch: {
          activeSellerChildrenCount: desiredSeller,
          activeRepresentativeChildrenCount: desiredRepresentative,
          activeSubordinateCount: desiredTotal,
          updatedAt: nowIso,
        },
      });

      touchedDocs += 1;
      if (operations.length >= 400) {
        await commitBatch(db, operations);
        operations.length = 0;
      }
    }

    console.log(`Tenant ${tenantId}: ${docs.length} memberships processados.`);
  }

  await commitBatch(db, operations);

  console.log('Backfill de agregados concluido.');
  console.log(`Tenants processados: ${tenantCount}`);
  console.log(`Memberships atualizados: ${touchedDocs}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
