import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const serviceAccountPath = path.join(
  __dirname,
  'smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json',
);
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
initializeApp({ credential: cert(serviceAccount) });

function parseArgs() {
  const args = {};
  for (const item of process.argv.slice(2)) {
    if (!item.startsWith('--')) {
      continue;
    }
    const withoutPrefix = item.slice(2);
    const eqIndex = withoutPrefix.indexOf('=');
    if (eqIndex < 0) {
      args[withoutPrefix] = 'true';
      continue;
    }
    const key = withoutPrefix.slice(0, eqIndex);
    const value = withoutPrefix.slice(eqIndex + 1);
    args[key] = value;
  }
  return args;
}

function parsePayload(text) {
  if (!text || !text.trim()) {
    return { parsed: null, isJson: false };
  }

  try {
    return { parsed: JSON.parse(text), isJson: true };
  } catch {
    return { parsed: null, isJson: false };
  }
}

function saveOutputFile(output) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const outputDir = path.join(__dirname, '..', '..', 'docs', 'sankhya-api', 'examples');
  const outputPath = path.join(outputDir, `sankhya_vendedores_probe_${stamp}.json`);
  fs.mkdirSync(outputDir, { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
  return outputPath;
}

function toList(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.vendedores)) return payload.vendedores;
  if (Array.isArray(payload?.data)) return payload.data;
  if (Array.isArray(payload?.items)) return payload.items;
  if (Array.isArray(payload?.itens)) return payload.itens;
  return [];
}

function readText(value) {
  if (value == null) {
    return '';
  }
  return String(value).trim();
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

async function fetchWithBearer(baseUrl, token, endpointPath) {
  const response = await fetch(baseUrl + endpointPath, {
    method: 'GET',
    headers: {
      authorization: `Bearer ${token}`,
      accept: 'application/json',
    },
  });

  const bodyText = await response.text();
  const { parsed, isJson } = parsePayload(bodyText);

  return {
    status: response.status,
    bodyText,
    bodyParsed: parsed,
    isJson,
  };
}

const args = parseArgs();
const pageRaw = Number.parseInt(String(args.page ?? '0'), 10);
const page = Number.isFinite(pageRaw) && pageRaw >= 0 ? pageRaw : 0;

const creds = await resolveCreds();
if (!creds) {
  const output = {
    marker: 'VENDEDORES_PROBE',
    ok: false,
    error: 'no_complete_credentials_found',
  };
  const outputPath = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile: outputPath }, null, 2));
  process.exit(0);
}

const baseUrl =
  creds.env === 'homolog'
    ? 'https://api.sandbox.sankhya.com.br'
    : 'https://api.sankhya.com.br';

const authBody = new URLSearchParams({
  client_id: creds.username,
  client_secret: creds.password,
  grant_type: 'client_credentials',
});

const authResponse = await fetch(baseUrl + '/authenticate', {
  method: 'POST',
  headers: {
    'content-type': 'application/x-www-form-urlencoded',
    'x-token': creds.xToken,
  },
  body: authBody,
});

const authText = await authResponse.text();
let authPayload = {};
try {
  authPayload = JSON.parse(authText);
} catch {
  authPayload = Object.fromEntries(new URLSearchParams(authText));
}

const accessToken = String(authPayload.access_token ?? '').trim();
if (!accessToken) {
  const output = {
    marker: 'VENDEDORES_PROBE',
    ok: false,
    tenantId: creds.tenantId,
    environment: creds.env,
    authStatus: authResponse.status,
    bearerReceived: false,
    authError: authPayload.error ?? null,
    authErrorDescription: authPayload.error_description ?? null,
  };
  const outputPath = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile: outputPath }, null, 2));
  process.exit(0);
}

const endpointPath = `/v1/vendedores?page=${page}`;
const target = await fetchWithBearer(baseUrl, accessToken, endpointPath);
const vendedores = toList(target.bodyParsed);

const hierarchyPreview = vendedores.slice(0, 10).map((item) => ({
  codigoVendedor: item?.codigoVendedor ?? null,
  nome: readText(item?.nome),
  ativo: item?.ativo ?? null,
  tipo: item?.tipo ?? null,
  codigoGerente: item?.codigoGerente ?? null,
  codigoParceiro: item?.codigoParceiro ?? null,
}));

const output = {
  marker: 'VENDEDORES_PROBE',
  ok: target.status >= 200 && target.status < 300,
  executedAt: new Date().toISOString(),
  tenantId: creds.tenantId,
  environment: creds.env,
  baseUrl,
  authStatus: authResponse.status,
  bearerReceived: true,
  request: {
    method: 'GET',
    path: endpointPath,
  },
  response: {
    status: target.status,
    isJson: target.isJson,
    body: target.bodyParsed ?? { raw: target.bodyText },
  },
  summary: {
    page,
    totalItemsInPayload: vendedores.length,
    hierarchyPreview,
  },
};

const outputPath = saveOutputFile(output);

console.log(
  JSON.stringify(
    {
      marker: 'VENDEDORES_PROBE',
      ok: output.ok,
      tenantId: creds.tenantId,
      environment: creds.env,
      requestPath: endpointPath,
      status: target.status,
      savedFile: outputPath,
      totalItemsInPayload: vendedores.length,
      hierarchyPreview,
    },
    null,
    2,
  ),
);
