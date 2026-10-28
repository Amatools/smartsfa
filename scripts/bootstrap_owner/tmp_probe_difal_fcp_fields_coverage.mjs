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
  const candidates = [configured, envBase];
  if (configured) {
    try {
      const url = new URL(configured);
      candidates.push(`${url.protocol}//${url.host}`);
    } catch {
      // noop
    }
  }
  const unique = [];
  const seen = new Set();
  for (const value of candidates) {
    if (value && !seen.has(value)) {
      seen.add(value);
      unique.push(value);
    }
  }
  return unique;
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
  if (!parsed || typeof parsed !== 'object') return [];
  if (Array.isArray(parsed.rows)) return parsed.rows;
  if (Array.isArray(parsed?.responseBody?.rows)) return parsed.responseBody.rows;
  if (Array.isArray(parsed?.responseBody?.result)) return parsed.responseBody.result;
  return [];
}

function extractFields(parsed) {
  if (!parsed || typeof parsed !== 'object') return [];
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
  return { status: authResponse.status, accessToken, payload: authPayload };
}

async function runExecuteQuery({ baseUrl, endpointPath, accessToken, xToken, sql }) {
  const payload = { serviceName: 'DbExplorerSP.executeQuery', requestBody: { sql } };
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
    rows,
    responseBody: response.ok ? undefined : (parsed ?? { raw: text }),
  };
}

