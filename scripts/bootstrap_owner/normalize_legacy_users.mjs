import process from 'node:process';

const API_KEY = process.env.FIREBASE_WEB_API_KEY ?? 'AIzaSyDFXV_T5_WfN2xrl-qi814i_AwReyGjXKs';
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID ?? 'smart-sfa';
const PASSWORD = process.env.TEST_PASSWORD ?? 'tester123';

const CONTACT_EMAIL = process.env.LEGACY_CONTACT_EMAIL ?? 'contato@smartsfa.com.br';
const CONTACT_DISPLAY_NAME = process.env.LEGACY_CONTACT_DISPLAY_NAME ?? 'Contato Amatools';
const CONTACT_WORKSPACE_NAME = process.env.LEGACY_CONTACT_WORKSPACE_NAME ?? 'Amatools';
const CONTACT_RAZAO_SOCIAL =
  process.env.LEGACY_CONTACT_RAZAO_SOCIAL ??
  'Amatools Comercial e Importadora Ltda.';
const CONTACT_CNPJ = process.env.LEGACY_CONTACT_CNPJ ?? '07228424000157';
const CONTACT_LOGRADOURO = process.env.LEGACY_CONTACT_LOGRADOURO ?? 'Avenida Dois Corregos';
const CONTACT_NUMERO = process.env.LEGACY_CONTACT_NUMERO ?? '2650';
const CONTACT_CEP = process.env.LEGACY_CONTACT_CEP ?? '13420-835';
const CONTACT_CIDADE = process.env.LEGACY_CONTACT_CIDADE ?? 'Piracicaba';
const CONTACT_UF = process.env.LEGACY_CONTACT_UF ?? 'SP';

const SELLER_EMAIL = process.env.LEGACY_SELLER_EMAIL ?? 'vendas@smartsfa.com.br';
const SELLER_DISPLAY_NAME = process.env.LEGACY_SELLER_DISPLAY_NAME ?? 'Vendas Individual';
const SELLER_WORKSPACE_NAME = process.env.LEGACY_SELLER_WORKSPACE_NAME ?? 'Vendas Individual';

const REP_EMAIL = process.env.LEGACY_REP_EMAIL ?? 'representante@smartsfa.com.br';
const REP_DISPLAY_NAME = process.env.LEGACY_REP_DISPLAY_NAME ?? 'Representante Amatools';
const REP_WORKSPACE_NAME = process.env.LEGACY_REP_WORKSPACE_NAME ?? 'Amatools Representacoes';
const REP_RAZAO_SOCIAL =
  process.env.LEGACY_REP_RAZAO_SOCIAL ??
  'Amatools Representacoes Ltda.';
const REP_CNPJ = process.env.LEGACY_REP_CNPJ ?? '07228424000157';
const REP_CIDADE = process.env.LEGACY_REP_CIDADE ?? 'Piracicaba';
const REP_UF = process.env.LEGACY_REP_UF ?? 'SP';

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

