#!/usr/bin/env node
/**
 * Executa uma consulta SOMENTE LEITURA (SELECT) direto no DbExplorerSP.executeQuery
 * do Sankhya, usando o MESMO fluxo de autenticacao e os MESMOS endpoints candidatos
 * ja validados em producao por `functions/index.js` (authenticateInSankhya +
 * executeSankhyaDbExplorerQuery). Nao depende de firebase-admin nem toca Firestore:
 * serve apenas para validar/explorar dados reais do tenant (ex.: TGFTOP, TGFPAR)
 * antes de decidir se vale a pena automatizar algum sync.
 *
 * Credenciais SEMPRE via variaveis de ambiente (nunca hardcode, nunca cole no chat):
 *   SANKHYA_ENV           homolog | prod
 *   SANKHYA_CLIENT_ID
 *   SANKHYA_CLIENT_SECRET
 *   SANKHYA_XTOKEN
 *
 * Uso:
 *   node scripts/sankhya_dbexplorer_query.mjs --sql "SELECT * FROM TGFTOP WHERE ROWNUM <= 5"
 *   node scripts/sankhya_dbexplorer_query.mjs --file scripts/sankhya_queries/top_ativos.sql
 *
 * Seguranca:
 *   - Este script so deve ser usado com SELECT. Nao faz nenhuma validacao de SQL,
 *     entao trate-o como voce trataria o proprio acesso do DbExplorer do Sankhya:
 *     use apenas com credenciais de um usuario com permissao de leitura.
 */

const SANKHYA_DBEXPLORER_ENDPOINT_PATHS = [
  '/gateway/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/gateway/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
];

function tryParseJson(text) {
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

function readBearerToken(payload) {
  if (!payload || typeof payload !== 'object') {
    return '';
  }
  const candidates = [
    payload.access_token,
    payload.accessToken,
    payload.token,
    payload.bearerToken,
  ];
  for (const candidate of candidates) {
    const value = String(candidate ?? '').trim();
    if (value) {
      return value;
    }
  }
  return '';
}

async function authenticateInSankhya({ baseUrl, clientId, clientSecret, xToken }) {
  const formBody = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    grant_type: 'client_credentials',
  });

  const authResponse = await fetch(`${baseUrl}/authenticate`, {
    method: 'POST',
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      'x-token': xToken,
    },
    body: formBody,
    signal: AbortSignal.timeout(15000),
  });

  const authBodyText = await authResponse.text();
  if (authResponse.status !== 200) {
    throw new Error(
      `Falha na autenticacao Sankhya (HTTP ${authResponse.status}): ${authBodyText.slice(0, 300)}`,
    );
  }

  const jsonPayload = tryParseJson(authBodyText);
  if (jsonPayload && typeof jsonPayload === 'object') {
    return jsonPayload;
  }
  return Object.fromEntries(new URLSearchParams(authBodyText));
}

function normalizeDbExplorerRows(payload) {
  if (!payload || typeof payload !== 'object') {
    return [];
  }
  const root =
    payload.responseBody && typeof payload.responseBody === 'object'
      ? payload.responseBody
      : payload;
  const rawRows = Array.isArray(root.rows) ? root.rows : [];
  if (rawRows.length === 0) {
    return [];
  }
  if (rawRows.every((row) => row && typeof row === 'object' && !Array.isArray(row))) {
    return rawRows;
  }
  const fields = Array.isArray(root.fieldsMetadata) ? root.fieldsMetadata : [];
  if (fields.length === 0) {
    return [];
  }
  return rawRows
    .filter((row) => Array.isArray(row))
    .map((row) => {
      const mapped = {};
      for (let index = 0; index < fields.length; index++) {
        const fieldName = String(fields[index]?.name ?? '').trim();
        if (!fieldName) {
          continue;
        }
        mapped[fieldName] = row[index] ?? null;
      }
      return mapped;
    });
}

