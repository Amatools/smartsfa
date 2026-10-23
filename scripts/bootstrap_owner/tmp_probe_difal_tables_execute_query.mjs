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

function uniqueNonEmpty(values) {
  const list = [];
  const seen = new Set();
  for (const raw of values) {
    const value = String(raw ?? '').trim();
    if (!value || seen.has(value)) {
      continue;
    }
    seen.add(value);
    list.push(value);
  }
  return list;
}

function normalizeBaseUrl(raw) {
  const value = String(raw ?? '').trim();
  if (!value) {
    return '';
  }
  if (/^https?:\/\//i.test(value)) {
    return value.replace(/\/+$/g, '');
  }
  return `https://${value}`.replace(/\/+$/g, '');
}

function buildBaseUrlCandidates(creds) {
  const envBase =
    creds.env === 'homolog'
      ? 'https://api.sandbox.sankhya.com.br'
      : 'https://api.sankhya.com.br';

  const configured = normalizeBaseUrl(creds.apiBaseUrl);
  const candidates = [configured, envBase];
  if (configured) {
    try {
      const url = new URL(configured);
      candidates.push(`${url.protocol}//${url.host}`);
    } catch {
      // noop
    }
  }
  return uniqueNonEmpty(candidates);
}

function buildEndpointCandidates() {
  return [
    '/gateway/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
    '/gateway/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
    '/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
    '/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  ];
}

function extractRows(parsed) {
  if (!parsed || typeof parsed !== 'object') {
    return [];
  }
  if (Array.isArray(parsed.rows)) return parsed.rows;
  if (Array.isArray(parsed?.responseBody?.rows)) return parsed.responseBody.rows;
  if (Array.isArray(parsed?.responseBody?.result)) return parsed.responseBody.result;
  return [];
}

function extractFields(parsed) {
  if (!parsed || typeof parsed !== 'object') {
    return [];
  }
  if (Array.isArray(parsed?.responseBody?.fieldsMetadata)) {
    return parsed.responseBody.fieldsMetadata.map((f) => f?.name).filter(Boolean);
  }
  if (Array.isArray(parsed?.fieldsMetadata)) {
    return parsed.fieldsMetadata.map((f) => f?.name).filter(Boolean);
  }
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
        apiBaseUrl: String(c.apiBaseUrl ?? '').trim(),
        username: String(c.username).trim(),
        password: String(c.password).trim(),
        xToken: String(c.accessToken).trim(),
      };
    }
  }

  return null;
}

async function authenticate(baseUrl, creds) {
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
  return {
    status: authResponse.status,
    accessToken,
    payload: authPayload,
  };
}

async function runExecuteQuery({
  baseUrl,
  endpointPath,
  accessToken,
  xToken,
  sql,
}) {
  const payload = {
    serviceName: 'DbExplorerSP.executeQuery',
    requestBody: { sql },
  };

  const response = await fetch(baseUrl + endpointPath, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      accept: 'application/json',
      'content-type': 'application/json',
      'x-token': xToken,
    },
    body: JSON.stringify(payload),
  });

  const text = await response.text();
  const { parsed, isJson } = parsePayload(text);
  const rows = extractRows(parsed);
  const fields = extractFields(parsed);

  return {
    status: response.status,
    ok: response.ok,
    responseIsJson: isJson,
    rowCount: rows.length,
    fields,
    responseBody: parsed ?? { raw: text },
  };
}

