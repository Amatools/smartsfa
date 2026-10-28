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

const SANKHYA_PRODUCTION_URL = 'https://api.sankhya.com.br/authenticate';
const SANKHYA_SANDBOX_URL = 'https://api.sandbox.sankhya.com.br/authenticate';
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

async function authenticateInSankhya({ baseUrl, clientId, clientSecret, xToken }) {
  const formBody = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    grant_type: 'client_credentials',
  });
  const res = await fetch(baseUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-token': xToken },
    body: formBody,
    signal: AbortSignal.timeout(15000),
  });
  const text = await res.text();
  if (res.status !== 200) {
    throw new Error(`auth failed ${res.status}: ${text.slice(0, 300)}`);
  }
  const json = tryParseJson(text);
  return json && typeof json === 'object' ? json : Object.fromEntries(new URLSearchParams(text));
}

async function executeQuery({ apiBaseUrl, bearerToken, xToken, sql }) {
  const variants = [
    { serviceName: 'DbExplorerSP.executeQuery', requestBody: { sql } },
    { requestBody: { sql } },
    { requestBody: { query: sql } },
  ];
  for (const endpointPath of SANKHYA_DBEXPLORER_ENDPOINT_PATHS) {
    for (const payload of variants) {
      const res = await fetch(`${apiBaseUrl}${endpointPath}`, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          Authorization: `Bearer ${bearerToken}`,
          'content-type': 'application/json',
          'x-token': xToken,
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(30000),
      });
      const text = await res.text();
      if (res.status === 200) {
        const json = tryParseJson(text);
        const rows = normalizeDbExplorerRows(json);
        if (rows.length > 0 || res.status === 200) {
          return { rows, raw: json };
        }
      }
    }
  }
  throw new Error('Todos os endpoints/variantes falharam');
}

async function resolveCreds() {
  const user = await getAuth().getUserByEmail('enterprise@smartsfa.com.br');
  const memberships = await getFirestore()
    .collection('tenant_memberships')
    .where('uid', '==', user.uid)
    .get();
  for (const membership of memberships.docs) {
    const tenantId = membership.data().tenantId;
    const tenant = (await getFirestore().collection('tenants').doc(tenantId).get()).data() ?? {};
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

async function run() {
  const creds = await resolveCreds();
  if (!creds) throw new Error('Credenciais nao encontradas.');

  const authBaseUrl =
    creds.environment === 'prod' ? SANKHYA_PRODUCTION_URL : SANKHYA_SANDBOX_URL;
  const apiBaseUrl = authBaseUrl.replace('/authenticate', '');

  const authPayload = await authenticateInSankhya({
    baseUrl: authBaseUrl,
    clientId: creds.clientId,
    clientSecret: creds.clientSecret,
    xToken: creds.xToken,
  });
  const bearerToken = String(
    authPayload.access_token ?? authPayload.accessToken ?? authPayload.token ?? '',
  ).trim();
  if (!bearerToken) {
    throw new Error('Nao foi possivel extrair bearer token: ' + JSON.stringify(authPayload));
  }

  const sql = `
SELECT
    TO_CHAR(ICM.CODTAB) AS CODTAB,
    TO_CHAR(ICM.SEQUENCIA) AS SEQUENCIA,
    NVL(UFO.UF, 'ANY') AS UFORIGEM,
    NVL(UFD.UF, 'ANY') AS UFDESTINO,
    TO_CHAR(ICM.ALIQUOTA) AS ALIQUOTA_RAW,
    TO_CHAR(ICM.ALIQINTDEST) AS ALIQINTDEST_RAW,
    TO_CHAR(ICM.ALIQSUBTRIB) AS ALIQSUBTRIB_RAW,
    TO_CHAR(ICM.TIPRESTRICAO) AS TIPRESTRICAO,
    TO_CHAR(ICM.CODRESTRICAO) AS CODRESTRICAO,
    TO_CHAR(ICM.DTINICIOVIGENCIA, 'YYYY-MM-DD') AS VIGENCIAINICIAL
FROM TGFICM ICM
LEFT JOIN TSIUFS UFO ON ICM.UFORIG = UFO.CODUF
LEFT JOIN TSIUFS UFD ON ICM.UFDEST = UFD.CODUF
WHERE UFO.UF = 'SP' AND UFD.UF = 'SP'
ORDER BY ICM.SEQUENCIA
`.trim();

  const result = await executeQuery({ apiBaseUrl, bearerToken, xToken: creds.xToken, sql });
  console.log(`linhas retornadas: ${result.rows.length}`);
  for (const row of result.rows.slice(0, 20)) {
    console.log(JSON.stringify(row));
  }
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
