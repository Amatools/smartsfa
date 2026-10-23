import fs from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const sa = JSON.parse(fs.readFileSync('./smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json', 'utf8'));
initializeApp({ credential: cert(sa) });

const user = await getAuth().getUserByEmail('enterprise@smartsfa.com.br');
const memberships = await getFirestore().collection('tenant_memberships').where('uid', '==', user.uid).get();

let creds = null;
for (const membership of memberships.docs) {
  const tenant = (await getFirestore().collection('tenants').doc(membership.data().tenantId).get()).data() ?? {};
  const c = tenant.erpIntegration?.credentials ?? {};
  if (c.username && c.password && c.accessToken) {
    creds = {
      tenantId: membership.data().tenantId,
      env: String(tenant.erpIntegration?.environment ?? 'prod').trim().toLowerCase(),
      username: String(c.username).trim(),
      password: String(c.password).trim(),
      xToken: String(c.accessToken).trim(),
    };
    break;
  }
}

if (!creds) {
  console.log(JSON.stringify({ marker: 'NEGOCIACAO_SIMPLE', error: 'no_complete_credentials_found' }));
  process.exit(0);
}

const base = creds.env === 'homolog' ? 'https://api.sandbox.sankhya.com.br' : 'https://api.sankhya.com.br';
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
try { authPayload = JSON.parse(authText); } catch { authPayload = Object.fromEntries(new URLSearchParams(authText)); }
const token = String(authPayload.access_token ?? '');
if (!token) {
  console.log(JSON.stringify({ marker: 'NEGOCIACAO_SIMPLE', tenantId: creds.tenantId, authStatus: authResp.status, bearerReceived: false, authError: authPayload.error ?? null, authErrorDescription: authPayload.error_description ?? null }));
  process.exit(0);
}

const paths = [
  '/v1/tipos-negociacao?page=1',
  '/v1/vendas/tipos-negociacao?page=1',
  '/v1/tipos-operacao?tipoMovimento=19&page=1',
];

const out = [];
for (const path of paths) {
  const resp = await fetch(base + path, { headers: { authorization: `Bearer ${token}`, accept: 'application/json' } });
  const text = await resp.text();
  let payload = {};
  try { payload = JSON.parse(text); } catch { payload = { raw: text }; }
  const list = Array.isArray(payload)
    ? payload
    : Array.isArray(payload.data)
      ? payload.data
      : Array.isArray(payload.items)
        ? payload.items
        : Array.isArray(payload.itens)
          ? payload.itens
          : [];
  out.push({ path, status: resp.status, count: list.length, errorCode: payload?.error?.code ?? null, errorDetails: payload?.error?.details ?? null });
}

console.log(JSON.stringify({ marker: 'NEGOCIACAO_SIMPLE', tenantId: creds.tenantId, environment: creds.env, authStatus: authResp.status, bearerReceived: true, results: out }));
