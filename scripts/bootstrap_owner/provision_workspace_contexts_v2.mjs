import process from 'node:process';

const API_KEY = process.env.FIREBASE_WEB_API_KEY ?? 'AIzaSyDFXV_T5_WfN2xrl-qi814i_AwReyGjXKs';
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID ?? 'smart-sfa';
const PASSWORD = process.env.TEST_PASSWORD ?? 'tester123';

const scenarios = {
  sellerSolo: {
    email: 'roberto.solo@smartsfa.com.br',
    displayName: 'Roberto Solo',
    workspaceName: 'Roberto Vendas',
    plan: 'solo',
    workspaceType: 'seller_solo_workspace',
    hierarchyModel: 'seller_only',
    allowInvitations: false,
    cnpjBinding: 'informational_only',
    representedCompanyDocument: '00000000000000',
  },
  repWorkspace: {
    owner: {
      email: 'owner.multiop@smartsfa.com.br',
      displayName: 'Owner Representacoes',
    },
    manager: {
      email: 'gerente.multiop@smartsfa.com.br',
      displayName: 'Gerente Representacoes',
    },
    representative: {
      email: 'representante.multiop@smartsfa.com.br',
      displayName: 'Representante Representacoes',
    },
    seller: {
      email: 'vendedor.multiop@smartsfa.com.br',
      displayName: 'Vendedor Representacoes',
    },
    workspaceName: 'Amatools Representacoes',
    plan: 'team',
    workspaceType: 'rep_workspace',
    hierarchyModel: 'full_chain',
    allowInvitations: true,
    cnpjBinding: 'informational_only',
    representedCompanyDocument: '07228424000157',
    contatoResponsavel: 'Owner Representacoes',
    cidade: 'Piracicaba',
    uf: 'SP',
  },
};

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

function tenantIdFor({ uid, plan, workspaceName }) {
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

async function postJson(url, body, token) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
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

  if (response.status === 404 || response.status === 403) {
    return null;
  }

  const payload = await response.json();
  if (!response.ok) {
    throw new Error(`GET ${path}: ${payload?.error?.message ?? response.statusText}`);
  }
  return payload;
}

async function createOrLoginUser(email, password, displayName) {
  console.log(`Auth: ${email}`);
  const signUpUrl = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`;
  const signInUrl = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`;
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
      created: true,
    };
  } catch (error) {
    if (!String(error.message).includes('EMAIL_EXISTS')) {
      throw error;
    }
  }

  const signedIn = await postJson(signInUrl, {
    email,
    password,
    returnSecureToken: true,
  });
  return {
    email,
    displayName,
    uid: signedIn.localId,
    idToken: signedIn.idToken,
    created: false,
  };
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