async function executeSankhyaDbExplorerQuery({ baseUrl, bearerToken, xToken, sql }) {
  const payloadVariants = [
    { name: 'serviceName_requestBody_sql', payload: { serviceName: 'DbExplorerSP.executeQuery', requestBody: { sql } } },
    { name: 'requestBody_sql', payload: { requestBody: { sql } } },
    { name: 'requestBody_query', payload: { requestBody: { query: sql } } },
  ];

  const failures = [];
  for (const endpointPath of SANKHYA_DBEXPLORER_ENDPOINT_PATHS) {
    for (const payloadVariant of payloadVariants) {
      const response = await fetch(`${baseUrl}${endpointPath}`, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          Authorization: `Bearer ${bearerToken}`,
          'content-type': 'application/json',
          'x-token': xToken,
        },
        body: JSON.stringify(payloadVariant.payload),
        signal: AbortSignal.timeout(30000),
      });

      const bodyText = await response.text();
      const parsed = tryParseJson(bodyText);
      if (response.ok) {
        return {
          endpointPath,
          payloadVariant: payloadVariant.name,
          rows: normalizeDbExplorerRows(parsed),
        };
      }

      failures.push({
        endpointPath,
        payloadVariant: payloadVariant.name,
        status: response.status,
        bodyPreview: bodyText.slice(0, 220),
      });
    }
  }

  const details = failures
    .map((item) => `${item.endpointPath} [${item.payloadVariant}] -> HTTP ${item.status}: ${item.bodyPreview}`)
    .join(' | ')
    .slice(0, 1800);
  throw new Error(`DbExplorer executeQuery falhou. Tentativas: ${details}`);
}

function parseArgs(argv) {
  const result = { sql: null, file: null };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--sql') {
      result.sql = argv[index + 1] ?? null;
      index++;
    } else if (arg === '--file') {
      result.file = argv[index + 1] ?? null;
      index++;
    }
  }
  return result;
}

async function main() {
  const { sql: sqlArg, file } = parseArgs(process.argv.slice(2));

  let sql = sqlArg;
  if (!sql && file) {
    const fs = await import('node:fs/promises');
    sql = (await fs.readFile(file, 'utf8')).trim();
  }
  if (!sql) {
    console.error('Uso: node scripts/sankhya_dbexplorer_query.mjs --sql "SELECT ..." | --file caminho.sql');
    process.exit(1);
  }

  const environment = String(process.env.SANKHYA_ENV ?? '').trim().toLowerCase();
  const clientId = String(process.env.SANKHYA_CLIENT_ID ?? '').trim();
  const clientSecret = String(process.env.SANKHYA_CLIENT_SECRET ?? '').trim();
  const xToken = String(process.env.SANKHYA_XTOKEN ?? '').trim();

  if (!['homolog', 'prod'].includes(environment)) {
    console.error('Defina SANKHYA_ENV=homolog ou SANKHYA_ENV=prod.');
    process.exit(1);
  }
  if (!clientId || !clientSecret || !xToken) {
    console.error('Defina SANKHYA_CLIENT_ID, SANKHYA_CLIENT_SECRET e SANKHYA_XTOKEN no ambiente.');
    process.exit(1);
  }

  const baseUrl =
    environment === 'prod' ? 'https://api.sankhya.com.br' : 'https://api.sandbox.sankhya.com.br';

  const authPayload = await authenticateInSankhya({ baseUrl, clientId, clientSecret, xToken });
  const bearerToken = readBearerToken(authPayload);
  if (!bearerToken) {
    console.error('Autenticacao nao retornou access_token. Verifique credenciais/permissao do app Sankhya.');
    process.exit(1);
  }

  const result = await executeSankhyaDbExplorerQuery({ baseUrl, bearerToken, xToken, sql });
  console.error(`# endpoint: ${result.endpointPath} | payload: ${result.payloadVariant} | linhas: ${result.rows.length}`);
  console.log(JSON.stringify(result.rows, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