function saveOutputFile(output) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const outputDir = path.join(__dirname, '..', '..', 'docs', 'sankhya-api', 'examples');
  const outputPath = path.join(outputDir, `difal_fcp_fields_coverage_${stamp}.json`);
  fs.mkdirSync(outputDir, { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
  return outputPath;
}

const queries = {
  coverage: `
SELECT
  COUNT(*) AS TOTAL_LINHAS,
  SUM(CASE WHEN NVL(ICM.PERCICMSFCP, 0) <> 0 THEN 1 ELSE 0 END) AS LINHAS_PERCICMSFCP,
  SUM(CASE WHEN NVL(ICM.PERCICMSFCPINT, 0) <> 0 THEN 1 ELSE 0 END) AS LINHAS_PERCICMSFCPINT,
  SUM(CASE WHEN NVL(ICM.PERCSTFCPINT, 0) <> 0 THEN 1 ELSE 0 END) AS LINHAS_PERCSTFCPINT,
  SUM(CASE WHEN ICM.TIPCALCDIFAL IS NOT NULL THEN 1 ELSE 0 END) AS LINHAS_TIPCALCDIFAL,
  SUM(CASE WHEN ICM.REPDIFALFCP IS NOT NULL THEN 1 ELSE 0 END) AS LINHAS_REPDIFALFCP,
  SUM(CASE WHEN NVL(ICM.ALIQINTDEST, 0) <> 0 THEN 1 ELSE 0 END) AS LINHAS_ALIQINTDEST,
  SUM(CASE WHEN NVL(ICM.ALIQUOTA, 0) <> 0 THEN 1 ELSE 0 END) AS LINHAS_ALIQUOTA,
  SUM(CASE WHEN NVL(ICM.ALIQSUBTRIB, 0) <> 0 THEN 1 ELSE 0 END) AS LINHAS_ALIQSUBTRIB,
  SUM(CASE WHEN ICM.UFORIG <> ICM.UFDEST THEN 1 ELSE 0 END) AS LINHAS_INTERESTADUAL,
  COUNT(DISTINCT ICM.REPDIFALFCP) AS DISTINCT_REPDIFALFCP,
  COUNT(DISTINCT ICM.TIPCALCDIFAL) AS DISTINCT_TIPCALCDIFAL
FROM TGFICM ICM
`,
  distinct_flags: `
SELECT ICM.REPDIFALFCP, ICM.TIPCALCDIFAL, COUNT(*) AS QTD
FROM TGFICM ICM
GROUP BY ICM.REPDIFALFCP, ICM.TIPCALCDIFAL
ORDER BY QTD DESC
`,
  samples_fcp: `
SELECT
  ICM.CODTAB,
  ICM.SEQUENCIA,
  ICM.IDALIQ,
  ICM.UFORIG,
  ICM.UFDEST,
  ICM.PERCICMSFCP,
  ICM.PERCICMSFCPINT,
  ICM.PERCSTFCPINT,
  ICM.TIPCALCDIFAL,
  ICM.REPDIFALFCP,
  ICM.ALIQINTDEST,
  ICM.ALIQUOTA,
  ICM.ALIQSUBTRIB
FROM TGFICM ICM
WHERE NVL(ICM.PERCICMSFCP, 0) <> 0
   OR NVL(ICM.PERCICMSFCPINT, 0) <> 0
   OR NVL(ICM.PERCSTFCPINT, 0) <> 0
FETCH FIRST 30 ROWS ONLY
`,
  samples_difal_interstate: `
SELECT
  ICM.CODTAB,
  ICM.SEQUENCIA,
  ICM.IDALIQ,
  ICM.UFORIG,
  ICM.UFDEST,
  ICM.ALIQINTDEST,
  ICM.ALIQUOTA,
  ICM.ALIQSUBTRIB,
  ICM.TIPCALCDIFAL,
  ICM.PERCICMSFCP
FROM TGFICM ICM
WHERE ICM.UFORIG <> ICM.UFDEST
FETCH FIRST 30 ROWS ONLY
`,
  updated_sync_sql_dryrun: `
SELECT * FROM (
SELECT DISTINCT
    NVL(UFO.UF, 'ANY') AS UFORIGEM,
    NVL(UFD.UF, 'ANY') AS UFDESTINO,
    CASE
        WHEN NVL(ICM.ALIQINTDEST, 0) > 0
             AND UFO.UF IS NOT NULL
             AND UFD.UF IS NOT NULL
             AND UFO.UF <> UFD.UF
            THEN TO_CHAR(GREATEST(ICM.ALIQINTDEST - NVL(ICM.ALIQUOTA, 0), 0))
        ELSE TO_CHAR(NULL)
    END AS ALIQUOTADIFAL,
    TO_CHAR(ICM.PERCICMSFCPINT) AS PERCFCPINTERNO,
    TO_CHAR(ICM.PERCICMSFCP) AS PERCFCPGERAL,
    TO_CHAR(ICM.PERCSTFCPINT) AS PERCSTFCPINTERNO,
    ICM.ALIQINTDEST,
    ICM.ALIQUOTA
FROM TGFICM ICM
LEFT JOIN TSIUFS UFO ON ICM.UFORIG = UFO.CODUF
LEFT JOIN TSIUFS UFD ON ICM.UFDEST = UFD.CODUF
WHERE ICM.DTINICIOVIGENCIA IS NULL OR ICM.DTINICIOVIGENCIA <= SYSDATE
)
WHERE ALIQUOTADIFAL IS NOT NULL
   OR PERCFCPINTERNO IS NOT NULL
   OR PERCFCPGERAL IS NOT NULL
   OR PERCSTFCPINTERNO IS NOT NULL
FETCH FIRST 30 ROWS ONLY
`,
  distinct_uf_pairs_with_difal: `
SELECT COUNT(DISTINCT ICM.UFORIG || '-' || ICM.UFDEST) AS PARES_DISTINTOS,
       COUNT(*) AS TOTAL_LINHAS
FROM TGFICM ICM
WHERE NVL(ICM.ALIQINTDEST, 0) > 0
  AND ICM.UFORIG <> ICM.UFDEST
`,
  restriction_types_on_difal_rows: `
SELECT NVL(TO_CHAR(ICM.TIPRESTRICAO), 'NULL') AS TIPRESTRICAO,
       NVL(TO_CHAR(ICM.CODRESTRICAO), 'NULL') AS CODRESTRICAO,
       COUNT(*) AS QTD
FROM TGFICM ICM
WHERE NVL(ICM.ALIQINTDEST, 0) > 0
  AND ICM.UFORIG <> ICM.UFDEST
GROUP BY TO_CHAR(ICM.TIPRESTRICAO), TO_CHAR(ICM.CODRESTRICAO)
ORDER BY QTD DESC
`,
  total_uf_count: `
SELECT COUNT(*) AS TOTAL_UFS FROM TSIUFS
`,
  rows_per_origin_uf_coverage: `
SELECT ICM.UFORIG, COUNT(DISTINCT ICM.UFDEST) AS QTD_DESTINOS
FROM TGFICM ICM
WHERE NVL(ICM.ALIQINTDEST, 0) > 0
  AND ICM.UFORIG <> ICM.UFDEST
GROUP BY ICM.UFORIG
ORDER BY ICM.UFORIG
`,
  ncm_specific_rows_count_and_sample: `
SELECT ICM.CODTAB, ICM.SEQUENCIA, ICM.IDALIQ, ICM.UFORIG, ICM.UFDEST,
       TO_CHAR(ICM.TIPRESTRICAO) AS TIPRESTRICAO,
       TO_CHAR(ICM.CODRESTRICAO) AS CODRESTRICAO,
       ICM.ALIQUOTA, ICM.ALIQINTDEST
FROM TGFICM ICM
WHERE TO_CHAR(ICM.TIPRESTRICAO) IN ('N','4','H','P','1','I','K')
  AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1','0')
FETCH FIRST 15 ROWS ONLY
`,
  codtrib_grupoicms_match_rate: `
WITH CODTRIB_GENERICO AS (
    SELECT DISTINCT NVL(ICM.CODTRIB, -1) AS CODTRIB
    FROM TGFICM ICM
    WHERE NVL(TO_CHAR(ICM.CODRESTRICAO), '-1') IN ('-1', '0')
      AND NVL(TO_CHAR(ICM.CODRESTRICAO2), '-1') IN ('-1', '0')
)
SELECT
    COUNT(*) AS CODTRIB_DISTINTOS_GENERICOS,
    SUM(
        CASE WHEN EXISTS (
            SELECT 1 FROM TGFPRO PRO
            WHERE PRO.ATIVO = 'S' AND NVL(PRO.GRUPOICMS, -1) = C.CODTRIB AND ROWNUM = 1
        ) THEN 1 ELSE 0 END
    ) AS CODTRIB_COM_MATCH_GRUPOICMS,
    SUM(
        CASE WHEN EXISTS (
            SELECT 1 FROM TGFPRO PRO
            WHERE PRO.ATIVO = 'S' AND NVL(PRO.GRUPOICMS2, -1) = C.CODTRIB AND ROWNUM = 1
        ) THEN 1 ELSE 0 END
    ) AS CODTRIB_COM_MATCH_GRUPOICMS2,
    SUM(
        CASE WHEN EXISTS (
            SELECT 1 FROM TGFPRO PRO
            WHERE PRO.ATIVO = 'S' AND (NVL(PRO.GRUPOICMS, -1) = C.CODTRIB OR NVL(PRO.GRUPOICMS2, -1) = C.CODTRIB)
              AND ROWNUM = 1
        ) THEN 1 ELSE 0 END
    ) AS CODTRIB_COM_MATCH_EM_QUALQUER_GRUPO
FROM CODTRIB_GENERICO C
`,
  codtrib_idaliq_distribution: `
SELECT
    NVL(ICM.CODTRIB, -1) AS CODTRIB,
    NVL(ICM.IDALIQ, -1) AS IDALIQ,
    COUNT(*) AS TOTAL
FROM TGFICM ICM
WHERE NVL(TO_CHAR(ICM.CODRESTRICAO), '-1') IN ('-1', '0')
  AND NVL(TO_CHAR(ICM.CODRESTRICAO2), '-1') IN ('-1', '0')
GROUP BY NVL(ICM.CODTRIB, -1), NVL(ICM.IDALIQ, -1)
ORDER BY TOTAL DESC
FETCH FIRST 20 ROWS ONLY
`,
  produtos_com_grupoicms_coverage: `
SELECT
  COUNT(*) AS TOTAL_PRODUTOS_ATIVOS,
  SUM(CASE WHEN NVL(PRO.GRUPOICMS, -1) <> -1 THEN 1 ELSE 0 END) AS COM_GRUPOICMS,
  SUM(CASE WHEN NVL(PRO.GRUPOICMS2, -1) <> -1 THEN 1 ELSE 0 END) AS COM_GRUPOICMS2,
  COUNT(DISTINCT PRO.GRUPOICMS) AS DISTINCT_GRUPOICMS,
  COUNT(DISTINCT PRO.GRUPOICMS2) AS DISTINCT_GRUPOICMS2
FROM TGFPRO PRO
WHERE PRO.ATIVO = 'S'
`,
  tiprestricao_distribution_full: `
SELECT
  NVL(TO_CHAR(ICM.TIPRESTRICAO), 'NULL') AS TIPRESTRICAO,
  COUNT(*) AS QTD
FROM TGFICM ICM
GROUP BY TO_CHAR(ICM.TIPRESTRICAO)
ORDER BY QTD DESC
`,
  tiprestricao2_distribution_full: `
SELECT
  NVL(TO_CHAR(ICM.TIPRESTRICAO2), 'NULL') AS TIPRESTRICAO2,
  COUNT(*) AS QTD
FROM TGFICM ICM
GROUP BY TO_CHAR(ICM.TIPRESTRICAO2)
ORDER BY QTD DESC
`,
  raw_rows_for_sample_ncm_sp_sp: `
SELECT ICM.CODTAB, ICM.SEQUENCIA, ICM.IDALIQ, ICM.UFORIG, ICM.UFDEST,
       TO_CHAR(ICM.TIPRESTRICAO) AS TIPRESTRICAO,
       TO_CHAR(ICM.CODRESTRICAO) AS CODRESTRICAO,
       TO_CHAR(ICM.TIPRESTRICAO2) AS TIPRESTRICAO2,
       TO_CHAR(ICM.CODRESTRICAO2) AS CODRESTRICAO2,
       ICM.ALIQUOTA, ICM.ALIQINTDEST, ICM.CODTRIB, ICM.CST
FROM TGFICM ICM
WHERE ICM.CODRESTRICAO IN (
  SELECT PRO.CODPROD FROM TGFPRO PRO WHERE PRO.NCM IN ('42032900','42033000','64034000')
)
OR EXISTS (
  SELECT 1 FROM TGFPRO PRO WHERE PRO.NCM IN ('42032900','42033000','64034000')
    AND (TO_CHAR(ICM.TIPRESTRICAO) IN ('N','4','H','P','1') AND ICM.CODRESTRICAO = PRO.CODPROD)
)
FETCH FIRST 20 ROWS ONLY
`,
};

async function run() {
  const creds = await resolveCreds();
  if (!creds) {
    throw new Error('Nao foi possivel localizar credenciais ERP configuradas em nenhum tenant do usuario enterprise@smartsfa.com.br.');
  }

  const baseUrls = buildBaseUrlCandidates(creds);
  const endpoints = buildEndpointCandidates();

  let authResult = null;
  let workingBaseUrl = null;
  for (const baseUrl of baseUrls) {
    const attempt = await authenticate(baseUrl, creds);
    if (attempt.accessToken) {
      authResult = attempt;
      workingBaseUrl = baseUrl;
      break;
    }
  }

  if (!authResult) {
    throw new Error('Falha ao autenticar em todos os baseUrl candidatos.');
  }

  const output = {
    tenantId: creds.tenantId,
    env: creds.env,
    baseUrl: workingBaseUrl,
    results: {},
  };

  for (const [name, sql] of Object.entries(queries)) {
    let lastError = null;
    let success = null;
    for (const endpointPath of endpoints) {
      try {
        const result = await runExecuteQuery({
          baseUrl: workingBaseUrl,
          endpointPath,
          accessToken: authResult.accessToken,
          xToken: creds.xToken,
          sql,
        });
        if (result.ok) {
          success = { endpointPath, ...result };
          break;
        }
        lastError = result;
      } catch (error) {
        lastError = { error: String(error?.message ?? error) };
      }
    }
    output.results[name] = success ?? { failed: true, lastError };
  }

  const outputPath = saveOutputFile(output);
  console.log(`# salvo em: ${outputPath}`);
  console.log(JSON.stringify(output, null, 2));
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