async function bootstrapSelfServiceWorkspace({ auth, scenario }) {
  console.log(`Workspace: ${scenario.workspaceType} for ${auth.email}`);
  const tenantId = tenantIdFor({
    uid: auth.uid,
    plan: scenario.plan,
    workspaceName: scenario.workspaceName,
  });
  const membershipId = `${tenantId}_${auth.uid}`;
  const tenantDoc = {
    tenantId,
    slug: tenantId,
    nomeFantasia: scenario.workspaceName,
    ativo: true,
    operationMode: 'manual',
    erpProvider: 'none',
    plan: scenario.plan,
    workspaceType: scenario.workspaceType,
    hierarchyModel: scenario.hierarchyModel,
    allowInvitations: scenario.allowInvitations,
    cnpjBinding: scenario.cnpjBinding,
    ownerUid: auth.uid,
    updatedAt: new Date().toISOString(),
  };

  if (scenario.cnpj) {
    tenantDoc.cnpj = scenario.cnpj;
  }
  if (scenario.razaoSocial) {
    tenantDoc.razaoSocial = scenario.razaoSocial;
  }
  if (scenario.contatoResponsavel) {
    tenantDoc.contatoResponsavel = scenario.contatoResponsavel;
  }
  if (scenario.representedCompanyDocument) {
    tenantDoc.representedCompanyDocument = scenario.representedCompanyDocument;
  }
  if (scenario.logradouro) {
    tenantDoc.logradouro = scenario.logradouro;
  }
  if (scenario.numero) {
    tenantDoc.numero = scenario.numero;
  }
  if (scenario.cep) {
    tenantDoc.cep = scenario.cep;
  }
  if (scenario.cidade) {
    tenantDoc.cidade = scenario.cidade;
  }
  if (scenario.uf) {
    tenantDoc.uf = scenario.uf;
  }

  const membershipDoc = {
    membershipId,
    tenantId,
    uid: auth.uid,
    role: scenario.workspaceType === 'seller_solo_workspace'
      ? 'vendedor'
      : scenario.workspaceType === 'rep_workspace'
      ? 'representante'
      : 'owner',
    ativo: true,
    defaultTenant: true,
    state: 'active',
    ownerId: scenario.workspaceType === 'brand_owner_workspace' ? auth.uid : '',
    gerenteId: '',
    representanteId: scenario.workspaceType === 'rep_workspace' ? auth.uid : '',
    vendedorId: scenario.workspaceType === 'seller_solo_workspace' ? auth.uid : '',
    updatedAt: new Date().toISOString(),
  };

  await upsertUserDoc(auth, {
    defaultTenantId: tenantId,
    lastSelectedTenantId: tenantId,
  });
  const existingTenant = await getDoc(`tenants/${tenantId}`, auth.idToken);
  if (!existingTenant) {
    await patchDoc(`tenants/${tenantId}`, tenantDoc, auth.idToken);
  }

  const existingMembership = await getDoc(
    `tenant_memberships/${membershipId}`,
    auth.idToken,
  );
  if (!existingMembership) {
    await patchDoc(`tenant_memberships/${membershipId}`, membershipDoc, auth.idToken);
  }

  return { tenantId, membershipId };
}

