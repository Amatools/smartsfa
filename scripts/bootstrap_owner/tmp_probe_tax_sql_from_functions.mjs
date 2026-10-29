import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const workspaceRoot = path.join(__dirname, '..', '..');

const serviceAccountPath = path.join(
  __dirname,
  'smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json',
);
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
initializeApp({ credential: cert(serviceAccount) });

const SANKHYA_DBEXPLORER_ENDPOINT_PATHS = [
  '/gateway/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/gateway/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
];

function tryParseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function normalizeDbExplorerRows(payload) {
  if (!payload || typeof payload !== 'object') return [];
  const root =
    payload.responseBody && typeof payload.responseBody === 'object'
      ? payload.responseBody
      : payload;
  const rawRows = Array.isArray(root.rows) ? root.rows : [];
  if (rawRows.length === 0) return [];
  if (rawRows.every((row) => row && typeof row === 'object' && !Array.isArray(row))) {
    return rawRows;
  }
  const fields = Array.isArray(root.fieldsMetadata) ? root.fieldsMetadata : [];
  if (fields.length === 0) return [];
  return rawRows
    .filter((row) => Array.isArray(row))
    .map((row) => {
      const mapped = {};
      for (let i = 0; i < fields.length; i++) {
        const name = String(fields[i]?.name ?? '').trim();
        if (name) mapped[name] = row[i] ?? null;
      }
      return mapped;
    });
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
        environment: String(tenant.erpIntegration?.environment ?? 'prod').trim().toLowerCase(),
        clientId: String(c.username).trim(),
        clientSecret: String(c.password).trim(),
        xToken: String(c.accessToken).trim(),
      };
    }
  }

  return null;
}

async function authenticate(baseUrl, creds) {
  const formBody = new URLSearchParams({
    client_id: creds.clientId,
    client_secret: creds.clientSecret,
    grant_type: 'client_credentials',
  });
  const res = await fetch(baseUrl + '/authenticate', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-token': creds.xToken },
    body: formBody,
    signal: AbortSignal.timeout(15000),
  });
  const text = await res.text();
  if (res.status !== 200) {
    throw new Error(`auth failed ${res.status}: ${text.slice(0, 500)}`);
  }
  const json = tryParseJson(text);
  const payload = json && typeof json === 'object' ? json : Object.fromEntries(new URLSearchParams(text));
  return String(payload.access_token ?? payload.accessToken ?? payload.token ?? '').trim();
}

async function executeQuery({ apiBaseUrl, bearerToken, xToken, sql }) {
  const variants = [
    { name: 'serviceName_requestBody_sql', payload: { serviceName: 'DbExplorerSP.executeQuery', requestBody: { sql } } },
    { name: 'requestBody_sql', payload: { requestBody: { sql } } },
    { name: 'requestBody_query', payload: { requestBody: { query: sql } } },
  ];

  const failures = [];
  for (const endpointPath of SANKHYA_DBEXPLORER_ENDPOINT_PATHS) {
    for (const variant of variants) {
      const res = await fetch(`${apiBaseUrl}${endpointPath}`, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          Authorization: `Bearer ${bearerToken}`,
          'content-type': 'application/json',
          'x-token': xToken,
        },
        body: JSON.stringify(variant.payload),
        signal: AbortSignal.timeout(30000),
      });
      const text = await res.text();
      const parsed = tryParseJson(text);
      const rows = normalizeDbExplorerRows(parsed);
      if (res.ok) {
        return {
          ok: true,
          endpointPath,
          payloadVariant: variant.name,
          rows,
          status: res.status,
          bodySample: text.slice(0, 500),
          parsedKeys: parsed && typeof parsed === 'object' ? Object.keys(parsed) : [],
        };
      }
      failures.push({ endpointPath, payloadVariant: variant.name, status: res.status, bodySample: text.slice(0, 300) });
    }
  }

  return { ok: false, failures };
}

function extractTaxSql() {
  const indexPath = path.join(workspaceRoot, 'functions', 'index.js');
  const content = fs.readFileSync(indexPath, 'utf8');
  const match = content.match(/function\s+buildSankhyaTaxRulesSql\(\)\s*\{\s*return\s*`([\s\S]*?)`\.trim\(\);\s*\}/);
  if (!match) {
    throw new Error('Nao foi possivel extrair SQL de buildSankhyaTaxRulesSql().');
  }
  return match[1].trim();
}

async function run() {
  const sql = extractTaxSql();
  const creds = await resolveCreds();
  if (!creds) throw new Error('Credenciais ERP nao encontradas.');

  const baseUrl = creds.environment === 'prod'
    ? 'https://api.sankhya.com.br'
    : 'https://api.sandbox.sankhya.com.br';

  const token = await authenticate(baseUrl, creds);
  if (!token) throw new Error('Bearer token vazio.');

  const result = await executeQuery({
    apiBaseUrl: baseUrl,
    bearerToken: token,
    xToken: creds.xToken,
    sql,
  });

  console.log(JSON.stringify({
    ok: result.ok,
    endpointPath: result.endpointPath ?? null,
    payloadVariant: result.payloadVariant ?? null,
    status: result.status ?? null,
    rowCount: result.rows?.length ?? 0,
    parsedKeys: result.parsedKeys ?? [],
    firstRow: result.rows?.[0] ?? null,
    bodySample: result.bodySample ?? null,
    failures: result.failures ?? null,
  }, null, 2));
}

run().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exitCode = 1;
});
