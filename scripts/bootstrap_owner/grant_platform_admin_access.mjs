import process from 'node:process';

const API_KEY =
  process.env.FIREBASE_WEB_API_KEY ?? 'AIzaSyDFXV_T5_WfN2xrl-qi814i_AwReyGjXKs';
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID ?? 'smart-sfa';
const ADMIN_EMAIL = (process.env.ADMIN_EMAIL ?? '').trim();
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? '';
const TARGET_EMAIL = (process.env.TARGET_EMAIL ?? '').trim();
const TARGET_PLATFORM_ROLE = (
  process.env.TARGET_PLATFORM_ROLE ?? 'platform_admin'
)
  .trim()
  .toLowerCase();
const MAINTAINER_CONSOLE_ENABLED = parseBool(
  process.env.MAINTAINER_CONSOLE_ENABLED,
  true,
);
const MAINTAINER_MFA_REQUIRED = parseBool(
  process.env.MAINTAINER_MFA_REQUIRED,
  false,
);
const MAINTAINER_MFA_VERIFIED = parseBool(
  process.env.MAINTAINER_MFA_VERIFIED,
  false,
);

function parseBool(rawValue, defaultValue) {
  if (rawValue == null || rawValue === '') {
    return defaultValue;
  }

  const normalized = String(rawValue).trim().toLowerCase();
  if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) {
    return true;
  }
  if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) {
    return false;
  }
  return defaultValue;
}

function requireEnv(name, value) {
  if (!value || !String(value).trim()) {
    throw new Error(`Variavel obrigatoria ausente: ${name}`);
  }
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
    if (Number.isInteger(value)) {
      return { integerValue: String(value) };
    }
    return { doubleValue: value };
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

function fromFsValue(value) {
  if (!value || typeof value !== 'object') {
    return null;
  }
  if ('stringValue' in value) {
    return value.stringValue;
  }
  if ('booleanValue' in value) {
    return value.booleanValue;
  }
  if ('integerValue' in value) {
    return Number(value.integerValue);
  }
  if ('doubleValue' in value) {
    return Number(value.doubleValue);
  }
  if ('nullValue' in value) {
    return null;
  }
  if ('arrayValue' in value) {
    const values = value.arrayValue?.values ?? [];
    return values.map((item) => fromFsValue(item));
  }
  if ('mapValue' in value) {
    const fields = value.mapValue?.fields ?? {};
    return fromFsFields(fields);
  }
  if ('timestampValue' in value) {
    return value.timestampValue;
  }
  return null;
}

function fromFsFields(fields) {
  const output = {};
  for (const [key, fsValue] of Object.entries(fields ?? {})) {
    output[key] = fromFsValue(fsValue);
  }
  return output;
}

function documentPathFromName(name) {
  const marker = '/documents/';
  const index = name.indexOf(marker);
  if (index < 0) {
    return name;
  }
  return name.slice(index + marker.length);
}

function uidFromDocName(name) {
  const path = documentPathFromName(name);
  return path.split('/').pop() ?? '';
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
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`;
  return postJson(url, {
    email,
    password,
    returnSecureToken: true,
  });
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

async function findUserDocByEmail(email, token) {
  const attempts = [email, email.toLowerCase()];

  for (const candidate of attempts) {
    const rows = await runQuery(
      {
        structuredQuery: {
          from: [{ collectionId: 'usuarios' }],
          where: {
            fieldFilter: {
              field: { fieldPath: 'email' },
              op: 'EQUAL',
              value: { stringValue: candidate },
            },
          },
          limit: 2,
        },
      },
      token,
    );

    if (rows.length > 0) {
      return rows[0].document;
    }
  }

  return null;
}

async function listActiveMemberships(uid, token) {
  const rows = await runQuery(
    {
      structuredQuery: {
        from: [{ collectionId: 'tenant_memberships' }],
        where: {
          compositeFilter: {
            op: 'AND',
            filters: [
              {
                fieldFilter: {
                  field: { fieldPath: 'uid' },
                  op: 'EQUAL',
                  value: { stringValue: uid },
                },
              },
              {
                fieldFilter: {
                  field: { fieldPath: 'ativo' },
                  op: 'EQUAL',
                  value: { booleanValue: true },
                },
              },
            ],
          },
        },
      },
    },
    token,
  );

  return rows;
}

async function run() {
  requireEnv('ADMIN_EMAIL', ADMIN_EMAIL);
  requireEnv('ADMIN_PASSWORD', ADMIN_PASSWORD);
  requireEnv('TARGET_EMAIL', TARGET_EMAIL);

  if (!['platform_admin', 'platform_observer', 'platform_operator', 'none'].includes(TARGET_PLATFORM_ROLE)) {
    throw new Error(
      'TARGET_PLATFORM_ROLE invalido. Use: platform_admin, platform_observer, platform_operator ou none.',
    );
  }

  console.log(`Autenticando conta administradora: ${ADMIN_EMAIL}`);
  const auth = await signIn(ADMIN_EMAIL, ADMIN_PASSWORD);
  const token = auth.idToken;

  console.log(`Localizando usuario alvo por email: ${TARGET_EMAIL}`);
  const targetDoc = await findUserDocByEmail(TARGET_EMAIL, token);
  if (!targetDoc) {
    throw new Error(
      'Usuario alvo nao encontrado em usuarios/. Faça login uma vez com este email no app para criar o documento e tente novamente.',
    );
  }

  const uid = uidFromDocName(targetDoc.name);
  const current = fromFsFields(targetDoc.fields);
  const now = new Date().toISOString();

  const merged = {
    ...current,
    uid,
    email: (current.email ?? TARGET_EMAIL).toString(),
    displayName:
      (current.displayName ?? current.name ?? TARGET_EMAIL.split('@')[0]).toString(),
    ativoGlobal: current.ativoGlobal === false ? false : true,
    platformRole: TARGET_PLATFORM_ROLE,
    maintainerConsoleEnabled: MAINTAINER_CONSOLE_ENABLED,
    maintainerMfaRequired: MAINTAINER_MFA_REQUIRED,
    maintainerMfaVerified: MAINTAINER_MFA_VERIFIED,
    maintainerAccessUpdatedAt: now,
    updatedAt: now,
  };

  await patchDoc(`usuarios/${uid}`, merged, token);

  const memberships = await listActiveMemberships(uid, token);
  console.log('Promocao concluida com sucesso.');
  console.log(`uid: ${uid}`);
  console.log(`email: ${merged.email}`);
  console.log(`platformRole: ${TARGET_PLATFORM_ROLE}`);
  console.log(`maintainerConsoleEnabled: ${MAINTAINER_CONSOLE_ENABLED}`);
  console.log(`maintainerMfaRequired: ${MAINTAINER_MFA_REQUIRED}`);
  console.log(`maintainerMfaVerified: ${MAINTAINER_MFA_VERIFIED}`);
  console.log(`activeMemberships: ${memberships.length}`);

  if (memberships.length === 0) {
    console.log(
      'Aviso: sem membership ativo. Esta conta nao conseguira entrar no portal ate ter um workspace vinculado.',
    );
  }
}

run().catch((error) => {
  console.error('Falha ao promover conta de plataforma:', error.message);
  process.exitCode = 1;
});
