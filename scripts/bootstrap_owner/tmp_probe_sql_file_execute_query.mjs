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
    if (!item.startsWith('--')) continue;
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
  if (!text || !text.trim()) return { parsed: null, isJson: false };
  try {
    return { parsed: JSON.parse(text), isJson: true };
  } catch {
    return { parsed: null, isJson: false };
  }
}

function extractRows(parsed) {
  if (!parsed || typeof parsed !== 'object') return [];
  if (Array.isArray(parsed.rows)) return parsed.rows;
  if (Array.isArray(parsed?.responseBody?.rows)) return parsed.responseBody.rows;
  return [];
}

function extractFields(parsed) {
  if (!parsed || typeof parsed !== 'object') return [];
  if (Array.isArray(parsed?.responseBody?.fieldsMetadata)) {
    return parsed.responseBody.fieldsMetadata.map((f) => ({
      name: f?.name ?? null,
      order: f?.order ?? null,
      userType: f?.userType ?? null,
      precision: f?.precision ?? null,
    }));
  }
  if (Array.isArray(parsed?.fieldsMetadata)) {
    return parsed.fieldsMetadata.map((f) => ({
      name: f?.name ?? null,
      order: f?.order ?? null,
      userType: f?.userType ?? null,
      precision: f?.precision ?? null,
    }));
  }
  return [];
}

function uniqueNonEmpty(values) {
  const list = [];
  const seen = new Set();
  for (const raw of values) {
    const value = String(raw ?? '').trim();
    if (!value || seen.has(value)) continue;
    seen.add(value);
    list.push(value);
  }
  return list;
}

function normalizeBaseUrl(raw) {
  const value = String(raw ?? '').trim();
  if (!value) return '';
  if (/^https?:\/\//i.test(value)) return value.replace(/\/+$/g, '');
  return `https://${value}`.replace(/\/+$/g, '');
}

function buildBaseUrlCandidates(creds) {
  const envBase =
    creds.env === 'homolog'
      ? 'https://api.sandbox.sankhya.com.br'
      : 'https://api.sankhya.com.br';
  const configured = normalizeBaseUrl(creds.apiBaseUrl);
  return uniqueNonEmpty([configured, envBase]);
}

function buildEndpointCandidates() {
  return [
    '/gateway/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
    '/gateway/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
    '/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
    '/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  ];
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

  return {
    status: authResponse.status,
    accessToken: String(authPayload.access_token ?? '').trim(),
    payload: authPayload,
  };
}

async function executeQuery({ baseUrl, endpointPath, accessToken, xToken, sql }) {
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

  return {
    status: response.status,
    ok: response.ok,
    responseIsJson: isJson,
    fields: extractFields(parsed),
    rows: extractRows(parsed),
    responseBody: parsed ?? { raw: text },
  };
}

function saveOutputFile(output, suffix = 'sql_file_probe') {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const outputDir = path.join(__dirname, '..', '..', 'docs', 'sankhya-api', 'examples');
  const outputPath = path.join(outputDir, `sankhya_${suffix}_${stamp}.json`);
  fs.mkdirSync(outputDir, { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
  return outputPath;
}

const args = parseArgs();
const sqlFileArg = String(args.sqlFile ?? '').trim();
if (!sqlFileArg) {
  console.error('Use --sqlFile=docs/path/file.sql');
  process.exit(1);
}

const sqlPath = path.isAbsolute(sqlFileArg)
  ? sqlFileArg
  : path.join(__dirname, '..', '..', sqlFileArg);
const sql = fs.readFileSync(sqlPath, 'utf8').trim();

const creds = await resolveCreds();
if (!creds) {
  const output = { marker: 'SQL_FILE_PROBE', ok: false, error: 'no_complete_credentials_found' };
  const savedFile = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile }, null, 2));
  process.exit(0);
}

const baseUrlCandidates = buildBaseUrlCandidates(creds);
const auth = await authenticate(baseUrlCandidates[0], creds);
if (!auth.accessToken) {
  const output = {
    marker: 'SQL_FILE_PROBE',
    ok: false,
    tenantId: creds.tenantId,
    environment: creds.env,
    authStatus: auth.status,
    authError: auth.payload?.error ?? null,
    authErrorDescription: auth.payload?.error_description ?? null,
  };
  const savedFile = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile }, null, 2));
  process.exit(0);
}

const endpointCandidates = buildEndpointCandidates();
let winner = null;
for (const baseUrl of baseUrlCandidates) {
  for (const endpointPath of endpointCandidates) {
    const smoke = await executeQuery({
      baseUrl,
      endpointPath,
      accessToken: auth.accessToken,
      xToken: creds.xToken,
      sql: 'SELECT 1 AS OK FROM DUAL',
    });
    if (smoke.ok) {
      winner = { baseUrl, endpointPath, smoke };
      break;
    }
  }
  if (winner) break;
}

if (!winner) {
  const output = {
    marker: 'SQL_FILE_PROBE',
    ok: false,
    tenantId: creds.tenantId,
    environment: creds.env,
    error: 'no_working_execute_query_endpoint',
  };
  const savedFile = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile }, null, 2));
  process.exit(0);
}

const result = await executeQuery({
  baseUrl: winner.baseUrl,
  endpointPath: winner.endpointPath,
  accessToken: auth.accessToken,
  xToken: creds.xToken,
  sql,
});

const output = {
  marker: 'SQL_FILE_PROBE',
  ok: result.ok,
  tenantId: creds.tenantId,
  environment: creds.env,
  sqlFile: sqlPath,
  baseUrl: winner.baseUrl,
  endpointPath: winner.endpointPath,
  status: result.status,
  responseIsJson: result.responseIsJson,
  rowCount: result.rows.length,
  fields: result.fields,
  rows: result.rows,
  responseBody: result.responseBody,
};

const savedFile = saveOutputFile(output);
console.log(JSON.stringify({ ...output, savedFile }, null, 2));
