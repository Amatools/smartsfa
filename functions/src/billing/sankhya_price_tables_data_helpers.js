const admin = require('firebase-admin');

function normalizePriceTableCodes(raw) {
  const tokens = [];
  if (Array.isArray(raw)) {
    for (const item of raw) {
      tokens.push(String(item ?? ''));
    }
  } else if (typeof raw === 'string') {
    tokens.push(...raw.split(/[\s,;|]+/));
  }

  const normalized = [];
  const seen = new Set();
  for (const token of tokens) {
    const clean = String(token ?? '').trim();
    if (!clean || !/^\d+$/.test(clean)) {
      continue;
    }
    if (seen.has(clean)) {
      continue;
    }
    seen.add(clean);
    normalized.push(clean);
  }
  return normalized;
}

async function buildTenantProductIndex({ firestore, tenantId }) {
  const snapshot = await firestore
    .collection('produtos')
    .where('tenantId', '==', tenantId)
    .select('erpProductId', 'codigoFabricante', 'deletedAt')
    .get();

  const index = new Map();
  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    if (data.deletedAt) {
      continue;
    }

    const keys = [
      toCodeString(data.erpProductId),
      toCodeString(data.codigoFabricante),
    ];

    for (const key of keys) {
      if (!key || isZeroCode(key)) {
        continue;
      }
      if (!index.has(key)) {
        index.set(key, {
          productId: doc.id,
        });
      }
    }
  }

  return index;
}

async function upsertPriceTableDocument({
  firestore,
  tenantId,
  priceTableDocId,
  tableCode,
  nowIso,
}) {
  const docRef = firestore.collection('tabelas_preco').doc(priceTableDocId);
  const snapshot = await docRef.get();
  const existing = snapshot.exists ? snapshot.data() || {} : {};

  await docRef.set(
    {
      id: priceTableDocId,
      tenantId,
      nome: existing.nome || `Tabela Sankhya ${tableCode}`,
      scopeType: existing.scopeType || 'general',
      scopeLabel: existing.scopeLabel || `Sankhya CODTAB ${tableCode}`,
      scopeIndex: existing.scopeIndex || [`sankhya`, `codtab_${tableCode}`],
      origem: 'erp',
      status: 'ativo',
      linkedEntityId: existing.linkedEntityId || null,
      createdAt: existing.createdAt || nowIso,
      updatedAt: nowIso,
    },
    { merge: true },
  );
}

async function upsertDefaultPriceTableDocument({
  firestore,
  tenantId,
  defaultPriceTableDocId,
  primaryTableCode,
  nowIso,
}) {
  const docRef = firestore.collection('tabelas_preco').doc(defaultPriceTableDocId);
  const snapshot = await docRef.get();
  const existing = snapshot.exists ? snapshot.data() || {} : {};

  await docRef.set(
    {
      id: defaultPriceTableDocId,
      tenantId,
      nome: existing.nome || 'Tabela padrao',
      scopeType: existing.scopeType || 'general',
      scopeLabel:
        existing.scopeLabel || `Tabela padrao vinculada ao Sankhya CODTAB ${primaryTableCode}`,
      scopeIndex: existing.scopeIndex || ['default', 'tenant_default'],
      origem: existing.origem || 'system',
      status: existing.status || 'ativo',
      linkedEntityId: existing.linkedEntityId || null,
      createdAt: existing.createdAt || nowIso,
      updatedAt: nowIso,
    },
    { merge: true },
  );

  await firestore.collection('tenants').doc(tenantId).set(
    {
      defaultPriceTableIds: { tenant_default: defaultPriceTableDocId },
      defaultPriceRegionIds: { tenant_default: 'default' },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function readPriceRowsFromPayload(payload) {
  if (Array.isArray(payload?.produtos)) {
    return payload.produtos;
  }
  if (Array.isArray(payload?.precos)) {
    return payload.precos;
  }
  return [];
}

function buildPriceTableDocId(tenantId, tableCode) {
  return `erp_pt_${tenantId}_${toCodeString(tableCode)}`;
}

function buildDefaultPriceTableDocId(tenantId) {
  return `pt_default_${tenantId}`;
}

function buildDefaultProductBasePriceDocId({
  tenantId,
  productId,
  defaultPriceTableDocId,
}) {
  return `pbp_${tenantId}_${productId}_${defaultPriceTableDocId}`;
}

function normalizeTextToken(value, fallback) {
  const raw = String(value ?? '').trim();
  if (!raw) {
    return fallback;
  }
  const normalized = raw
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^A-Za-z0-9_-]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return normalized || fallback;
}

function buildProductBasePriceDocId({
  tenantId,
  tableCode,
  productId,
  localCode,
  unitCode,
  controlCode,
}) {
  return [
    'erp_pbp',
    tenantId,
    toCodeString(tableCode),
    productId,
    normalizeTextToken(localCode, '0'),
    normalizeTextToken(unitCode, 'UN'),
    normalizeTextToken(controlCode, 'SEM_CONTROLE'),
  ].join('_');
}

function toCodeString(value) {
  if (value === null || value === undefined) {
    return '';
  }

  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      return '';
    }
    return String(Math.trunc(value));
  }

  return String(value).trim();
}

function isZeroCode(codeValue) {
  const normalized = String(codeValue ?? '').trim();
  if (!normalized) {
    return true;
  }

  const numeric = Number(normalized.replace(',', '.'));
  if (Number.isFinite(numeric) && numeric === 0) {
    return true;
  }

  return /^0+$/.test(normalized);
}

module.exports = {
  normalizePriceTableCodes,
  buildTenantProductIndex,
  upsertPriceTableDocument,
  upsertDefaultPriceTableDocument,
  readPriceRowsFromPayload,
  buildPriceTableDocId,
  buildDefaultPriceTableDocId,
  buildDefaultProductBasePriceDocId,
  normalizeTextToken,
  buildProductBasePriceDocId,
};