function tenantIdFor(uid, workspaceName, plan) {
  if (plan === 'solo') {
    return `solo_${uid}`;
  }
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

async function createOrLoginUser(email, password, displayName) {
  const signInErrorMessages = new Set([
    'EMAIL_NOT_FOUND',
    'INVALID_LOGIN_CREDENTIALS',
    'INVALID_PASSWORD',
    'auth/user-not-found',
    'auth/wrong-password',
  ]);

  try {
    const signedIn = await signIn(email, password);
    return {
      email,
      displayName,
      uid: signedIn.localId,
      idToken: signedIn.idToken,
    };
  } catch (error) {
    const message = String(error?.message ?? error).toUpperCase();
    const shouldTrySignup = [...signInErrorMessages].some((code) => message.includes(code));
    if (!shouldTrySignup) {
      throw error;
    }
  }

  const signUpUrl = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`;
  try {
    const created = await postJson(signUpUrl, {
      email,
      password,
      returnSecureToken: true,
    });
    return {
      email,
      displayName,
      uid: created.localId,
      idToken: created.idToken,
    };
  } catch (error) {
    const message = String(error?.message ?? error).toUpperCase();
    if (!message.includes('EMAIL_EXISTS')) {
      throw error;
    }

    const signedIn = await signIn(email, password);
    return {
      email,
      displayName,
      uid: signedIn.localId,
      idToken: signedIn.idToken,
    };
  }
}

async function upsertUserDoc(auth, extra = {}) {
  await patchDoc(
    `usuarios/${auth.uid}`,
    {
      uid: auth.uid,
      email: auth.email,
      displayName: auth.displayName,
      platformRole: 'none',
      ativoGlobal: true,
      ...extra,
      updatedAt: new Date().toISOString(),
    },
    auth.idToken,
  );
}

async function bootstrapContactAccount() {
  console.log(`Provisionando conta enterprise legacy: ${CONTACT_EMAIL}`);
  const auth = await createOrLoginUser(CONTACT_EMAIL, PASSWORD, CONTACT_DISPLAY_NAME);
  const uid = auth.uid;
  const tenantId = tenantIdFor(uid, CONTACT_WORKSPACE_NAME, 'enterprise');
  const membershipId = `${tenantId}_${uid}`;
  const now = new Date().toISOString();

  await upsertUserDoc(auth, {
    accountContractLock: 'enterprise_only',
    defaultTenantId: tenantId,
    lastSelectedTenantId: tenantId,
  });

  await patchDoc(
    `tenants/${tenantId}`,
    {
      tenantId,
      slug: tenantId,
      nomeFantasia: CONTACT_WORKSPACE_NAME,
      razaoSocial: CONTACT_RAZAO_SOCIAL,
      ativo: true,
      plan: 'enterprise',
      workspaceType: 'brand_owner_workspace',
      hierarchyModel: 'full_chain',
      allowInvitations: true,
      operationMode: 'manual',
      erpProvider: 'none',
      ownerUid: uid,
      cnpj: CONTACT_CNPJ,
      logradouro: CONTACT_LOGRADOURO,
      numero: CONTACT_NUMERO,
      cep: CONTACT_CEP,
      cidade: CONTACT_CIDADE,
      uf: CONTACT_UF,
      cnpjBinding: 'owner_legal_entity',
      updatedAt: now,
    },
    auth.idToken,
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
    auth.idToken,
  );

  return { auth, tenantId, membershipId };
}

async function bootstrapSellerSoloAccount() {
  console.log(`Provisionando conta individual legacy: ${SELLER_EMAIL}`);
  const auth = await createOrLoginUser(SELLER_EMAIL, PASSWORD, SELLER_DISPLAY_NAME);
  const uid = auth.uid;
  const tenantId = tenantIdFor(uid, SELLER_WORKSPACE_NAME, 'solo');
  const membershipId = `${tenantId}_${uid}`;
  const now = new Date().toISOString();

  await upsertUserDoc(auth, {
    accountContractLock: 'flexible',
    defaultTenantId: tenantId,
    lastSelectedTenantId: tenantId,
  });

  await patchDoc(
    `tenants/${tenantId}`,
    {
      tenantId,
      slug: tenantId,
      nomeFantasia: SELLER_WORKSPACE_NAME,
      ativo: true,
      plan: 'solo',
      workspaceType: 'seller_solo_workspace',
      hierarchyModel: 'seller_only',
      allowInvitations: false,
      operationMode: 'manual',
      erpProvider: 'none',
      ownerUid: uid,
      updatedAt: now,
    },
    auth.idToken,
  );

  await patchDoc(
    `tenant_memberships/${membershipId}`,
    {
      membershipId,
      tenantId,
      uid,
      role: 'vendedor',
      ativo: true,
      defaultTenant: true,
      state: 'active',
      ownerId: '',
      gerenteId: '',
      representanteId: '',
      vendedorId: uid,
      updatedAt: now,
    },
    auth.idToken,
  );

  return { auth, tenantId, membershipId };
}

async function bootstrapRepAccount() {
  console.log(`Provisionando conta de representacoes legacy: ${REP_EMAIL}`);
  const auth = await createOrLoginUser(REP_EMAIL, PASSWORD, REP_DISPLAY_NAME);
  const uid = auth.uid;
  const tenantId = tenantIdFor(uid, REP_WORKSPACE_NAME, 'team');
  const membershipId = `${tenantId}_${uid}`;
  const now = new Date().toISOString();

  await upsertUserDoc(auth, {
    accountContractLock: 'flexible',
    defaultTenantId: tenantId,
    lastSelectedTenantId: tenantId,
  });

  await patchDoc(
    `tenants/${tenantId}`,
    {
      tenantId,
      slug: tenantId,
      nomeFantasia: REP_WORKSPACE_NAME,
      razaoSocial: REP_RAZAO_SOCIAL,
      ativo: true,
      plan: 'team',
      workspaceType: 'rep_workspace',
      hierarchyModel: 'full_chain',
      allowInvitations: true,
      operationMode: 'manual',
      erpProvider: 'none',
      ownerUid: uid,
      representedCompanyDocument: REP_CNPJ,
      cnpjBinding: 'informational_only',
      cidade: REP_CIDADE,
      uf: REP_UF,
      updatedAt: now,
    },
    auth.idToken,
  );

  await patchDoc(
    `tenant_memberships/${membershipId}`,
    {
      membershipId,
      tenantId,
      uid,
      role: 'representante',
      ativo: true,
      defaultTenant: true,
      state: 'active',
      ownerId: uid,
      gerenteId: '',
      representanteId: uid,
      vendedorId: '',
      updatedAt: now,
    },
    auth.idToken,
  );

  return { auth, tenantId, membershipId };
}

async function cleanupStaleMemberships(auth, tenantId) {
  const rows = await runQuery(
    {
      structuredQuery: {
        from: [{ collectionId: 'tenant_memberships' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'uid' },
            op: 'EQUAL',
            value: { stringValue: auth.uid },
          },
        },
      },
    },
    auth.idToken,
  );

  const now = new Date().toISOString();
  for (const row of rows) {
    const docFields = row.document.fields;
    const currentTenantId = readString(docFields, 'tenantId');
    if (!currentTenantId || currentTenantId === tenantId) {
      continue;
    }

    const membershipId = readString(docFields, 'membershipId') || `${currentTenantId}_${auth.uid}`;
    await patchDoc(
      `tenant_memberships/${membershipId}`,
      {
        membershipId,
        tenantId: currentTenantId,
        uid: auth.uid,
        role: readString(docFields, 'role') || 'vendedor',
        ativo: false,
        defaultTenant: false,
        state: 'inactive',
        ownerId: readString(docFields, 'ownerId'),
        gerenteId: readString(docFields, 'gerenteId'),
        representanteId: readString(docFields, 'representanteId'),
        vendedorId: readString(docFields, 'vendedorId'),
        updatedAt: now,
      },
      auth.idToken,
    );
  }
}

async function run() {
  console.log('Normalizando usuarios legados para o novo formato...');

  const contact = await bootstrapContactAccount();
  const seller = await bootstrapSellerSoloAccount();
  const rep = await bootstrapRepAccount();

  await cleanupStaleMemberships(contact.auth, contact.tenantId);
  await cleanupStaleMemberships(seller.auth, seller.tenantId);
  await cleanupStaleMemberships(rep.auth, rep.tenantId);

  console.log('\nUsuarios normalizados com sucesso.');
  console.log(`contato: ${contact.auth.email} -> brand_owner_workspace (${contact.tenantId})`);
  console.log(`vendas: ${seller.auth.email} -> seller_solo_workspace (${seller.tenantId})`);
  console.log(`representante: ${rep.auth.email} -> rep_workspace (${rep.tenantId})`);
}

run().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
