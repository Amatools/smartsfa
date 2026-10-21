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
  const outputPath = path.join(outputDir, `sankhya_tributacao_execute_query_${stamp}.json`);
  fs.mkdirSync(outputDir, { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
  return outputPath;
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

function readSqlFile(sqlFilePath) {
  const absolute = path.isAbsolute(sqlFilePath)
    ? sqlFilePath
    : path.join(__dirname, '..', '..', sqlFilePath);
  const sql = fs.readFileSync(absolute, 'utf8');
  return { sql, absolute };
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

function buildExecuteQueryPayload(sql) {
  // Observacao importante:
  // A estrutura exata pode variar conforme a configuracao/versao do ambiente Sankhya.
  // Este payload segue um padrao comum de chamada do serviceName DbExplorerSP.executeQuery.
  return {
    serviceName: 'DbExplorerSP.executeQuery',
    requestBody: {
      sql,
    },
  };
}

function buildPayloadVariants(sql) {
  return [
    {
      variant: 'body_serviceName_requestBody_sql',
      payload: {
        serviceName: 'DbExplorerSP.executeQuery',
        requestBody: { sql },
      },
    },
    {
      variant: 'body_requestBody_sql',
      payload: {
        requestBody: { sql },
      },
    },
    {
      variant: 'body_requestBody_query',
      payload: {
        requestBody: {
          query: sql,
        },
      },
    },
    {
      variant: 'body_only_sql',
      payload: {
        sql,
      },
    },
  ];
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

  // When apiBaseUrl points to a full path, also try host root.
  if (configured) {
    try {
      const url = new URL(configured);
      candidates.push(`${url.protocol}//${url.host}`);
    } catch {
      // Keep only normalized candidate.
    }
  }

  return uniqueNonEmpty(candidates);
}

function buildEndpointCandidates() {
  return [
    '/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
    '/mge/service.sbr?serviceName=DbExplorerSP.executeQuery&outputType=json',
    '/gateway/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
    '/gateway/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
    '/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  ];
}

async function callExecuteQuery({
  baseUrl,
  endpointPath,
  accessToken,
  xToken,
  payloadVariant,
}) {
  const response = await fetch(baseUrl + endpointPath, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      accept: 'application/json',
      'content-type': 'application/json',
      'x-token': xToken,
    },
    body: JSON.stringify(payloadVariant.payload),
  });

  const bodyText = await response.text();
  const { parsed, isJson } = parsePayload(bodyText);
  const rows = extractRows(parsed);

  return {
    ok: response.ok,
    status: response.status,
    responseIsJson: isJson,
    rowCountDetected: rows.length,
    responseBody: parsed ?? { raw: bodyText },
    payloadVariant: payloadVariant.variant,
    payload: payloadVariant.payload,
  };
}

function extractRows(parsed) {
  if (!parsed || typeof parsed !== 'object') {
    return [];
  }

  if (Array.isArray(parsed.rows)) {
    return parsed.rows;
  }

  if (Array.isArray(parsed?.responseBody?.rows)) {
    return parsed.responseBody.rows;
  }

  if (Array.isArray(parsed?.responseBody?.result)) {
    return parsed.responseBody.result;
  }

  if (Array.isArray(parsed?.responseBody?.entities)) {
    return parsed.responseBody.entities;
  }

  return [];
}

const args = parseArgs();
const sqlFileArg = String(
  args.sqlFile ?? 'docs/sankhya-api/examples/tributacao_query_template.sql',
).trim();

const creds = await resolveCreds();
if (!creds) {
  const output = {
    marker: 'TRIBUTACAO_EXECUTE_QUERY_PROBE',
    ok: false,
    error: 'no_complete_credentials_found',
  };
  const outputPath = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile: outputPath }, null, 2));
  process.exit(0);
}

const baseUrlCandidates = buildBaseUrlCandidates(creds);
const baseUrl = baseUrlCandidates[0];

const auth = await authenticate(baseUrl, creds);
if (!auth.accessToken) {
  const output = {
    marker: 'TRIBUTACAO_EXECUTE_QUERY_PROBE',
    ok: false,
    tenantId: creds.tenantId,
    environment: creds.env,
    authStatus: auth.status,
    bearerReceived: false,
    authError: auth.payload?.error ?? null,
    authErrorDescription: auth.payload?.error_description ?? null,
  };
  const outputPath = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile: outputPath }, null, 2));
  process.exit(0);
}

const { sql, absolute: sqlAbsolutePath } = readSqlFile(sqlFileArg);
const trimmedSql = sql.trim();
if (!trimmedSql) {
  const output = {
    marker: 'TRIBUTACAO_EXECUTE_QUERY_PROBE',
    ok: false,
    tenantId: creds.tenantId,
    environment: creds.env,
    bearerReceived: true,
    error: 'empty_sql',
    sqlFile: sqlAbsolutePath,
  };
  const outputPath = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile: outputPath }, null, 2));
  process.exit(0);
}

const endpointCandidates = buildEndpointCandidates();
const payloadVariants = buildPayloadVariants(trimmedSql);

const attempts = [];
let successfulAttempt = null;

for (const candidateBaseUrl of baseUrlCandidates) {
  for (const candidateEndpoint of endpointCandidates) {
    for (const payloadVariant of payloadVariants) {
      const result = await callExecuteQuery({
        baseUrl: candidateBaseUrl,
        endpointPath: candidateEndpoint,
        accessToken: auth.accessToken,
        xToken: creds.xToken,
        payloadVariant,
      });

      const attempt = {
        baseUrl: candidateBaseUrl,
        endpointPath: candidateEndpoint,
        payloadVariant: result.payloadVariant,
        httpStatus: result.status,
        ok: result.ok,
        rowCountDetected: result.rowCountDetected,
        responseIsJson: result.responseIsJson,
        responseBodyPreview:
          result.responseBody && typeof result.responseBody === 'object'
            ? JSON.stringify(result.responseBody).slice(0, 1200)
            : String(result.responseBody).slice(0, 1200),
      };
      attempts.push(attempt);

      if (result.ok) {
        successfulAttempt = {
          baseUrl: candidateBaseUrl,
          endpointPath: candidateEndpoint,
          payloadVariant: result.payloadVariant,
          httpStatus: result.status,
          responseIsJson: result.responseIsJson,
          rowCountDetected: result.rowCountDetected,
          responseBody: result.responseBody,
          requestPayload: result.payload,
        };
        break;
      }

      const code = result.responseBody?.error?.code ?? '';
      if (result.status === 401 || result.status === 403 || code === 'UNAUTHORIZED') {
        // Unauthorized on this base/endpoint combination; continue trying others.
      }
    }

    if (successfulAttempt) {
      break;
    }
  }

  if (successfulAttempt) {
    break;
  }
}

const output = {
  marker: 'TRIBUTACAO_EXECUTE_QUERY_PROBE',
  ok: successfulAttempt != null,
  tenantId: creds.tenantId,
  environment: creds.env,
  baseUrlCandidates,
  endpointCandidates,
  sqlFile: sqlAbsolutePath,
  sqlPreview: trimmedSql.slice(0, 500),
  successfulAttempt,
  attempts,
};

const outputPath = saveOutputFile(output);
console.log(JSON.stringify({ ...output, savedFile: outputPath }, null, 2));
