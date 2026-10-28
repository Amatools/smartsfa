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

async function authenticate({ baseUrl, clientId, clientSecret, xToken }) {
  const response = await fetch(`${baseUrl}/authenticate`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      Authorization:
        'Basic ' + Buffer.from(`${clientId}:${clientSecret}`).toString('base64'),
    },
    body: JSON.stringify({ grant_type: 'client_credentials' }),
  });
  const payload = await response.json();
  return payload.access_token;
}

async function runQuery({ baseUrl, bearerToken, xToken, sql }) {
  const response = await fetch(
    `${baseUrl}/gateway/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        Authorization: `Bearer ${bearerToken}`,
        'x-token': xToken,
      },
      body: JSON.stringify({
        serviceName: 'DbExplorerSP.executeQuery',
        requestBody: { sql },
      }),
    },
  );
  const text = await response.text();
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { raw: text };
  }
  const root = parsed.responseBody && typeof parsed.responseBody === 'object'
    ? parsed.responseBody
    : parsed;
  return { status: response.status, fields: root.fieldsMetadata, rows: root.rows };
}

const queries = {
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
  ncm_specific_rows_sample: `
SELECT ICM.CODTAB, ICM.SEQUENCIA, ICM.IDALIQ, ICM.UFORIG, ICM.UFDEST,
       TO_CHAR(ICM.TIPRESTRICAO) AS TIPRESTRICAO,
       TO_CHAR(ICM.CODRESTRICAO) AS CODRESTRICAO,
       ICM.ALIQUOTA, ICM.ALIQINTDEST
FROM TGFICM ICM
WHERE TO_CHAR(ICM.TIPRESTRICAO) IN ('N','4','H','P','1','I','K')
  AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1','0')
FETCH FIRST 15 ROWS ONLY
`,
};

async function run() {
  const creds = await resolveCreds();
  if (!creds) throw new Error('Credenciais ERP nao encontradas.');
  const baseUrl =
    creds.environment === 'prod'
      ? 'https://api.sankhya.com.br'
      : 'https://api.sandbox.sankhya.com.br';
  const bearerToken = await authenticate({ baseUrl, ...creds });

  const results = {};
  for (const [name, sql] of Object.entries(queries)) {
    try {
      results[name] = await runQuery({ baseUrl, bearerToken, xToken: creds.xToken, sql });
    } catch (error) {
      results[name] = { error: error.message };
    }
  }

  console.log(JSON.stringify(results, null, 2));
}

run().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 1;
});
