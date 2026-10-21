import fs from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const sa = JSON.parse(
  fs.readFileSync('./smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json', 'utf8'),
);
initializeApp({ credential: cert(sa) });

function toList(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.data)) return payload.data;
  if (Array.isArray(payload?.items)) return payload.items;
  if (Array.isArray(payload?.itens)) return payload.itens;
  return [];
}

async function resolveCreds() {
  const user = await getAuth().getUserByEmail('enterprise@smartsfa.com.br');
  const memberships = await getFirestore()
    .collection('tenant_memberships')
    .where('uid', '==', user.uid)
    .get();

  for (const membership of memberships.docs) {
    const tenantId = membership.data().tenantId;
    const tenant = (
      await getFirestore().collection('tenants').doc(tenantId).get()
    ).data() ?? {};
    const c = tenant.erpIntegration?.credentials ?? {};
    if (c.username && c.password && c.accessToken) {
      return {
        tenantId,
        env: String(tenant.erpIntegration?.environment ?? 'prod')
          .trim()
          .toLowerCase(),
        username: String(c.username).trim(),
        password: String(c.password).trim(),
        xToken: String(c.accessToken).trim(),
      };
    }
  }

  return null;
}

const creds = await resolveCreds();
if (!creds) {
  console.log(
    JSON.stringify({
      marker: 'TIPOS_OPERACAO_GRANULAR',
      error: 'no_complete_credentials_found',
    }),
  );
  process.exit(0);
}

const base =
  creds.env === 'homolog'
    ? 'https://api.sandbox.sankhya.com.br'
    : 'https://api.sankhya.com.br';

const authBody = new URLSearchParams({
  client_id: creds.username,
  client_secret: creds.password,
  grant_type: 'client_credentials',
});

const authResp = await fetch(base + '/authenticate', {
  method: 'POST',
  headers: {
    'content-type': 'application/x-www-form-urlencoded',
    'x-token': creds.xToken,
  },
  body: authBody,
});

const authText = await authResp.text();
let authPayload = {};
try {
  authPayload = JSON.parse(authText);
} catch {
  authPayload = Object.fromEntries(new URLSearchParams(authText));
}

const token = String(authPayload.access_token ?? '');
if (!token) {
  console.log(
    JSON.stringify({
      marker: 'TIPOS_OPERACAO_GRANULAR',
      tenantId: creds.tenantId,
      environment: creds.env,
      authStatus: authResp.status,
      bearerReceived: false,
      authError: authPayload.error ?? null,
      authErrorDescription: authPayload.error_description ?? null,
    }),
  );
  process.exit(0);
}

const tests = [{ tipoMovimento: null, path: '/v1/tipos-operacao?page=1' }];
for (let i = 1; i <= 23; i += 1) {
  tests.push({
    tipoMovimento: i,
    path: `/v1/tipos-operacao?tipoMovimento=${i}&page=1`,
  });
}

const results = [];
for (const test of tests) {
  const resp = await fetch(base + test.path, {
    headers: {
      authorization: `Bearer ${token}`,
      accept: 'application/json',
    },
  });
  const text = await resp.text();
  let payload = {};
  try {
    payload = JSON.parse(text);
  } catch {
    payload = { raw: text };
  }

  const list = toList(payload);
  results.push({
    tipoMovimento: test.tipoMovimento,
    status: resp.status,
    count: list.length,
    errorCode: payload?.error?.code ?? null,
    errorDetails: payload?.error?.details ?? null,
  });
}

console.log(
  JSON.stringify({
    marker: 'TIPOS_OPERACAO_GRANULAR',
    tenantId: creds.tenantId,
    environment: creds.env,
    authStatus: authResp.status,
    bearerReceived: true,
    results,
  }),
);
