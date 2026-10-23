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

function toList(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.data)) return payload.data;
  if (Array.isArray(payload?.items)) return payload.items;
  if (Array.isArray(payload?.itens)) return payload.itens;
  if (Array.isArray(payload?.precos)) return payload.precos;
  if (Array.isArray(payload?.produtos)) return payload.produtos;
  return [];
}

function readCode(source, keys) {
  if (!source || typeof source !== 'object') {
    return '';
  }
  for (const key of keys) {
    const value = source[key];
    if (value == null) {
      continue;
    }
    const text = String(value).trim();
    if (text) {
      return text;
    }
  }
  return '';
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
  const outputPath = path.join(outputDir, `sankhya_preco_tabela_probe_${stamp}.json`);
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

async function discoverPriceTableCode(baseUrl, token) {
  const discovery = {
    productsProbeStatus: null,
    productsChecked: 0,
    productPriceChecks: [],
    tablesListProbeStatus: null,
    selectedBy: null,
    selectedCodigoTabela: null,
  };

  const productsProbe = await fetchWithBearer(baseUrl, token, '/v1/produtos?page=0');
  discovery.productsProbeStatus = productsProbe.status;

  const productList = toList(productsProbe.bodyParsed);
  const productCodes = productList
    .map((item) =>
      readCode(item, [
        'codigoProduto',
        'codigo',
        'codProduto',
        'CODPROD',
        'id',
      ]),
    )
    .filter((value) => /^\d+$/.test(value));

  const maxChecks = Math.min(productCodes.length, 12);
  for (let i = 0; i < maxChecks; i += 1) {
    const codigoProduto = productCodes[i];
    const pathProbe = `/v1/precos/produto/${codigoProduto}?pagina=1`;
    const probe = await fetchWithBearer(baseUrl, token, pathProbe);
    const precos = toList(probe.bodyParsed);

    let codigoTabela = '';
    for (const item of precos) {
      codigoTabela = readCode(item, [
        'codigoTabela',
        'codTabela',
        'CODTAB',
        'tabela',
      ]);
      if (/^\d+$/.test(codigoTabela)) {
        break;
      }
      codigoTabela = '';
    }

    discovery.productPriceChecks.push({
      codigoProduto,
      path: pathProbe,
      status: probe.status,
      registros: precos.length,
      errorCode: probe.bodyParsed?.error?.code ?? null,
      errorDetails:
        probe.bodyParsed?.error?.details ??
        probe.bodyParsed?.mensagem?.details ??
        probe.bodyParsed?.message ??
        null,
      codigoTabelaEncontrado: codigoTabela || null,
    });
    discovery.productsChecked += 1;

    if (codigoTabela) {
      discovery.selectedBy = 'preco_por_produto';
      discovery.selectedCodigoTabela = codigoTabela;
      return discovery;
    }
  }

  const tableListProbe = await fetchWithBearer(
    baseUrl,
    token,
    '/v1/tabelas-preco?page=1',
  );
  discovery.tablesListProbeStatus = tableListProbe.status;
  discovery.tablesListProbeErrorCode = tableListProbe.bodyParsed?.error?.code ?? null;
  discovery.tablesListProbeErrorDetails =
    tableListProbe.bodyParsed?.error?.details ??
    tableListProbe.bodyParsed?.mensagem?.details ??
    tableListProbe.bodyParsed?.message ??
    null;

  const tableList = toList(tableListProbe.bodyParsed);
  for (const item of tableList) {
    const codigoTabela = readCode(item, [
      'codigoTabela',
      'codigo',
      'codTabela',
      'CODTAB',
      'id',
    ]);
    if (/^\d+$/.test(codigoTabela)) {
      discovery.selectedBy = 'lista_tabelas_preco';
      discovery.selectedCodigoTabela = codigoTabela;
      return discovery;
    }
  }

  return discovery;
}

const args = parseArgs();
const requestedTableCode = String(args.codigoTabela ?? '').trim();
const page = Number.parseInt(String(args.pagina ?? '1'), 10);
const safePage = Number.isFinite(page) && page > 0 ? page : 1;

const creds = await resolveCreds();
if (!creds) {
  const output = {
    marker: 'PRECO_TABELA_PROBE',
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
    marker: 'PRECO_TABELA_PROBE',
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

const discovery = {
  productsProbeStatus: null,
  productsChecked: 0,
  productPriceChecks: [],
  tablesListProbeStatus: null,
  selectedBy: 'argumento',
  selectedCodigoTabela: requestedTableCode || null,
};

let codigoTabela = requestedTableCode;
if (!/^\d+$/.test(codigoTabela)) {
  const discovered = await discoverPriceTableCode(baseUrl, accessToken);
  discovery.productsProbeStatus = discovered.productsProbeStatus;
  discovery.productsChecked = discovered.productsChecked;
  discovery.productPriceChecks = discovered.productPriceChecks;
  discovery.tablesListProbeStatus = discovered.tablesListProbeStatus;
  discovery.selectedBy = discovered.selectedBy;
  discovery.selectedCodigoTabela = discovered.selectedCodigoTabela;
  codigoTabela = String(discovered.selectedCodigoTabela ?? '').trim();
}

if (!/^\d+$/.test(codigoTabela)) {
  const output = {
    marker: 'PRECO_TABELA_PROBE',
    ok: false,
    tenantId: creds.tenantId,
    environment: creds.env,
    authStatus: authResponse.status,
    bearerReceived: true,
    error: 'codigo_tabela_not_found',
    discovery,
  };
  const outputPath = saveOutputFile(output);
  console.log(JSON.stringify({ ...output, savedFile: outputPath }, null, 2));
  process.exit(0);
}

const endpointPath = `/v1/precos/tabela/${codigoTabela}?pagina=${safePage}`;
const target = await fetchWithBearer(baseUrl, accessToken, endpointPath);

const responseBody = target.bodyParsed ?? { raw: target.bodyText };
const precos = toList(target.bodyParsed);
const pageValue = Number(target.bodyParsed?.page ?? safePage);
const numeroRegistros = Number(target.bodyParsed?.numeroRegistros ?? precos.length);
const temMaisRegistros = Boolean(target.bodyParsed?.temMaisRegistros ?? false);

const output = {
  marker: 'PRECO_TABELA_PROBE',
  ok: target.status >= 200 && target.status < 300,
  executedAt: new Date().toISOString(),
  tenantId: creds.tenantId,
  environment: creds.env,
  baseUrl,
  authStatus: authResponse.status,
  bearerReceived: true,
  discovery,
  request: {
    method: 'GET',
    path: endpointPath,
  },
  response: {
    status: target.status,
    isJson: target.isJson,
    body: responseBody,
  },
  summary: {
    codigoTabela,
    page: pageValue,
    numeroRegistros,
    temMaisRegistros,
    totalItensNoArrayPrecos: precos.length,
  },
};

const outputPath = saveOutputFile(output);

console.log(
  JSON.stringify(
    {
      marker: 'PRECO_TABELA_PROBE',
      ok: output.ok,
      tenantId: creds.tenantId,
      environment: creds.env,
      requestPath: endpointPath,
      status: target.status,
      savedFile: outputPath,
      summary: output.summary,
    },
    null,
    2,
  ),
);
