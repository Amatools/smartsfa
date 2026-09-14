import process from 'node:process';

const API_KEY = process.env.FIREBASE_WEB_API_KEY ?? 'AIzaSyDFXV_T5_WfN2xrl-qi814i_AwReyGjXKs';
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID ?? 'smart-sfa';
const EMAIL = process.env.ENTERPRISE_EMAIL ?? 'empresa@smartsfa.com.br';
const PASSWORD = process.env.ENTERPRISE_PASSWORD ?? 'tester123';
const DISPLAY_NAME = process.env.ENTERPRISE_DISPLAY_NAME ?? 'Empresa Amatools';
const WORKSPACE_NAME = process.env.ENTERPRISE_WORKSPACE_NAME ?? 'Amatools';
const RAZAO_SOCIAL =
  process.env.ENTERPRISE_RAZAO_SOCIAL ??
  'Amatools Comercial e Importadora Ltda.';
const CNPJ = process.env.ENTERPRISE_CNPJ ?? '07228424000157';
const LOGRADOURO = process.env.ENTERPRISE_LOGRADOURO ?? 'Avenida Dois Corregos';
const NUMERO = process.env.ENTERPRISE_NUMERO ?? '2650';
const CEP = process.env.ENTERPRISE_CEP ?? '13420-835';
const CIDADE = process.env.ENTERPRISE_CIDADE ?? 'Piracicaba';
const UF = process.env.ENTERPRISE_UF ?? 'SP';

function slugify(value) {
  const slug = String(value)
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-+/g, '-');
  return slug || Date.now().toString();
}

function tenantIdFor(uid, workspaceName) {
  return `self_${uid}_${slugify(workspaceName).slice(0, 48)}`;
}

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
    return { integerValue: String(value) };
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

async function patchDoc(path, data, token) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`;
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

async function getDoc(path, token) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`;
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

function readString(fields, key) {
  return fields?.[key]?.stringValue ?? '';
}

async function signIn(email, password) {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`;
  return postJson(url, {
    email,
    password,
    returnSecureToken: true,
  });
}

async function run() {
  console.log(`Autenticando conta enterprise: ${EMAIL}`);
  const auth = await signIn(EMAIL, PASSWORD);
  const uid = auth.localId;
  const idToken = auth.idToken;
  const userDoc = await getDoc(`usuarios/${uid}`, idToken);
  const persistedDefaultTenantId = readString(userDoc?.fields, 'defaultTenantId');
  const membershipRows = await runQuery(
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
    idToken,
  );
  const existingTenantIds = membershipRows
    .map((row) => readString(row.document.fields, 'tenantId'))
    .filter(Boolean);
  const tenantId =
    persistedDefaultTenantId ||
    existingTenantIds.find((item) => item.includes('amatools')) ||
    tenantIdFor(uid, WORKSPACE_NAME);
  const membershipId = `${tenantId}_${uid}`;
  const now = new Date().toISOString();

  await patchDoc(
    `usuarios/${uid}`,
    {
      uid,
      email: EMAIL,
      displayName: DISPLAY_NAME,
      platformRole: 'none',
      ativoGlobal: true,
      accountContractLock: 'enterprise_only',
      defaultTenantId: tenantId,
      lastSelectedTenantId: tenantId,
      updatedAt: now,
    },
    idToken,
  );

  await patchDoc(
    `tenants/${tenantId}`,
    {
      tenantId,
      slug: tenantId,
      nomeFantasia: WORKSPACE_NAME,
      razaoSocial: RAZAO_SOCIAL,
      ativo: true,
      operationMode: 'manual',
      erpProvider: 'none',
      plan: 'enterprise',
      workspaceType: 'brand_owner_workspace',
      hierarchyModel: 'full_chain',
      allowInvitations: true,
      ownerUid: uid,
      cnpj: CNPJ,
      logradouro: LOGRADOURO,
      numero: NUMERO,
      cep: CEP,
      cidade: CIDADE,
      uf: UF,
      cnpjBinding: 'owner_legal_entity',
      updatedAt: now,
    },
    idToken,
  );

  await patchDoc(
    `tenant_memberships/${membershipId}`,
    {
      membershipId,
      tenantId,
      uid,
      role: 'owner',
      ativo: true,
      defaultTenant: true,
      state: 'active',
      ownerId: uid,
      gerenteId: '',
      representanteId: '',
      vendedorId: '',
      updatedAt: now,
    },
    idToken,
  );

  for (const candidateTenantId of existingTenantIds) {
    if (candidateTenantId === tenantId) {
      continue;
    }

    const duplicateMembershipId = `${candidateTenantId}_${uid}`;
    await patchDoc(
      `tenant_memberships/${duplicateMembershipId}`,
      {
        membershipId: duplicateMembershipId,
        tenantId: candidateTenantId,
        uid,
        role: 'owner',
        ativo: false,
        defaultTenant: true,
        state: 'inactive',
        ownerId: uid,
        gerenteId: '',
        representanteId: '',
        vendedorId: '',
        updatedAt: now,
      },
      idToken,
    );
  }

  console.log('Conta enterprise provisionada com sucesso.');
  console.log(`email: ${EMAIL}`);
  console.log(`tenantId: ${tenantId}`);
  console.log(`workspaceType: brand_owner_workspace`);
  console.log(`accountContractLock: enterprise_only`);
}

run().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