async function createInvitation({ actor, tenantId, role, invitedEmail, defaultTenant = false }) {
  console.log(`Invite: ${actor.email} -> ${invitedEmail} as ${role}`);
  const token = `${tenantId}_${role}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  await patchDoc(
    `tenant_invitations/${token}`,
    {
      token,
      tenantId,
      role,
      status: 'pending',
      invitedEmail,
      defaultTenant,
      createdByUid: actor.uid,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    actor.idToken,
  );
  return token;
}

async function createManagedMembership({
  actor,
  target,
  tenantId,
  role,
  scope,
}) {
  console.log(`Membership: ${actor.email} -> ${target.email} as ${role}`);
  const membershipId = `${tenantId}_${target.uid}`;
  const existing = await getDoc(`tenant_memberships/${membershipId}`, actor.idToken);
  if (existing) {
    console.log(`Membership already exists: ${membershipId}`);
    return membershipId;
  }
  await upsertUserDoc(target, {
    lastSelectedTenantId: tenantId,
  });
  await patchDoc(
    `tenant_memberships/${membershipId}`,
    {
      membershipId,
      tenantId,
      uid: target.uid,
      role,
      ativo: true,
      defaultTenant: false,
      state: 'active',
      ownerId: scope.ownerId,
      gerenteId: scope.gerenteId,
      representanteId: scope.representanteId,
      vendedorId: scope.vendedorId,
      updatedAt: new Date().toISOString(),
    },
    actor.idToken,
  );
  return membershipId;
}

async function acceptInvitation({ invitee, invitationToken, tenantId, role, scope }) {
  console.log(`Accept: ${invitee.email} into ${tenantId} as ${role}`);
  const membershipId = `${tenantId}_${invitee.uid}`;
  await upsertUserDoc(invitee, {
    defaultTenantId: tenantId,
    lastSelectedTenantId: tenantId,
  });
  await patchDoc(
    `tenant_memberships/${membershipId}`,
    {
      membershipId,
      tenantId,
      uid: invitee.uid,
      role,
      ativo: true,
      defaultTenant: false,
      state: 'active',
      ownerId: scope.ownerId,
      gerenteId: scope.gerenteId,
      representanteId: scope.representanteId,
      vendedorId: scope.vendedorId,
      invitationToken,
      updatedAt: new Date().toISOString(),
    },
    invitee.idToken,
  );
  await patchDoc(
    `tenant_invitations/${invitationToken}`,
    {
      token: invitationToken,
      tenantId,
      role,
      status: 'accepted',
      invitedEmail: invitee.email,
      defaultTenant: false,
      acceptedByUid: invitee.uid,
      acceptedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    invitee.idToken,
  );
  return membershipId;
}

async function bootstrapRepWorkspace() {
  console.log('Scenario: rep workspace');
  const owner = await createOrLoginUser(
    scenarios.repWorkspace.owner.email,
    PASSWORD,
    scenarios.repWorkspace.owner.displayName,
  );
  const manager = await createOrLoginUser(
    scenarios.repWorkspace.manager.email,
    PASSWORD,
    scenarios.repWorkspace.manager.displayName,
  );
  const representative = await createOrLoginUser(
    scenarios.repWorkspace.representative.email,
    PASSWORD,
    scenarios.repWorkspace.representative.displayName,
  );
  const seller = await createOrLoginUser(
    scenarios.repWorkspace.seller.email,
    PASSWORD,
    scenarios.repWorkspace.seller.displayName,
  );
  const workspace = await bootstrapSelfServiceWorkspace({
    auth: owner,
    scenario: scenarios.repWorkspace,
  });

  const managerMembershipId = await createManagedMembership({
    actor: owner,
    target: manager,
    tenantId: workspace.tenantId,
    role: 'gerente',
    scope: {
      ownerId: owner.uid,
      gerenteId: manager.uid,
      representanteId: '',
      vendedorId: '',
    },
  });

  const representativeMembershipId = await createManagedMembership({
    actor: manager,
    target: representative,
    tenantId: workspace.tenantId,
    role: 'representante',
    scope: {
      ownerId: owner.uid,
      gerenteId: manager.uid,
      representanteId: representative.uid,
      vendedorId: '',
    },
  });

  const sellerMembershipId = await createManagedMembership({
    actor: representative,
    target: seller,
    tenantId: workspace.tenantId,
    role: 'vendedor',
    scope: {
      ownerId: owner.uid,
      gerenteId: manager.uid,
      representanteId: representative.uid,
      vendedorId: seller.uid,
    },
  });

  return {
    tenantId: workspace.tenantId,
    owner,
    manager,
    representative,
    seller,
    memberships: [managerMembershipId, representativeMembershipId, sellerMembershipId],
  };
}

async function run() {
  console.log('Provisionando cenarios de teste do modelo v2...');

  const sellerSoloUser = await createOrLoginUser(
    scenarios.sellerSolo.email,
    PASSWORD,
    scenarios.sellerSolo.displayName,
  );
  const sellerSoloWorkspace = await bootstrapSelfServiceWorkspace({
    auth: sellerSoloUser,
    scenario: scenarios.sellerSolo,
  });
  console.log(`Seller solo OK: ${sellerSoloWorkspace.tenantId}`);

  const repWorkspace = await bootstrapRepWorkspace();
  console.log(`Rep workspace OK: ${repWorkspace.tenantId}`);

  console.log('\nCenarios provisionados com sucesso.');
  console.log(`Senha padrao: ${PASSWORD}`);
  console.log('\n1) Seller solo');
  console.log(`   email: ${sellerSoloUser.email}`);
  console.log(`   tenantId: ${sellerSoloWorkspace.tenantId}`);
  console.log('\n2) Rep workspace');
  console.log(`   owner: ${repWorkspace.owner.email}`);
  console.log(`   gerente: ${repWorkspace.manager.email}`);
  console.log(`   representante: ${repWorkspace.representative.email}`);
  console.log(`   vendedor: ${repWorkspace.seller.email}`);
  console.log(`   tenantId: ${repWorkspace.tenantId}`);
}

run().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
