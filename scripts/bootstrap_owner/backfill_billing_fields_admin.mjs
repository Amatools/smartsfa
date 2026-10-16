import process from 'node:process';

const API_KEY = process.env.FIREBASE_WEB_API_KEY ?? 'AIzaSyDFXV_T5_WfN2xrl-qi814i_AwReyGjXKs';
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID ?? 'smart-sfa';
const ADMIN_EMAIL = process.env.BILLING_ADMIN_EMAIL ?? process.env.LEGACY_CONTACT_EMAIL ?? 'contato@smartsfa.com.br';
const ADMIN_PASSWORD = process.env.BILLING_ADMIN_PASSWORD ?? process.env.TEST_PASSWORD ?? 'tester123';

function toFsValue(value) {
  if (value === null || value === undefined) {
    return { nullValue: null };
  }
  if (typeof value === 'string') {
    return { stringValue: value };
  }
  if (typeof value === 'boolean') {
    return { booleanValue: value };
  }
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map((item) => toFsValue(item)) } };
  }

  const fields = {};
  for (const [key, nested] of Object.entries(value)) {
    fields[key] = toFsValue(nested);
  }
  return { mapValue: { fields } };
}

function readString(fields, key) {
  const raw = fields?.[key];
  if (!raw || typeof raw !== 'object') {
    return '';
  }
  return (
    raw.stringValue ??
    raw.timestampValue ??
    ''
  ).toString().trim();
}

function hasField(fields, key) {
  return Boolean(fields && Object.prototype.hasOwnProperty.call(fields, key));
}

function isBlank(value) {
  return value.trim().length === 0;
}

function plusDays(isoDate, days) {
  const base = Date.parse(isoDate);
  if (Number.isNaN(base)) {
    return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
  }
  return new Date(base + days * 24 * 60 * 60 * 1000).toISOString();
}

function documentPathFromName(name) {
  const marker = '/documents/';
  const index = name.indexOf(marker);
  if (index < 0) {
    throw new Error(`Nome de documento invalido: ${name}`);
  }
  return name.slice(index + marker.length);
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload?.error?.message ?? response.statusText);
  }
  return payload;
}

async function signIn(email, password) {
  return postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    {
      email,
      password,
      returnSecureToken: true,
    },
  );
}

async function runQuery(body, token) {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(body),
    },
  );

  const payload = await response.json();
  if (!response.ok) {
    throw new Error(`runQuery: ${payload?.error?.message ?? response.statusText}`);
  }

  return payload.filter((row) => row.document?.name && row.document?.fields);
}

async function resolveAccessibleTenantIds(uid, token) {
  const rows = await runQuery(
    {
      structuredQuery: {
        from: [{ collectionId: 'tenant_memberships' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'uid' },
            op: 'EQUAL',
            value: { stringValue: uid },
          },
        },
      },
    },
    token,
  );

  const tenantIds = new Set();
  for (const row of rows) {
    const role = readString(row.document?.fields, 'role').toLowerCase();
    if (role !== 'owner') {
      continue;
    }

    const tenantId = readString(row.document?.fields, 'tenantId');
    if (!tenantId) {
      continue;
    }
    tenantIds.add(tenantId);
  }

  return Array.from(tenantIds);
}

async function listCollectionDocs(collectionId, token) {
  const results = [];
  let pageToken = '';

  do {
    const query = new URLSearchParams({ pageSize: '300' });
    if (pageToken) {
      query.set('pageToken', pageToken);
    }
    const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collectionId}?${query.toString()}`;

    const response = await fetch(url, {
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(`LIST ${collectionId}: ${payload?.error?.message ?? response.statusText}`);
    }

    if (Array.isArray(payload.documents)) {
      results.push(...payload.documents);
    }
    pageToken = payload.nextPageToken ?? '';
  } while (pageToken);

  return results;
}

async function patchDoc(path, data, token) {
  const fieldPaths = Object.keys(data);
  const query = new URLSearchParams();
  for (const fieldPath of fieldPaths) {
    query.append('updateMask.fieldPaths', fieldPath);
  }
  query.append('currentDocument.exists', 'true');

  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}?${query.toString()}`;
  const response = await fetch(url, {
    method: 'PATCH',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      fields: Object.fromEntries(
        Object.entries(data).map(([key, value]) => [key, toFsValue(value)]),
      ),
    }),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(`PATCH ${path}: ${payload?.error?.message ?? response.statusText}`);
  }
  return payload;
}

