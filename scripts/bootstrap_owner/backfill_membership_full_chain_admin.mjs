import process from 'node:process';

const API_KEY =
  process.env.FIREBASE_WEB_API_KEY ??
  'AIzaSyDFXV_T5_WfN2xrl-qi814i_AwReyGjXKs';
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID ?? 'smart-sfa';
const ADMIN_EMAIL =
  process.env.HIERARCHY_ADMIN_EMAIL ??
  process.env.BILLING_ADMIN_EMAIL ??
  process.env.LEGACY_CONTACT_EMAIL ??
  'contato@smartsfa.com.br';
const ADMIN_PASSWORD =
  process.env.HIERARCHY_ADMIN_PASSWORD ??
  process.env.BILLING_ADMIN_PASSWORD ??
  process.env.TEST_PASSWORD ??
  'tester123';

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
  return (raw.stringValue ?? raw.timestampValue ?? '').toString().trim();
}

function readBool(fields, key) {
  const raw = fields?.[key];
  if (!raw || typeof raw !== 'object') {
    return false;
  }
  return raw.booleanValue === true;
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

async function listCollectionDocs(collectionId, token) {
  const results = [];
  let pageToken = '';

  do {
    const query = new URLSearchParams({ pageSize: '300' });
    if (pageToken) {
      query.set('pageToken', pageToken);
    }
    const url =
      `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collectionId}?${query.toString()}`;

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

async function getDoc(path, token) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`;
  const response = await fetch(url, {
    headers: {
      authorization: `Bearer ${token}`,
    },
  });

  if (response.status === 404) {
    return null;
  }

  const payload = await response.json();
  if (!response.ok) {
    throw new Error(`GET ${path}: ${payload?.error?.message ?? response.statusText}`);
  }

  return payload;
}

async function patchDoc(path, data, token) {
  const fieldPaths = Object.keys(data);
  const query = new URLSearchParams();
  for (const fieldPath of fieldPaths) {
    query.append('updateMask.fieldPaths', fieldPath);
  }
  query.append('currentDocument.exists', 'true');

  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}?${query.toString()}`;
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

async function resolveOwnedTenantIds(uid, token) {
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
    const fields = row.document?.fields;
    const role = readString(fields, 'role').toLowerCase();
    const isActive = readBool(fields, 'ativo');
    if (role !== 'owner' || !isActive) {
      continue;
    }

    const tenantId = readString(fields, 'tenantId');
    if (tenantId) {
      tenantIds.add(tenantId);
    }
  }

  return Array.from(tenantIds);
}

async function listMembershipDocsForTenant(tenantId, token) {
  const rows = await runQuery(
    {
      structuredQuery: {
        from: [{ collectionId: 'tenant_memberships' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'tenantId' },
            op: 'EQUAL',
            value: { stringValue: tenantId },
          },
        },
      },
    },
    token,
  );

  return rows.map((row) => row.document);
}

function buildFullChainPatch({ membershipFields, workspaceType, tenantOwnerUid, nowIso }) {
  if (workspaceType === 'seller_solo_workspace') {
    return null;
  }

  const role = readString(membershipFields, 'role').toLowerCase();
  const uid = readString(membershipFields, 'uid');
  if (!role || !uid) {
    return null;
  }

  const currentOwnerId = readString(membershipFields, 'ownerId');
  const currentGerenteId = readString(membershipFields, 'gerenteId');
  const currentRepresentanteId = readString(membershipFields, 'representanteId');
  const currentVendedorId = readString(membershipFields, 'vendedorId');

  const ownerFallback = currentOwnerId || tenantOwnerUid || uid;
  const managerFallback = currentGerenteId || ownerFallback;
  const representativeFallback =
    currentRepresentanteId ||
    (role === 'vendedor' ? ownerFallback : uid) ||
    ownerFallback;

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

  patch.updatedAt = nowIso;
  return patch;
}

async function run() {
  console.log(`Autenticando conta para backfill de hierarquia: ${ADMIN_EMAIL}`);
  const auth = await signIn(ADMIN_EMAIL, ADMIN_PASSWORD);
  const token = auth.idToken;
  const uid = auth.localId;
  const nowIso = new Date().toISOString();

  let listingMode = 'global';
  let membershipDocs = [];

  try {
    membershipDocs = await listCollectionDocs('tenant_memberships', token);
  } catch (error) {
    const message = (error?.message ?? '').toString().toLowerCase();
    if (!message.includes('missing or insufficient permissions')) {
      throw error;
    }

    listingMode = 'owner_scope';
    const tenantIds = await resolveOwnedTenantIds(uid, token);
    membershipDocs = [];
    for (const tenantId of tenantIds) {
      const docs = await listMembershipDocsForTenant(tenantId, token);
      membershipDocs.push(...docs);
    }
  }

  const tenantInfoCache = new Map();
  let patched = 0;
  let skipped = 0;
  let unchanged = 0;

  for (const doc of membershipDocs) {
    const membershipPath = documentPathFromName(doc.name);
    const membershipFields = doc.fields ?? {};
    const tenantId = readString(membershipFields, 'tenantId');
    if (!tenantId) {
      unchanged += 1;
      continue;
    }

    if (!tenantInfoCache.has(tenantId)) {
      try {
        const tenantDoc = await getDoc(`tenants/${tenantId}`, token);
        const tenantFields = tenantDoc?.fields ?? {};
        tenantInfoCache.set(tenantId, {
          workspaceType:
            readString(tenantFields, 'workspaceType') ||
            'brand_owner_workspace',
          ownerUid: readString(tenantFields, 'ownerUid'),
        });
      } catch (error) {
        tenantInfoCache.set(tenantId, {
          workspaceType: '',
          ownerUid: '',
          error: error,
        });
      }
    }

    const tenantInfo = tenantInfoCache.get(tenantId);
    if (!tenantInfo || tenantInfo.error) {
      skipped += 1;
      continue;
    }

    const patch = buildFullChainPatch({
      membershipFields,
      workspaceType: tenantInfo.workspaceType,
      tenantOwnerUid: tenantInfo.ownerUid,
      nowIso,
    });

    if (!patch) {
      unchanged += 1;
      continue;
    }

    try {
      await patchDoc(membershipPath, patch, token);
      patched += 1;
    } catch (error) {
      skipped += 1;
      console.warn(
        `Membership ignorado por permissao/regra: ${membershipPath} -> ${error.message}`,
      );
    }
  }

  console.log('Backfill de hierarquia concluido.');
  console.log(`modo: ${listingMode}`);
  console.log(`memberships processados: ${membershipDocs.length}`);
  console.log(`memberships atualizados: ${patched}`);
  console.log(`memberships sem mudanca: ${unchanged}`);
  console.log(`memberships ignorados: ${skipped}`);
}

run().catch((error) => {
  console.error('Falha no backfill de hierarquia:', error.message);
  process.exitCode = 1;
});