function saveOutputFile(output) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const outputDir = path.join(__dirname, '..', '..', 'docs', 'sankhya-api', 'examples');
  const outputPath = path.join(outputDir, `sankhya_difal_table_probe_${stamp}.json`);
  fs.mkdirSync(outputDir, { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
  return outputPath;
}

const queries = {
  tgfcusite: `
SELECT
  COUNT(*) AS TOTAL_LINHAS,
  SUM(CASE WHEN NVL(CUS.CODPROD, 0) > 0 THEN 1 ELSE 0 END) AS LINHAS_COM_PRODUTO
FROM TGFCUSITE CUS
`,
  tgfdin_difal: `
SELECT
  COUNT(*) AS TOTAL_LINHAS,
  SUM(CASE WHEN NVL(DIN.BASEDIFAL, 0) <> 0 THEN 1 ELSE 0 END) AS LINHAS_BASEDIFAL,
  SUM(CASE WHEN NVL(DIN.VLRDIFALDEST, 0) <> 0 THEN 1 ELSE 0 END) AS LINHAS_VLRDIFALDEST,
  SUM(CASE WHEN NVL(DIN.VLRDIFALREM, 0) <> 0 THEN 1 ELSE 0 END) AS LINHAS_VLRDIFALREM,
  SUM(CASE WHEN NVL(DIN.PERCPARTDIFAL, 0) <> 0 THEN 1 ELSE 0 END) AS LINHAS_PERCPARTDIFAL,
  SUM(CASE WHEN DIN.TIPCALCDIFAL IS NOT NULL THEN 1 ELSE 0 END) AS LINHAS_TIPCALCDIFAL
FROM TGFDIN DIN
`,
  tgfdin_samples: `
SELECT
  DIN.NUNOTA,
  DIN.SEQUENCIA,
  DIN.CODIMP,
  DIN.CODCST,
  DIN.BASEDIFAL,
  DIN.VLRDIFALDEST,
  DIN.VLRDIFALREM,
  DIN.PERCPARTDIFAL,
  DIN.TIPCALCDIFAL,
  DIN.PERCFCP,
  DIN.VLRFCP
FROM TGFDIN DIN
WHERE NVL(DIN.BASEDIFAL, 0) <> 0
   OR NVL(DIN.VLRDIFALDEST, 0) <> 0
   OR NVL(DIN.VLRDIFALREM, 0) <> 0
ORDER BY DIN.NUNOTA DESC, DIN.SEQUENCIA DESC
FETCH FIRST 20 ROWS ONLY
`,
};

const creds = await resolveCreds();
if (!creds) {
  const output = {
    marker: 'DIFAL_TABLE_PROBE',
    ok: false,
    error: 'no_complete_credentials_found',
  };
  const outputPath = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile: outputPath }, null, 2));
  process.exit(0);
}

const baseUrlCandidates = buildBaseUrlCandidates(creds);
const auth = await authenticate(baseUrlCandidates[0], creds);
if (!auth.accessToken) {
  const output = {
    marker: 'DIFAL_TABLE_PROBE',
    ok: false,
    tenantId: creds.tenantId,
    environment: creds.env,
    authStatus: auth.status,
    authError: auth.payload?.error ?? null,
    authErrorDescription: auth.payload?.error_description ?? null,
  };
  const outputPath = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile: outputPath }, null, 2));
  process.exit(0);
}

const endpointCandidates = buildEndpointCandidates();
let winningBase = null;
let winningEndpoint = null;
let smoke = null;

for (const base of baseUrlCandidates) {
  for (const endpoint of endpointCandidates) {
    const result = await runExecuteQuery({
      baseUrl: base,
      endpointPath: endpoint,
      accessToken: auth.accessToken,
      xToken: creds.xToken,
      sql: 'SELECT 1 AS OK FROM DUAL',
    });

    if (result.ok) {
      winningBase = base;
      winningEndpoint = endpoint;
      smoke = result;
      break;
    }
  }
  if (winningBase) {
    break;
  }
}

if (!winningBase || !winningEndpoint) {
  const output = {
    marker: 'DIFAL_TABLE_PROBE',
    ok: false,
    tenantId: creds.tenantId,
    environment: creds.env,
    error: 'no_working_endpoint_for_execute_query',
  };
  const outputPath = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile: outputPath }, null, 2));
  process.exit(0);
}

const results = {};
for (const [name, sql] of Object.entries(queries)) {
  results[name] = await runExecuteQuery({
    baseUrl: winningBase,
    endpointPath: winningEndpoint,
    accessToken: auth.accessToken,
    xToken: creds.xToken,
    sql,
  });
}

const output = {
  marker: 'DIFAL_TABLE_PROBE',
  ok: true,
  tenantId: creds.tenantId,
  environment: creds.env,
  baseUrl: winningBase,
  endpointPath: winningEndpoint,
  smoke,
  results,
};

const outputPath = saveOutputFile(output);
console.log(JSON.stringify({ ...output, savedFile: outputPath }, null, 2));