function buildTenantPatch(fields, nowIso) {
  const patch = {};

  if (isBlank(readString(fields, 'planTier'))) {
    patch.planTier = 'base';
  }
  if (isBlank(readString(fields, 'billingScope'))) {
    patch.billingScope = 'tenant';
  }

  const plan = readString(fields, 'plan');
  if (isBlank(readString(fields, 'billingPlanKey'))) {
    patch.billingPlanKey = plan || 'team';
  }
  if (isBlank(readString(fields, 'billingStatus'))) {
    patch.billingStatus = 'active';
  }
  if (isBlank(readString(fields, 'billingCycle'))) {
    patch.billingCycle = 'monthly';
  }
  if (!hasField(fields, 'billingGracePeriodDays')) {
    patch.billingGracePeriodDays = 7;
  }
  if (isBlank(readString(fields, 'billingDelinquencyStage'))) {
    patch.billingDelinquencyStage = 'none';
  }

  const periodStart = readString(fields, 'billingCurrentPeriodStartAt');
  const createdAt = readString(fields, 'createdAt');
  const effectiveStart = periodStart || createdAt || nowIso;

  if (isBlank(periodStart)) {
    patch.billingCurrentPeriodStartAt = effectiveStart;
  }

  const periodEnd = readString(fields, 'billingCurrentPeriodEndAt');
  if (isBlank(periodEnd)) {
    patch.billingCurrentPeriodEndAt = plusDays(effectiveStart, 30);
  }

  if (!hasField(fields, 'billingGraceUntilAt')) {
    patch.billingGraceUntilAt = null;
  }
  if (!hasField(fields, 'billingPastDueSinceAt')) {
    patch.billingPastDueSinceAt = null;
  }
  if (!hasField(fields, 'billingSuspendedAt')) {
    patch.billingSuspendedAt = null;
  }

  if (Object.keys(patch).length > 0) {
    patch.billingUpdatedAt = nowIso;
  }

  return patch;
}

function buildUserPatch(fields, nowIso) {
  const patch = {};

  if (isBlank(readString(fields, 'billingAccountState'))) {
    patch.billingAccountState = 'active';
  }
  if (!hasField(fields, 'billingGraceUntilAt')) {
    patch.billingGraceUntilAt = null;
  }
  if (!hasField(fields, 'billingSuspendedAt')) {
    patch.billingSuspendedAt = null;
  }

  if (Object.keys(patch).length > 0) {
    patch.billingUpdatedAt = nowIso;
  }

  return patch;
}

async function run() {
  console.log(`Autenticando admin para backfill: ${ADMIN_EMAIL}`);
  const auth = await signIn(ADMIN_EMAIL, ADMIN_PASSWORD);
  const token = auth.idToken;
  const uid = auth.localId;
  const nowIso = new Date().toISOString();

  let tenantDocs = [];
  let listingMode = 'global';
  try {
    tenantDocs = await listCollectionDocs('tenants', token);
  } catch (error) {
    const message = (error?.message ?? '').toString();
    const canFallback =
      message.toLowerCase().includes('missing or insufficient permissions');
    if (!canFallback) {
      throw error;
    }

    listingMode = 'membership_scope';
    const tenantIds = await resolveAccessibleTenantIds(uid, token);
    tenantDocs = tenantIds.map((tenantId) => ({
      name: `projects/${PROJECT_ID}/databases/(default)/documents/tenants/${tenantId}`,
      fields: { tenantId: { stringValue: tenantId } },
    }));
  }

  if (tenantDocs.length === 0) {
    console.log('Nenhum tenant encontrado para backfill no escopo da conta usada.');
  }

  let tenantPatched = 0;
  let tenantSkipped = 0;

  for (const doc of tenantDocs) {
    const patch = buildTenantPatch(doc.fields ?? {}, nowIso);
    if (Object.keys(patch).length === 0) {
      continue;
    }

    try {
      await patchDoc(documentPathFromName(doc.name), patch, token);
      tenantPatched += 1;
    } catch (error) {
      tenantSkipped += 1;
      console.warn(`Tenant ignorado por permissao/regra: ${documentPathFromName(doc.name)} -> ${error.message}`);
    }
  }

  let userDocs = [];
  if (listingMode === 'global') {
    userDocs = await listCollectionDocs('usuarios', token);
  } else {
    userDocs = [
      {
        name: `projects/${PROJECT_ID}/databases/(default)/documents/usuarios/${uid}`,
        fields: {},
      },
    ];
  }
  let userPatched = 0;
  let userSkipped = 0;

  for (const doc of userDocs) {
    const patch = buildUserPatch(doc.fields ?? {}, nowIso);
    if (Object.keys(patch).length === 0) {
      continue;
    }

    try {
      await patchDoc(documentPathFromName(doc.name), patch, token);
      userPatched += 1;
    } catch (error) {
      userSkipped += 1;
      console.warn(`Usuario ignorado por permissao/regra: ${documentPathFromName(doc.name)} -> ${error.message}`);
    }
  }

  console.log('Backfill billing concluido.');
  console.log(`modo: ${listingMode}`);
  console.log(`tenants atualizados: ${tenantPatched}/${tenantDocs.length}`);
  console.log(`tenants ignorados: ${tenantSkipped}`);
  console.log(`usuarios atualizados: ${userPatched}/${userDocs.length}`);
  console.log(`usuarios ignorados: ${userSkipped}`);
}

run().catch((error) => {
  console.error('Falha no backfill de billing:', error.message);
  process.exitCode = 1;
});
