const { onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const crypto = require('node:crypto');

const SANKHYA_PRODUCTION_URL = 'https://api.sankhya.com.br/authenticate';
const SANKHYA_SANDBOX_URL =
  'https://api.sandbox.sankhya.com.br/authenticate';
const SANKHYA_PRODUCTS_PATH = '/v1/produtos?page=0';
const SANKHYA_DBEXPLORER_ENDPOINT_PATHS = [
  '/gateway/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/gateway/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
  '/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
];
const TEMPORARY_IMPORT_LIMIT = 5;

if (!admin.apps.length) {
  admin.initializeApp();
}

exports.testSankhyaAuthentication = onRequest(
  { cors: true, region: 'us-central1', timeoutSeconds: 30 },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const environment = String(request.body?.environment ?? '')
      .trim()
      .toLowerCase();
    const clientId = String(request.body?.clientId ?? '').trim();
    const clientSecret = String(request.body?.clientSecret ?? '').trim();
    const xToken = String(request.body?.xToken ?? '').trim();

    if (!['homolog', 'prod'].includes(environment)) {
      response.status(400).json({
        error: 'invalid_environment',
        error_description: 'Use homolog ou prod.',
      });
      return;
    }
    if (!clientId || !clientSecret || !xToken) {
      response.status(400).json({
        error: 'missing_credentials',
        error_description: 'Client Id, Client Secret e X-Token sao obrigatorios.',
      });
      return;
    }

    const targetUrl =
      environment === 'prod'
        ? SANKHYA_PRODUCTION_URL
        : SANKHYA_SANDBOX_URL;
    const formBody = new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: 'client_credentials',
    });

    try {
      const sankhyaResponse = await fetch(targetUrl, {
        method: 'POST',
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
          'x-token': xToken,
        },
        body: formBody,
        signal: AbortSignal.timeout(15000),
      });
      const bodyText = await sankhyaResponse.text();
      let payload = {};
      try {
        payload = JSON.parse(bodyText);
      } catch (_) {
        payload = Object.fromEntries(new URLSearchParams(bodyText));
      }

      response.status(sankhyaResponse.status).json(payload);
    } catch (error) {
      response.status(502).json({
        error: 'sankhya_unavailable',
        error_description: error instanceof Error ? error.message : String(error),
      });
    }
  },
);

exports.syncSankhyaCatalogModule = onRequest(
  { cors: true, region: 'us-central1', timeoutSeconds: 300 },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const tenantId = String(request.body?.tenantId ?? '').trim();
    const moduleId = String(request.body?.module ?? '').trim().toLowerCase();
    const environment = String(request.body?.environment ?? '')
      .trim()
      .toLowerCase();
    const clientId = String(request.body?.clientId ?? '').trim();
    const clientSecret = String(request.body?.clientSecret ?? '').trim();
    const xToken = String(request.body?.xToken ?? '').trim();
    // Filtro temporario de validacao: quando presente, restringe o sync de
    // 'clientes' a uma lista explicita de CODPARC (ex.: ['191']), evitando
    // puxar a base inteira de parceiros enquanto o mapeamento de campos ainda
    // esta em teste. Vazio/ausente = sem filtro (sync completo).
    const codigosFiltroRaw = request.body?.codigosFiltro;
    const codigosFiltro = Array.isArray(codigosFiltroRaw)
      ? codigosFiltroRaw
      : [];

    if (!tenantId) {
      response.status(400).json({
        error: 'missing_tenant',
        message: 'tenantId e obrigatorio.',
      });
      return;
    }

    if (!['homolog', 'prod'].includes(environment)) {
      response.status(400).json({
        error: 'invalid_environment',
        message: 'Use homolog ou prod.',
      });
      return;
    }

    if (!clientId || !clientSecret || !xToken) {
      response.status(400).json({
        error: 'missing_credentials',
        message: 'Client Id, Client Secret e X-Token sao obrigatorios.',
      });
      return;
    }

    if (!['produtos', 'tabelas_preco', 'tax_rules', 'clientes'].includes(moduleId)) {
      response.status(400).json({
        error: 'module_not_enabled',
        message:
          'Modulo ainda nao habilitado para ingestao. Valide endpoint/permissao e ative o modulo.',
        module: moduleId,
      });
      return;
    }

    const baseUrl =
      environment === 'prod'
        ? 'https://api.sankhya.com.br'
        : 'https://api.sandbox.sankhya.com.br';

    try {
      const authPayload = await authenticateInSankhya({
        baseUrl,
        clientId,
        clientSecret,
        xToken,
      });

      const bearerToken = readBearerToken(authPayload);
      if (!bearerToken) {
        response.status(502).json({
          error: 'missing_bearer',
          message:
            'Autenticacao retornou sem access_token. Verifique credenciais e permissao do app Sankhya.',
        });
        return;
      }
      const firestore = admin.firestore();
      let result;
      if (moduleId === 'produtos') {
        result = await syncSankhyaProductsModule({
          firestore,
          tenantId,
          baseUrl,
          bearerToken,
          xToken,
        });
      } else if (moduleId === 'tax_rules') {
        result = await syncSankhyaTaxRulesModule({
          firestore,
          tenantId,
          baseUrl,
          bearerToken,
          xToken,
        });
      } else if (moduleId === 'clientes') {
        result = await syncSankhyaClientesModule({
          firestore,
          tenantId,
          baseUrl,
          bearerToken,
          xToken,
          codigosFiltro,
        });
      } else {
        result = await syncSankhyaPriceTablesModule({
          firestore,
          tenantId,
          baseUrl,
          bearerToken,
          xToken,
        });
      }

      response.status(200).json({
        success: true,
        module: moduleId,
        environment,
        ...result,
      });
    } catch (error) {
      response.status(502).json({
        error: 'sankhya_sync_failed',
        message: error instanceof Error ? error.message : String(error),
      });
    }
  },
);

exports.fetchSankhyaOperationTypes = onRequest(
  { cors: true, region: 'us-central1', timeoutSeconds: 30 },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    const environment = String(request.body?.environment ?? '')
      .trim()
      .toLowerCase();
    const clientId = String(request.body?.clientId ?? '').trim();
    const clientSecret = String(request.body?.clientSecret ?? '').trim();
    const xToken = String(request.body?.xToken ?? '').trim();

    if (!['homolog', 'prod'].includes(environment)) {
      response.status(400).json({
        error: 'invalid_environment',
        message: 'Use homolog ou prod.',
      });
      return;
    }
    if (!clientId || !clientSecret || !xToken) {
      response.status(400).json({
        error: 'missing_credentials',
        message: 'Client Id, Client Secret e X-Token sao obrigatorios.',
      });
      return;
    }

    const baseUrl =
      environment === 'prod'
        ? 'https://api.sankhya.com.br'
        : 'https://api.sandbox.sankhya.com.br';

    try {
      const authPayload = await authenticateInSankhya({
        baseUrl,
        clientId,
        clientSecret,
        xToken,
      });

      const bearerToken = readBearerToken(authPayload);
      if (!bearerToken) {
        response.status(502).json({
          error: 'missing_bearer',
          message:
            'Autenticacao retornou sem access_token. Verifique credenciais e permissao do app Sankhya.',
        });
        return;
      }

      const sql = buildSankhyaOperationTypesSql();
      const queryResult = await executeSankhyaDbExplorerQuery({
        baseUrl,
        bearerToken,
        xToken,
        sql,
      });

      const operationTypes = queryResult.rows
        .map((row) => mapSankhyaOperationTypeRow(row))
        .filter((item) => item && item.code);

      response.status(200).json({
        ok: true,
        environment,
        endpoint: queryResult.endpointPath,
        rowCount: operationTypes.length,
        operationTypes,
      });
    } catch (error) {
      response.status(502).json({
        error: 'sankhya_operation_types_failed',
        message: error instanceof Error ? error.message : String(error),
      });
    }
  },
);

function buildSankhyaOperationTypesSql() {
  return `
SELECT
    T.CODTIPOPER AS CodTipoOper,
    T.DESCROPER AS Descricao,
    T.TIPMOV AS TipoMovimento,
    T.CALCDIFALPART AS CalcDifalPart,
    T.CALCICMS AS CalcIcms,
    T.CALCFCPINT AS CalcFcpInt,
    T.CALCFUSTTOP AS CalcFustTop
FROM TGFTOP T
WHERE T.ATIVO = 'S'
  AND T.DHALTER = (
        SELECT MAX(T2.DHALTER) FROM TGFTOP T2 WHERE T2.CODTIPOPER = T.CODTIPOPER
      )
ORDER BY T.CODTIPOPER
`.trim();
}

function mapSankhyaOperationTypeRow(row) {
  const code = toCodeString(
    readRowValueByAliases(row, ['CodTipoOper', 'CODTIPOOPER']),
  );
  if (!code) {
    return null;
  }

  return {
    code,
    description: String(
      readRowValueByAliases(row, ['Descricao', 'DESCRICAO']) ?? '',
    ).trim(),
    movementType: String(
      readRowValueByAliases(row, ['TipoMovimento', 'TIPOMOVIMENTO']) ?? '',
    ).trim(),
    calcDifalPart: String(
      readRowValueByAliases(row, ['CalcDifalPart', 'CALCDIFALPART']) ?? '',
    ).trim(),
    calcIcms: String(
      readRowValueByAliases(row, ['CalcIcms', 'CALCICMS']) ?? '',
    ).trim(),
    calcFcpInt: String(
      readRowValueByAliases(row, ['CalcFcpInt', 'CALCFCPINT']) ?? '',
    ).trim(),
    calcFustTop: String(
      readRowValueByAliases(row, ['CalcFustTop', 'CALCFUSTTOP']) ?? '',
    ).trim(),
  };
}

exports.syncSankhyaPriceTablesNightly = onSchedule(
  {
    region: 'us-central1',
    schedule: '0 3 * * *',
    timeZone: 'America/Sao_Paulo',
    timeoutSeconds: 540,
  },
  async () => {
    const firestore = admin.firestore();
    const tenantsSnapshot = await firestore.collection('tenants').get();

    let processedTenants = 0;
    let skippedTenants = 0;
    let failedTenants = 0;

    for (const tenantDoc of tenantsSnapshot.docs) {
      const tenantId = tenantDoc.id;
      const tenantData = tenantDoc.data() || {};
      const integration =
        tenantData.erpIntegration && typeof tenantData.erpIntegration === 'object'
          ? tenantData.erpIntegration
          : {};
      const credentials =
        integration.credentials && typeof integration.credentials === 'object'
          ? integration.credentials
          : {};

      const provider = String(integration.provider ?? '').trim().toLowerCase();
      const environment = String(integration.environment ?? '')
        .trim()
        .toLowerCase();
      const clientId = String(credentials.username ?? '').trim();
      const clientSecret = String(credentials.password ?? '').trim();
      const xToken = String(credentials.accessToken ?? '').trim();

      if (
        provider !== 'sankhya' ||
        !['homolog', 'prod'].includes(environment) ||
        !clientId ||
        !clientSecret ||
        !xToken
      ) {
        skippedTenants += 1;
        continue;
      }

      const baseUrl =
        environment === 'prod'
          ? 'https://api.sankhya.com.br'
          : 'https://api.sandbox.sankhya.com.br';

      try {
        const authPayload = await authenticateInSankhya({
          baseUrl,
          clientId,
          clientSecret,
          xToken,
        });

        const bearerToken = readBearerToken(authPayload);
        if (!bearerToken) {
          throw new Error('Autenticacao sem access_token.');
        }

        await syncSankhyaPriceTablesModule({
          firestore,
          tenantId,
          baseUrl,
          bearerToken,
          xToken,
        });
        processedTenants += 1;
      } catch (error) {
        failedTenants += 1;
        console.error(
          '[syncSankhyaPriceTablesNightly] tenant_failed',
          JSON.stringify({
            tenantId,
            message: error instanceof Error ? error.message : String(error),
          }),
        );
      }
    }

    console.log(
      '[syncSankhyaPriceTablesNightly] summary',
      JSON.stringify({ processedTenants, skippedTenants, failedTenants }),
    );
  },
);

async function authenticateInSankhya({
  baseUrl,
  clientId,
  clientSecret,
  xToken,
}) {
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

async function updateTenantSyncState({ firestore, tenantId, patch }) {
  const ref = firestore.collection('tenant_sync_state').doc(tenantId);
  await ref.set(
    {
      tenantId,
      ...patch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
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

async function buildTenantNcmGroupIndex({ firestore, tenantId }) {
  const snapshot = await firestore
    .collection('tax_rule_groups')
    .where('tenantId', '==', tenantId)
    .select('memberNcms')
    .get();

  const index = new Map();
  for (const doc of snapshot.docs) {
    const memberNcms = doc.data()?.memberNcms;
    if (!Array.isArray(memberNcms)) {
      continue;
    }
    for (const ncmDigits of memberNcms) {
      const digits = normalizeDigits(ncmDigits);
      if (digits) {
        index.set(digits, doc.id);
      }
    }
  }
  return index;
}

async function syncSankhyaProductsModule({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
}) {
  const sourceUrl = `${baseUrl}${SANKHYA_PRODUCTS_PATH}`;
  const sankhyaResponse = await fetch(sourceUrl, {
    method: 'GET',
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${bearerToken}`,
      'x-token': xToken,
    },
    signal: AbortSignal.timeout(30000),
  });

  const sourceText = await sankhyaResponse.text();
  if (sankhyaResponse.status !== 200) {
    throw new Error(
      `Falha ao consultar modulo produtos no endpoint ${SANKHYA_PRODUCTS_PATH} (HTTP ${sankhyaResponse.status}): ${sourceText.slice(0, 300)}`,
    );
  }

  const sourceData = tryParseJson(sourceText);
  const sourceProducts = Array.isArray(sourceData?.produtos)
    ? sourceData.produtos
    : [];

  const validProducts = [];
  let filteredOutZeroCodeCount = 0;

  for (const rawItem of sourceProducts) {
    if (!rawItem || typeof rawItem !== 'object') {
      continue;
    }

    const productCode = toCodeString(rawItem.codigoProduto);
    if (!productCode || isZeroCode(productCode)) {
      filteredOutZeroCodeCount++;
      continue;
    }

    validProducts.push(rawItem);
    if (validProducts.length >= TEMPORARY_IMPORT_LIMIT) {
      break;
    }
  }

  const nowIso = new Date().toISOString();
  const syncBatchId = `sankhya_${Date.now()}`;
  const productsCollection = firestore.collection('produtos');
  const validProductCodes = validProducts
    .map((item) => toCodeString(item?.codigoProduto))
    .filter((item) => item && !isZeroCode(item));

  let fiscalQueryOk = false;
  let fiscalQueryEndpoint = null;
  let fiscalQueryRowsCount = 0;
  let fiscalQueryError = null;
  let fiscalMatchedCount = 0;
  let fiscalEnrichmentCount = 0;
  let fiscalOriginEnrichmentCount = 0;
  let fiscalIpiEnrichmentCount = 0;
  let productFiscalByCode = new Map();
  const ncmToGroupId = await buildTenantNcmGroupIndex({ firestore, tenantId });

  if (validProductCodes.length > 0) {
    try {
      const fiscalResult = await fetchSankhyaProductsFiscalData({
        baseUrl,
        bearerToken,
        xToken,
        productCodes: validProductCodes,
      });
      fiscalQueryOk = true;
      fiscalQueryEndpoint = fiscalResult.endpointPath;
      fiscalQueryRowsCount = fiscalResult.rowCount;
      productFiscalByCode = fiscalResult.byProductCode;
    } catch (error) {
      fiscalQueryError = error instanceof Error ? error.message : String(error);
      console.warn(
        '[syncSankhyaProductsModule] fiscal_enrichment_failed',
        JSON.stringify({
          tenantId,
          message: fiscalQueryError,
        }),
      );
    }
  }

  for (const rawItem of validProducts) {
    const erpProductCode = toCodeString(rawItem.codigoProduto);
    const docId = buildProductDocId(tenantId, erpProductCode);
    const docRef = productsCollection.doc(docId);
    const existingDoc = await docRef.get();
    const existingData = existingDoc.exists ? existingDoc.data() || {} : {};
    const nextSyncVersion = readInt(existingData.syncVersion) + 1;
    const internalCode = await resolveInternalProductCode({
      firestore,
      tenantId,
      erpProductCode,
      existingData,
    });
    const productFiscal = productFiscalByCode.get(erpProductCode);
    if (productFiscal) {
      fiscalMatchedCount += 1;
      if (productFiscal.origemMercadoriaCst !== null) {
        fiscalOriginEnrichmentCount += 1;
      }
      if (productFiscal.aliquotaIpiBase !== null) {
        fiscalIpiEnrichmentCount += 1;
      }
      if (
        productFiscal.origemMercadoriaCst !== null ||
        productFiscal.aliquotaIpiBase !== null
      ) {
        fiscalEnrichmentCount += 1;
      }
    }

    const payload = mapSankhyaProductToFirestore({
      tenantId,
      nowIso,
      syncBatchId,
      internalCode,
      source: rawItem,
      productFiscal,
      existingData,
      nextSyncVersion,
      ncmToGroupId,
    });

    await docRef.set(payload, { merge: true });
  }

  await updateTenantSyncState({
    firestore,
    tenantId,
    patch: {
      lastProductsSyncedAt: nowIso,
      lastProductsSyncAt: nowIso,
      lastProductsImportedCount: validProducts.length,
      lastProductsSourceCount: sourceProducts.length,
      lastProductsFilteredOutZeroCodeCount: filteredOutZeroCodeCount,
      lastProductsAppliedLimit: TEMPORARY_IMPORT_LIMIT,
      lastProductsFiscalQueryOk: fiscalQueryOk,
      lastProductsFiscalEndpoint: fiscalQueryEndpoint,
      lastProductsFiscalRowsCount: fiscalQueryRowsCount,
      lastProductsFiscalMatchedCount: fiscalMatchedCount,
      lastProductsFiscalEnrichedCount: fiscalEnrichmentCount,
      lastProductsFiscalOriginEnrichedCount: fiscalOriginEnrichmentCount,
      lastProductsFiscalIpiEnrichedCount: fiscalIpiEnrichmentCount,
      lastProductsFiscalQueryError: fiscalQueryError,
    },
  });

  return {
    message:
      'Sincronizacao de produtos concluida com limite temporario de 5, filtro de codigo 0 e enriquecimento fiscal por SQL.',
    endpoint: SANKHYA_PRODUCTS_PATH,
    sourceStatus: sankhyaResponse.status,
    sourceCount: sourceProducts.length,
    importedCount: validProducts.length,
    filteredOutZeroCodeCount,
    fiscalQueryOk,
    fiscalQueryEndpoint,
    fiscalQueryRowsCount,
    fiscalMatchedCount,
    fiscalEnrichmentCount,
    fiscalOriginEnrichmentCount,
    fiscalIpiEnrichmentCount,
    fiscalQueryError,
    skippedNotFoundCount: 0,
    appliedLimit: TEMPORARY_IMPORT_LIMIT,
  };
}

async function syncSankhyaPriceTablesModule({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
}) {
  const tenantSnapshot = await firestore.collection('tenants').doc(tenantId).get();
  const tenantData = tenantSnapshot.exists ? tenantSnapshot.data() || {} : {};
  const priceTableCodes = normalizePriceTableCodes(
    tenantData?.erpIntegration?.priceTableCodes,
  );

  if (priceTableCodes.length === 0) {
    throw new Error(
      'Nenhum codigo de tabela foi configurado em erpIntegration.priceTableCodes para sincronizar tabelas de preco.',
    );
  }

  const nowIso = new Date().toISOString();
  const primaryTableCode = priceTableCodes[0];
  const defaultPriceTableDocId = buildDefaultPriceTableDocId(tenantId);

  await upsertDefaultPriceTableDocument({
    firestore,
    tenantId,
    defaultPriceTableDocId,
    primaryTableCode,
    nowIso,
  });

  const productIndex = await buildTenantProductIndex({
    firestore,
    tenantId,
  });
  const syncBatchId = `sankhya_precos_${Date.now()}`;
  const pricesCollection = firestore.collection('product_base_prices');

  let sourceCount = 0;
  let importedCount = 0;
  let skippedNotFoundCount = 0;
  let filteredOutZeroCodeCount = 0;
  const incrementalModeActive = false;
  const incrementalFallbackReason = null;
  const incrementalCandidatesCount = 0;
  const incrementalApiLookups = 0;
  const incrementalReadRows = 0;
  const incrementalScannedPages = 0;
  const incrementalScanComplete = true;

  const tableSummaries = [];
  const primaryTablePriceByProductId = new Map();

  const pricesWriter = firestore.bulkWriter();
  pricesWriter.onWriteError((error) => {
    // Retry transient failures a few times before surfacing the error.
    if (error.failedAttempts < 3) {
      return true;
    }
    console.error(
      '[syncSankhyaPriceTablesModule] write_failed',
      JSON.stringify({
        code: error.code,
        message: error.message,
        documentPath: error.documentRef?.path || null,
        failedAttempts: error.failedAttempts,
      }),
    );
    return false;
  });

  try {
    for (const tableCode of priceTableCodes) {
      const priceTableDocId = buildPriceTableDocId(tenantId, tableCode);
      await upsertPriceTableDocument({
        firestore,
        tenantId,
        priceTableDocId,
        tableCode,
        nowIso,
      });

      let page = 1;
      let hasMore = true;
      let tableSourceCount = 0;
      let tableImportedCount = 0;
      const tableUniqueProductIds = new Set();

      while (hasMore) {
        const endpointPath = `/v1/precos/tabela/${encodeURIComponent(
          tableCode,
        )}?pagina=${page}`;
        const url = `${baseUrl}${endpointPath}`;

        const pageResponse = await fetch(url, {
          method: 'GET',
          headers: {
            Accept: 'application/json',
            Authorization: `Bearer ${bearerToken}`,
            'x-token': xToken,
          },
          signal: AbortSignal.timeout(30000),
        });

        const pageText = await pageResponse.text();
        if (pageResponse.status !== 200) {
          throw new Error(
            `Falha ao consultar tabela de preco ${tableCode} (pagina ${page}, HTTP ${pageResponse.status}): ${pageText.slice(0, 300)}`,
          );
        }

        const pageData = tryParseJson(pageText) || {};
        const rows = readPriceRowsFromPayload(pageData);

        sourceCount += rows.length;
        tableSourceCount += rows.length;

        for (const row of rows) {
          const productCode = toCodeString(row?.codigoProduto);
          if (!productCode || isZeroCode(productCode)) {
            filteredOutZeroCodeCount++;
            continue;
          }

          const mappedProduct = productIndex.get(productCode);
          if (!mappedProduct) {
            skippedNotFoundCount++;
            continue;
          }

          const priceValue = toNumberOrNull(row?.valor);
          if (priceValue === null) {
            continue;
          }

          const localCode = toCodeString(row?.codigoLocalEstoque) || '0';
          const unitCode = normalizeTextToken(row?.unidade, 'UN');
          const controlCode = normalizeTextToken(row?.controle, 'SEM_CONTROLE');
          const priceDocId = buildProductBasePriceDocId({
            tenantId,
            tableCode,
            productId: mappedProduct.productId,
            localCode,
            unitCode,
            controlCode,
          });

          const payload = {
            id: priceDocId,
            tenantId,
            productId: mappedProduct.productId,
            priceTableId: priceTableDocId,
            regionId: 'ALL',
            basePrice: priceValue,
            status: 'active',
            currencyCode: 'BRL',
            validFrom: null,
            validUntil: null,
            createdAt: nowIso,
            updatedAt: nowIso,
            origin: 'erp',
            erpSyncId: syncBatchId,
            erpMeta: {
              codigoTabela: tableCode,
              codigoProduto: productCode,
              codigoLocalEstoque: localCode,
              unidade: unitCode,
              controle: controlCode,
            },
          };

          pricesWriter.set(pricesCollection.doc(priceDocId), payload, { merge: true });
          importedCount++;
          tableImportedCount++;
          tableUniqueProductIds.add(mappedProduct.productId);

          if (tableCode === primaryTableCode) {
            if (!primaryTablePriceByProductId.has(mappedProduct.productId)) {
              primaryTablePriceByProductId.set(mappedProduct.productId, priceValue);
            }

            const defaultPriceDocId = buildDefaultProductBasePriceDocId({
              tenantId,
              productId: mappedProduct.productId,
              defaultPriceTableDocId,
            });

            pricesWriter.set(
              pricesCollection.doc(defaultPriceDocId),
              {
                id: defaultPriceDocId,
                tenantId,
                productId: mappedProduct.productId,
                priceTableId: defaultPriceTableDocId,
                regionId: 'default',
                basePrice: priceValue,
                status: 'active',
                currencyCode: 'BRL',
                validFrom: null,
                validUntil: null,
                createdAt: nowIso,
                updatedAt: nowIso,
                origin: 'erp',
                erpSyncId: syncBatchId,
                erpMeta: {
                  codigoTabela: tableCode,
                  codigoProduto: productCode,
                  codigoLocalEstoque: localCode,
                  unidade: unitCode,
                  controle: controlCode,
                },
              },
              { merge: true },
            );
          }
        }

        const rawHasMore = pageData.temMaisRegistros;
        const normalizedHasMore = String(rawHasMore ?? '').toLowerCase();
        const hasMoreFlagKnown =
          rawHasMore === true ||
          rawHasMore === false ||
          normalizedHasMore === 'true' ||
          normalizedHasMore === 'false';
        const hasMoreByFlag =
          rawHasMore === true ||
          normalizedHasMore === 'true';
        hasMore = hasMoreFlagKnown ? hasMoreByFlag : rows.length > 0;
        page += 1;
        if (page > 1000) {
          throw new Error(
            `Limite de paginas excedido ao consultar tabela ${tableCode}.`,
          );
        }
      }

      await firestore.collection('tabelas_preco').doc(priceTableDocId).set(
        {
          rowCount: tableUniqueProductIds.size,
          updatedAt: nowIso,
        },
        { merge: true },
      );

      tableSummaries.push({
        codigoTabela: tableCode,
        sourceCount: tableSourceCount,
        importedCount: tableImportedCount,
        uniqueProductCount: tableUniqueProductIds.size,
        mode: 'full',
      });
    }

    if (primaryTablePriceByProductId.size > 0) {
      for (const [productId, priceValue] of primaryTablePriceByProductId.entries()) {
        pricesWriter.set(
          firestore.collection('produtos').doc(productId),
          {
            valorBruto: priceValue,
            moeda: 'BRL',
            erpSyncId: syncBatchId,
            updatedAt: nowIso,
          },
          { merge: true },
        );
      }
    }
  } finally {
    await pricesWriter.close();
  }

  await firestore.collection('tabelas_preco').doc(defaultPriceTableDocId).set(
    {
      rowCount: primaryTablePriceByProductId.size,
      updatedAt: nowIso,
    },
    { merge: true },
  );

  await updateTenantSyncState({
    firestore,
    tenantId,
    patch: {
      lastPriceSyncAt: nowIso,
      lastPriceSyncMode: 'full',
      lastPriceSyncFallbackReason: incrementalFallbackReason,
      lastPriceSyncCandidatesCount: incrementalCandidatesCount,
      lastPriceSyncApiLookups: incrementalApiLookups,
      lastPriceSyncReadRows: sourceCount,
      lastPriceSyncScannedProductPages: incrementalScannedPages,
      lastPriceSyncProductScanComplete: incrementalScanComplete,
      lastPriceSyncImportedCount: importedCount,
    },
  });

  return {
    message:
      'Sincronizacao de tabelas de preco concluida. Apenas produtos ja cadastrados no SaaS receberam preco.',
    endpoint: '/v1/precos/tabela/{codigoTabela}?pagina=N',
    sourceCount,
    importedCount,
    filteredOutZeroCodeCount,
    skippedNotFoundCount,
    primaryTableCode,
    mirroredDefaultPriceCount: primaryTablePriceByProductId.size,
    appliedPriceTableCodes: priceTableCodes,
    incrementalMode: incrementalModeActive,
    incrementalFallbackReason,
    incrementalCandidatesCount,
    incrementalApiLookups,
    incrementalReadRows,
    incrementalScannedProductPages: incrementalScannedPages,
    incrementalScanComplete,
    tableSummaries,
  };
}

function normalizePriceTableCodes(raw) {
  const tokens = [];
  if (Array.isArray(raw)) {
    for (const item of raw) {
      tokens.push(String(item ?? ''));
    }
  } else if (typeof raw === 'string') {
    tokens.push(...raw.split(/[\s,;|]+/));
  }

  const normalized = [];
  const seen = new Set();
  for (const token of tokens) {
    const clean = String(token ?? '').trim();
    if (!clean || !/^\d+$/.test(clean)) {
      continue;
    }
    if (seen.has(clean)) {
      continue;
    }
    seen.add(clean);
    normalized.push(clean);
  }
  return normalized;
}

async function buildTenantProductIndex({ firestore, tenantId }) {
  const snapshot = await firestore
    .collection('produtos')
    .where('tenantId', '==', tenantId)
    .select('erpProductId', 'codigoFabricante', 'deletedAt')
    .get();

  const index = new Map();
  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    if (data.deletedAt) {
      continue;
    }

    const keys = [
      toCodeString(data.erpProductId),
      toCodeString(data.codigoFabricante),
    ];

    for (const key of keys) {
      if (!key || isZeroCode(key)) {
        continue;
      }
      if (!index.has(key)) {
        index.set(key, {
          productId: doc.id,
        });
      }
    }
  }

  return index;
}

async function upsertPriceTableDocument({
  firestore,
  tenantId,
  priceTableDocId,
  tableCode,
  nowIso,
}) {
  const docRef = firestore.collection('tabelas_preco').doc(priceTableDocId);
  const snapshot = await docRef.get();
  const existing = snapshot.exists ? snapshot.data() || {} : {};

  await docRef.set(
    {
      id: priceTableDocId,
      tenantId,
      nome: existing.nome || `Tabela Sankhya ${tableCode}`,
      scopeType: existing.scopeType || 'general',
      scopeLabel: existing.scopeLabel || `Sankhya CODTAB ${tableCode}`,
      scopeIndex: existing.scopeIndex || [`sankhya`, `codtab_${tableCode}`],
      origem: 'erp',
      status: 'ativo',
      linkedEntityId: existing.linkedEntityId || null,
      createdAt: existing.createdAt || nowIso,
      updatedAt: nowIso,
    },
    { merge: true },
  );
}

async function upsertDefaultPriceTableDocument({
  firestore,
  tenantId,
  defaultPriceTableDocId,
  primaryTableCode,
  nowIso,
}) {
  const docRef = firestore.collection('tabelas_preco').doc(defaultPriceTableDocId);
  const snapshot = await docRef.get();
  const existing = snapshot.exists ? snapshot.data() || {} : {};

  await docRef.set(
    {
      id: defaultPriceTableDocId,
      tenantId,
      nome: existing.nome || 'Tabela padrao',
      scopeType: existing.scopeType || 'general',
      scopeLabel:
        existing.scopeLabel || `Tabela padrao vinculada ao Sankhya CODTAB ${primaryTableCode}`,
      scopeIndex: existing.scopeIndex || ['default', 'tenant_default'],
      origem: existing.origem || 'system',
      status: existing.status || 'ativo',
      linkedEntityId: existing.linkedEntityId || null,
      createdAt: existing.createdAt || nowIso,
      updatedAt: nowIso,
    },
    { merge: true },
  );

  await firestore.collection('tenants').doc(tenantId).set(
    {
      defaultPriceTableIds: { tenant_default: defaultPriceTableDocId },
      defaultPriceRegionIds: { tenant_default: 'default' },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function readPriceRowsFromPayload(payload) {
  if (Array.isArray(payload?.produtos)) {
    return payload.produtos;
  }
  if (Array.isArray(payload?.precos)) {
    return payload.precos;
  }
  return [];
}

function buildPriceTableDocId(tenantId, tableCode) {
  return `erp_pt_${tenantId}_${toCodeString(tableCode)}`;
}

function buildDefaultPriceTableDocId(tenantId) {
  return `pt_default_${tenantId}`;
}

function buildDefaultProductBasePriceDocId({
  tenantId,
  productId,
  defaultPriceTableDocId,
}) {
  return `pbp_${tenantId}_${productId}_${defaultPriceTableDocId}`;
}

function normalizeTextToken(value, fallback) {
  const raw = String(value ?? '').trim();
  if (!raw) {
    return fallback;
  }
  const normalized = raw
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^A-Za-z0-9_-]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return normalized || fallback;
}

function buildProductBasePriceDocId({
  tenantId,
  tableCode,
  productId,
  localCode,
  unitCode,
  controlCode,
}) {
  return [
    'erp_pbp',
    tenantId,
    toCodeString(tableCode),
    productId,
    normalizeTextToken(localCode, '0'),
    normalizeTextToken(unitCode, 'UN'),
    normalizeTextToken(controlCode, 'SEM_CONTROLE'),
  ].join('_');
}

function mapSankhyaProductToFirestore({
  tenantId,
  nowIso,
  syncBatchId,
  internalCode,
  source,
  productFiscal,
  existingData,
  nextSyncVersion,
  ncmToGroupId,
}) {
  const code = toCodeString(source.codigoProduto);
  const name = String(source.nome ?? '').trim();
  const groupName = String(source.nomeGrupoProduto ?? '').trim();
  const volume = String(source.volume ?? '').trim();
  const brand = String(source.marca ?? '').trim();
  const ncmRaw = String(source.ncm ?? '').trim();
  const cestRaw = String(source.cest ?? '').trim();
  const eanRaw = String(source.referencia ?? '').trim();
  const origemMercadoriaCst = normalizeOrigemMercadoriaCst(
    productFiscal?.origemMercadoriaCst ?? existingData.origemMercadoriaCst,
  );
  const aliquotaIpiBase = toNumberOrNull(
    productFiscal?.aliquotaIpiBase ?? existingData.aliquotaIpiBase,
  );
  const ncmDigits = normalizeDigits(ncmRaw);
  const grupoTributarioId =
    (ncmDigits ? ncmToGroupId?.get(ncmDigits) : null) ??
    existingData.grupoTributarioId ??
    null;

  return {
    id: buildProductDocId(tenantId, code),
    tenantId,
    representedCompanyId: existingData.representedCompanyId ?? null,
    codigoInterno: internalCode,
    descricao: name || `Produto ${code}`,
    descricaoResumida: name || null,
    descricaoLonga: String(source.complemento ?? '').trim() || null,
    codigoFabricante: code,
    ean: eanRaw || null,
    marca: brand || null,
    categoria: groupName || null,
    unidade: volume || null,
    ncm: ncmRaw || null,
    cest: cestRaw || null,
    grupoTributarioId,
    origemMercadoriaCst,
    aliquotaIpiBase,
    pesoKg: toNumberOrNull(source.pesoBruto),
    larguraMm: toNumberOrNull(source.largura),
    alturaMm: toNumberOrNull(source.altura),
    comprimentoMm: toNumberOrNull(source.espessura),
    origemCadastro: 'erp',
    status: source.ativo === false ? 'inativo' : 'ativo',
    erpProductId: code,
    erpSyncId: syncBatchId,
    updatedAt: nowIso,
    createdAt: existingData.createdAt || nowIso,
    deletedAt: null,
    syncVersion: nextSyncVersion,
  };
}

async function resolveInternalProductCode({
  firestore,
  tenantId,
  erpProductCode,
  existingData,
}) {
  const currentInternalCode = String(existingData.codigoInterno ?? '').trim();
  if (currentInternalCode && currentInternalCode !== erpProductCode) {
    return currentInternalCode;
  }

  const sequence = await nextTenantErpProductInternalSequence({
    firestore,
    tenantId,
  });
  return `ERP-${String(sequence).padStart(6, '0')}`;
}

async function nextTenantErpProductInternalSequence({ firestore, tenantId }) {
  const tenantRef = firestore.collection('tenants').doc(tenantId);
  return firestore.runTransaction(async (transaction) => {
    const tenantSnapshot = await transaction.get(tenantRef);
    const current = readInt(tenantSnapshot.data()?.erpInternalProductSequence);
    const next = current + 1;
    transaction.set(
      tenantRef,
      {
        erpInternalProductSequence: next,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return next;
  });
}

function buildProductDocId(tenantId, productCode) {
  return `erp_prod_${tenantId}_${toCodeString(productCode)}`;
}

function toCodeString(value) {
  if (value === null || value === undefined) {
    return '';
  }

  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      return '';
    }
    return String(Math.trunc(value));
  }

  return String(value).trim();
}

function isZeroCode(codeValue) {
  const normalized = String(codeValue ?? '').trim();
  if (!normalized) {
    return true;
  }

  const numeric = Number(normalized.replace(',', '.'));
  if (Number.isFinite(numeric) && numeric === 0) {
    return true;
  }

  return /^0+$/.test(normalized);
}

function toNumberOrNull(value) {
  if (value === null || value === undefined || value === '') {
    return null;
  }

  const numeric = Number(String(value).replace(',', '.'));
  return Number.isFinite(numeric) ? numeric : null;
}

function readInt(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }

  if (typeof value === 'string') {
    const parsed = Number.parseInt(value.trim(), 10);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  return 0;
}

function tryParseJson(text) {
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

async function fetchSankhyaProductsFiscalData({
  baseUrl,
  bearerToken,
  xToken,
  productCodes,
}) {
  const normalizedCodes = normalizeSankhyaNumericCodeList(productCodes);
  if (normalizedCodes.length === 0) {
    return {
      endpointPath: null,
      rowCount: 0,
      byProductCode: new Map(),
    };
  }

  const sql = buildSankhyaProductFiscalSql(normalizedCodes);
  const queryResult = await executeSankhyaDbExplorerQuery({
    baseUrl,
    bearerToken,
    xToken,
    sql,
  });

  const byProductCode = new Map();
  for (const row of queryResult.rows) {
    const productCode = toCodeString(
      readRowValueByAliases(row, [
        'CodigoProduto',
        'CODIGOPRODUTO',
        'CODPROD',
      ]),
    );
    if (!productCode || isZeroCode(productCode)) {
      continue;
    }

    const origemMercadoriaCst = normalizeOrigemMercadoriaCst(
      readRowValueByAliases(row, [
        'OrigemMercadoria',
        'ORIGEMMERCADORIA',
        'ORIGPROD',
      ]),
    );
    const aliquotaIpiBase = toNumberOrNull(
      readRowValueByAliases(row, [
        'AliquotaIPI',
        'ALIQUOTAIPI',
        'PERCENTUAL',
        'IPI',
      ]),
    );

    byProductCode.set(productCode, {
      origemMercadoriaCst,
      aliquotaIpiBase,
    });
  }

  return {
    endpointPath: queryResult.endpointPath,
    rowCount: queryResult.rows.length,
    byProductCode,
  };
}

function buildSankhyaProductFiscalSql(productCodes) {
  const safeCodes = normalizeSankhyaNumericCodeList(productCodes);
  if (safeCodes.length === 0) {
    return '';
  }

  const codesInClause = safeCodes.join(', ');
  return `
SELECT
    TO_CHAR(PRO.CODPROD) AS CodigoProduto,
    NVL(TO_CHAR(PRO.ORIGPROD), '0') AS OrigemMercadoria,
    COALESCE(
        IPI_ESPECIFICO.PERCENTUAL,
        TO_NUMBER(REPLACE(NCM.IPI, ',', '.')),
        0
    ) AS AliquotaIPI
FROM TGFPRO PRO
LEFT JOIN TGFIPI IPI_ESPECIFICO ON PRO.CODIPI = IPI_ESPECIFICO.CODIPI
LEFT JOIN TGFNCM NCM ON LTRIM(REPLACE(NCM.CODNCM, '.', ''), '0') = LTRIM(REPLACE(PRO.NCM, '.', ''), '0')
WHERE PRO.ATIVO = 'S'
  AND PRO.CODPROD IN (${codesInClause})
`.trim();
}

async function executeSankhyaDbExplorerQuery({
  baseUrl,
  bearerToken,
  xToken,
  sql,
}) {
  const payloadVariants = [
    {
      name: 'serviceName_requestBody_sql',
      payload: {
        serviceName: 'DbExplorerSP.executeQuery',
        requestBody: { sql },
      },
    },
    {
      name: 'requestBody_sql',
      payload: {
        requestBody: { sql },
      },
    },
    {
      name: 'requestBody_query',
      payload: {
        requestBody: { query: sql },
      },
    },
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
    .map(
      (item) =>
        `${item.endpointPath} [${item.payloadVariant}] -> HTTP ${item.status}: ${item.bodyPreview}`,
    )
    .join(' | ')
    .slice(0, 1800);

  throw new Error(`DbExplorer executeQuery falhou. Tentativas: ${details}`);
}

function normalizeDbExplorerRows(payload) {
  if (!payload || typeof payload !== 'object') {
    return [];
  }

  const root = payload.responseBody && typeof payload.responseBody === 'object'
    ? payload.responseBody
    : payload;
  const rawRows = Array.isArray(root.rows) ? root.rows : [];
  if (rawRows.length === 0) {
    return [];
  }

  if (
    rawRows.every(
      (row) => row && typeof row === 'object' && !Array.isArray(row),
    )
  ) {
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

function readRowValueByAliases(row, aliases) {
  if (!row || typeof row !== 'object') {
    return undefined;
  }

  for (const alias of aliases) {
    if (Object.prototype.hasOwnProperty.call(row, alias)) {
      return row[alias];
    }
  }

  const loweredMap = new Map(
    Object.entries(row).map(([key, value]) => [key.toLowerCase(), value]),
  );
  for (const alias of aliases) {
    const value = loweredMap.get(String(alias).toLowerCase());
    if (value !== undefined) {
      return value;
    }
  }

  return undefined;
}

function normalizeOrigemMercadoriaCst(value) {
  const normalized = String(value ?? '').trim();
  if (!normalized) {
    return null;
  }
  const parsed = Number.parseInt(normalized, 10);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 8) {
    return null;
  }
  return String(parsed);
}

function normalizeSankhyaNumericCodeList(values) {
  const normalized = [];
  const seen = new Set();
  for (const value of values) {
    const token = String(value ?? '').trim();
    if (!/^\d+$/.test(token)) {
      continue;
    }
    if (isZeroCode(token)) {
      continue;
    }
    const clean = String(Number.parseInt(token, 10));
    if (!clean || seen.has(clean)) {
      continue;
    }
    seen.add(clean);
    normalized.push(clean);
  }
  return normalized;
}

async function syncSankhyaTaxRulesModule({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
}) {
  const nowIso = new Date().toISOString();
  const syncBatchId = `sankhya_tax_${Date.now()}`;
  const sql = buildSankhyaTaxRulesSql();
  const queryResult = await executeSankhyaDbExplorerQuery({
    baseUrl,
    bearerToken,
    xToken,
    sql,
  });

  // Passo 1: mapeia todas as linhas em memoria (descarta linhas invalidas ou
  // excecoes por NCM sem nenhum valor fiscal real - ver mapSankhyaTaxRuleRow).
  const syncVersionBase = Date.now() * 1000;
  const mappedRows = [];
  let skippedInvalidCount = 0;
  for (let index = 0; index < queryResult.rows.length; index++) {
    const row = queryResult.rows[index];
    const mapped = mapSankhyaTaxRuleRow({
      tenantId,
      row,
      nowIso,
      syncBatchId,
      syncVersion: syncVersionBase + index,
    });
    if (!mapped) {
      skippedInvalidCount += 1;
      continue;
    }
    mappedRows.push(mapped);
  }

  // Passo 2: separa regras genericas por UF (sem NCM - tier 3 do motor) das
  // regras por NCM, e agrupa os NCMs com perfil fiscal identico (fingerprint)
  // em Grupos Tributarios automaticos.
  const genericRows = [];
  const ncmVectorMap = new Map();
  for (const mapped of mappedRows) {
    const ncmDigits = normalizeDigits(mapped.ncm);
    if (!ncmDigits) {
      genericRows.push(mapped);
      continue;
    }
    if (!ncmVectorMap.has(ncmDigits)) {
      ncmVectorMap.set(ncmDigits, []);
    }
    ncmVectorMap.get(ncmDigits).push(mapped);
  }

  const clustersByHash = new Map();
  for (const [ncmDigits, vectorRows] of ncmVectorMap.entries()) {
    const hash = computeFingerprintHash(buildTaxFingerprintKey(vectorRows));
    if (!clustersByHash.has(hash)) {
      clustersByHash.set(hash, { ncmDigitsList: [], vectorRows });
    }
    clustersByHash.get(hash).ncmDigitsList.push(ncmDigits);
  }

  const groupedNcmDigits = new Set();
  const ncmToGroupId = new Map();
  const groupDocsToUpsert = [];
  const groupRuleDocs = [];
  for (const cluster of clustersByHash.values()) {
    if (cluster.ncmDigitsList.length < 2) {
      continue;
    }
    const hash = computeFingerprintHash(
      buildTaxFingerprintKey(cluster.vectorRows),
    );
    const groupId = `erp_group_${tenantId}_${hash}`;
    const memberNcms = cluster.ncmDigitsList.slice().sort();
    for (const ncmDigits of memberNcms) {
      groupedNcmDigits.add(ncmDigits);
      ncmToGroupId.set(ncmDigits, groupId);
    }
    groupDocsToUpsert.push({
      groupId,
      hash,
      memberNcms,
      vectorRows: cluster.vectorRows,
    });
    for (const vectorRow of cluster.vectorRows) {
      const ruleId = `erp_taxgroup_${tenantId}_${hash}_${sanitizeKeyToken(vectorRow.ufOrigem, 'ANY')}_${sanitizeKeyToken(vectorRow.ufDestino, 'ANY')}`;
      groupRuleDocs.push({
        ...vectorRow,
        id: ruleId,
        ncm: null,
        cest: null,
        taxGroupId: groupId,
      });
    }
  }

  const taxRulesCollection = firestore.collection('tax_rules');
  const taxRuleGroupsCollection = firestore.collection('tax_rule_groups');
  const writer = firestore.bulkWriter();
  writer.onWriteError((error) => {
    if (error.failedAttempts < 3) {
      return true;
    }
    console.error(
      '[syncSankhyaTaxRulesModule] write_failed',
      JSON.stringify({
        code: error.code,
        message: error.message,
        documentPath: error.documentRef?.path || null,
        failedAttempts: error.failedAttempts,
      }),
    );
    return false;
  });

  let importedCount = 0;
  let importedMissingCestCount = 0;
  let prunedStaleRuleCount = 0;
  const mappedRuleIds = new Set();

  try {
    const writeRule = (ruleDoc) => {
      mappedRuleIds.add(ruleDoc.id);
      writer.set(taxRulesCollection.doc(ruleDoc.id), ruleDoc, { merge: true });
      importedCount += 1;
      if (!ruleDoc.cest) {
        importedMissingCestCount += 1;
      }
    };

    for (const mapped of genericRows) {
      writeRule(mapped);
    }
    for (const [ncmDigits, vectorRows] of ncmVectorMap.entries()) {
      if (groupedNcmDigits.has(ncmDigits)) {
        continue;
      }
      for (const mapped of vectorRows) {
        writeRule(mapped);
      }
    }
    for (const ruleDoc of groupRuleDocs) {
      writeRule(ruleDoc);
    }

    for (const groupDoc of groupDocsToUpsert) {
      const ref = taxRuleGroupsCollection.doc(groupDoc.groupId);
      const existingSnapshot = await ref.get();
      const existing = existingSnapshot.exists
        ? existingSnapshot.data() || {}
        : {};
      const isAutoName = existing.autoGenerated !== false;
      const autoName = buildAutoGroupName(
        groupDoc.vectorRows,
        groupDoc.memberNcms.length,
      );
      const name = isAutoName ? autoName : existing.name || autoName;
      writer.set(
        ref,
        {
          id: groupDoc.groupId,
          tenantId,
          representedCompanyId: null,
          status: existing.status || 'active',
          source: 'erp_sync',
          erpProvider: 'sankhya',
          externalCode: groupDoc.hash,
          fingerprint: groupDoc.hash,
          memberNcms: groupDoc.memberNcms,
          memberNcmCount: groupDoc.memberNcms.length,
          priority: existing.priority ?? 0,
          autoGenerated: existing.autoGenerated ?? true,
          name,
          normalizedName: name.trim().toLowerCase(),
          description:
            existing.description ||
            buildAutoGroupDescription(groupDoc.vectorRows, groupDoc.memberNcms),
          createdAt: existing.createdAt || nowIso,
          updatedAt: nowIso,
          erpSyncId: syncBatchId,
        },
        { merge: true },
      );
    }

    const existingSnapshot = await taxRulesCollection
      .where('tenantId', '==', tenantId)
      .get();
    for (const doc of existingSnapshot.docs) {
      const payload = doc.data() || {};
      const origin = String(payload.origin ?? '').trim().toLowerCase();
      if (origin !== 'erp') {
        continue;
      }

      const representedScope = String(payload.representedCompanyId ?? '').trim();
      if (representedScope) {
        continue;
      }

      if (mappedRuleIds.has(doc.id)) {
        continue;
      }

      writer.delete(doc.ref);
      prunedStaleRuleCount += 1;
    }
  } finally {
    await writer.close();
  }

  let productsGroupLinkedCount = 0;
  if (ncmToGroupId.size > 0) {
    productsGroupLinkedCount = await applyTaxGroupsToExistingProducts({
      firestore,
      tenantId,
      ncmToGroupId,
    });
  }

  await updateTenantSyncState({
    firestore,
    tenantId,
    patch: {
      lastTaxRulesSyncAt: nowIso,
      lastTaxRulesSyncMode: 'full',
      lastTaxRulesSourceCount: queryResult.rows.length,
      lastTaxRulesImportedCount: importedCount,
      lastTaxRulesSkippedInvalidCount: skippedInvalidCount,
      lastTaxRulesImportedMissingCestCount: importedMissingCestCount,
      lastTaxRulesPrunedStaleRuleCount: prunedStaleRuleCount,
      lastTaxRulesGroupsCreatedCount: groupDocsToUpsert.length,
      lastTaxRulesGroupedNcmCount: groupedNcmDigits.size,
      lastTaxRulesProductsGroupLinkedCount: productsGroupLinkedCount,
      lastTaxRulesEndpoint: queryResult.endpointPath,
    },
  });

  return {
    message:
      'Sincronizacao completa de tax_rules concluida via SQL DbExplorer, com agrupamento automatico de grupos tributarios.',
    endpoint: queryResult.endpointPath,
    sourceCount: queryResult.rows.length,
    importedCount,
    skippedInvalidCount,
    importedMissingCestCount,
    prunedStaleRuleCount,
    groupsCreatedCount: groupDocsToUpsert.length,
    groupedNcmCount: groupedNcmDigits.size,
    productsGroupLinkedCount,
    filteredOutZeroCodeCount: 0,
    skippedNotFoundCount: 0,
    mirroredRuleCount: mappedRuleIds.size,
  };
}

function buildClienteDocId(tenantId, codigoParceiro) {
  return `erp_cliente_${tenantId}_${toCodeString(codigoParceiro)}`;
}

// Mantido em paridade com `defaultTaxRegime` de lib/src/core/models/domain_types.dart.
// TGFPAR nao possui coluna de regime tributario do parceiro; usado apenas
// como fallback quando o documento ainda nao tem valor definido manualmente.
const SANKHYA_DEFAULT_TAX_REGIME = 'simples_nacional';

// Sync de clientes/parceiros Sankhya (TGFPAR) para a colecao `clientes`. UF e
// resolvida via TGFPAR.CODCID -> TSICID.UF (codigo numerico) -> TSIUFS.UF
// (sigla), mesmo join ja usado em tax_rules. CLASSIFICMS ("Classificacao
// ICMS" no cadastro de parceiros do Sankhya) tem 6 opcoes na tela (Revendedor,
// Produtor Rural, Consumidor Final Nao Contribuinte, Usar a da TOP, Isento de
// ICMS, Consumidor Final Contribuinte). Letras confirmadas empiricamente
// 2026-10-27 alterando o mesmo cliente de teste (191, CODPARC com IE valida)
// entre as 6 opcoes na tela do Sankhya e conferindo `erpClassificmsRaw` apos
// cada resync: R=Revendedor (contribuinte), P=Produtor Rural (contribuinte),
// T=Usar a da TOP (sem classificacao fixa, cai no fallback por IE), C=
// Consumidor Final NAO Contribuinte (a letra sugere o contrario, mas foi
// confirmado pela tela do Sankhya para o cliente 1887, IE nula), X=
// Consumidor Final Contribuinte (a letra 'C' ja estava ocupada por outra
// opcao, entao o Sankhya usa 'X' aqui). I=Isento de ICMS (nao contribuinte,
// validado com o cliente 1231, IE nula). 'N' nunca foi observado neste tenant
// (nao ha clientes produtor/consumidor final nao-PJ com essa letra), mas
// mantido no set nao_contribuinte por seguranca caso apareca futuramente -
// nao deve ser confundido com 'C', que e a letra realmente usada para o caso
// "Nao Contribuinte" nesta instalacao. Qualquer codigo nao mapeado
// (null/T/desconhecido) cai no fallback por Inscricao Estadual valida.
// taxRegime nao tem coluna correspondente em TGFPAR e permanece com o valor
// existente/manual.
const SANKHYA_CLASSIFICMS_CONTRIBUINTE_CODES = new Set(['R', 'P', 'X']);
const SANKHYA_CLASSIFICMS_NAO_CONTRIBUINTE_CODES = new Set(['C', 'I', 'N']);

function buildSankhyaClientesSql({ codigosFiltro } = {}) {
  const safeCodes = normalizeSankhyaNumericCodeList(codigosFiltro ?? []);
  const filtroCodigo =
    safeCodes.length > 0 ? `\n  AND PAR.CODPARC IN (${safeCodes.join(', ')})` : '';

  return `
SELECT
    TO_CHAR(PAR.CODPARC) AS CODPARC,
    PAR.NOMEPARC,
    PAR.RAZAOSOCIAL,
    PAR.CGC_CPF,
    PAR.TIPPESSOA,
    PAR.ATIVO,
    PAR.IDENTINSCESTAD,
    PAR.INSCMUN,
    PAR.CLASSIFICMS,
    PAR.CEP,
    PAR.NUMEND,
    PAR.COMPLEMENTO,
    PAR.TELEFONE,
    PAR.EMAIL,
    CID.NOMECID,
    UFS.UF AS SIGLA_UF
FROM TGFPAR PAR
LEFT JOIN TSICID CID ON CID.CODCID = PAR.CODCID
LEFT JOIN TSIUFS UFS ON UFS.CODUF = CID.UF
WHERE PAR.CLIENTE = 'S'${filtroCodigo}
`;
}

function mapSankhyaClienteRow({
  tenantId,
  row,
  nowIso,
  syncBatchId,
  syncVersion,
  existingData,
}) {
  const existing = existingData || {};
  const codigo = toCodeString(readRowValueByAliases(row, ['CODPARC']));
  if (!codigo || isZeroCode(codigo)) {
    return null;
  }

  const razaoSocial = String(
    readRowValueByAliases(row, ['RAZAOSOCIAL']) ?? '',
  ).trim();
  const nomeFantasia = String(
    readRowValueByAliases(row, ['NOMEPARC']) ?? '',
  ).trim();
  const documento = normalizeDigits(readRowValueByAliases(row, ['CGC_CPF']));
  const tipPessoaRaw = String(readRowValueByAliases(row, ['TIPPESSOA']) ?? '')
    .trim()
    .toUpperCase();
  const ativoRaw = String(readRowValueByAliases(row, ['ATIVO']) ?? '')
    .trim()
    .toUpperCase();
  const inscricaoEstadualRaw = String(
    readRowValueByAliases(row, ['IDENTINSCESTAD']) ?? '',
  ).trim();
  const classificmsRaw =
    nullableString(readRowValueByAliases(row, ['CLASSIFICMS']))?.toUpperCase() ??
    null;
  const inscricaoEstadualUpper = inscricaoEstadualRaw.toUpperCase();
  const hasValidIe =
    inscricaoEstadualUpper.length > 0 && inscricaoEstadualUpper !== 'ISENTO';

  let taxProfile;
  if (SANKHYA_CLASSIFICMS_CONTRIBUINTE_CODES.has(classificmsRaw)) {
    taxProfile = 'contribuinte';
  } else if (SANKHYA_CLASSIFICMS_NAO_CONTRIBUINTE_CODES.has(classificmsRaw)) {
    taxProfile = 'nao_contribuinte';
  } else {
    taxProfile = hasValidIe ? 'contribuinte' : 'nao_contribuinte';
  }

  let salePurposeFromClassificms = null;
  if (classificmsRaw === 'R') {
    salePurposeFromClassificms = 'revenda';
  } else if (
    classificmsRaw === 'C' ||
    classificmsRaw === 'N' ||
    classificmsRaw === 'X'
  ) {
    salePurposeFromClassificms = 'uso_consumo';
  }

  return {
    id: buildClienteDocId(tenantId, codigo),
    tenantId,
    representedCompanyId: existing.representedCompanyId ?? null,
    ownerId: existing.ownerId ?? null,
    gerenteId: existing.gerenteId ?? null,
    representanteId: existing.representanteId ?? null,
    vendedorId: existing.vendedorId ?? null,
    nome: razaoSocial || nomeFantasia || `Cliente ${codigo}`,
    nomeFantasia: nullableString(nomeFantasia),
    documento: nullableString(documento),
    tipoPessoa: tipPessoaRaw === 'F' ? 'pf' : 'pj',
    cep: nullableString(normalizeDigits(readRowValueByAliases(row, ['CEP']))),
    numero: nullableString(readRowValueByAliases(row, ['NUMEND'])),
    complemento: nullableString(readRowValueByAliases(row, ['COMPLEMENTO'])),
    cidade: nullableString(readRowValueByAliases(row, ['NOMECID'])),
    estado: nullableString(
      String(readRowValueByAliases(row, ['SIGLA_UF']) ?? '')
        .trim()
        .toUpperCase(),
    ),
    logradouro: existing.logradouro ?? null,
    bairro: existing.bairro ?? null,
    telefone: nullableString(readRowValueByAliases(row, ['TELEFONE'])),
    email: nullableString(readRowValueByAliases(row, ['EMAIL'])),
    inscricaoEstadual: nullableString(inscricaoEstadualRaw),
    inscricaoMunicipal: nullableString(
      readRowValueByAliases(row, ['INSCMUN']),
    ),
    taxProfile,
    taxRegime: existing.taxRegime || SANKHYA_DEFAULT_TAX_REGIME,
    isZfmSuframa: existing.isZfmSuframa ?? false,
    salePurpose: salePurposeFromClassificms || existing.salePurpose || 'revenda',
    origemCadastro: 'erp',
    // Sankhya e a fonte da verdade quando a integracao esta ativa: um cliente
    // ativo no ERP e gravado direto como 'aprovado' (nao 'sincronizado'), sem
    // exigir aprovacao manual no app - do contrario ele nunca aparece no
    // seletor de cliente da tela de pedido, que so lista status 'aprovado'.
    status: ativoRaw === 'S' ? 'aprovado' : 'inativo',
    erpClassificmsRaw: classificmsRaw,
    erpSyncId: syncBatchId,
    createdAt: existing.createdAt || nowIso,
    updatedAt: nowIso,
    deletedAt: null,
    syncVersion,
  };
}

// Mesma API publica (BrasilAPI) ja usada no app Flutter para preencher
// logradouro/bairro a partir do CEP (ver cliente_pre_cadastro_page.dart). Nao
// e relevante para o calculo fiscal, so para completar o cadastro de
// endereco; falhas sao toleradas silenciosamente (o campo so fica vazio).
async function lookupCepAddress(cep) {
  try {
    const response = await fetch(`https://brasilapi.com.br/api/cep/v2/${cep}`);
    if (!response.ok) {
      return null;
    }
    const data = await response.json();
    return {
      logradouro: nullableString(data?.street),
      bairro: nullableString(data?.neighborhood),
    };
  } catch (error) {
    console.error(
      '[lookupCepAddress] failed',
      JSON.stringify({ cep, message: error?.message }),
    );
    return null;
  }
}

async function syncSankhyaClientesModule({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
  codigosFiltro,
}) {
  const nowIso = new Date().toISOString();
  const syncBatchId = `sankhya_clientes_${Date.now()}`;
  const sql = buildSankhyaClientesSql({ codigosFiltro });
  const queryResult = await executeSankhyaDbExplorerQuery({
    baseUrl,
    bearerToken,
    xToken,
    sql,
  });

  const clientesCollection = firestore.collection('clientes');
  const writer = firestore.bulkWriter();
  writer.onWriteError((error) => {
    if (error.failedAttempts < 3) {
      return true;
    }
    console.error(
      '[syncSankhyaClientesModule] write_failed',
      JSON.stringify({
        code: error.code,
        message: error.message,
        documentPath: error.documentRef?.path || null,
        failedAttempts: error.failedAttempts,
      }),
    );
    return false;
  });

  const syncVersionBase = Date.now() * 1000;
  let importedCount = 0;
  let skippedInvalidCount = 0;
  let prunedInactiveCount = 0;
  const cepCache = new Map();
  const mappedClienteIds = new Set();
  const isFullSync = !codigosFiltro || codigosFiltro.length === 0;

  try {
    for (let index = 0; index < queryResult.rows.length; index++) {
      const row = queryResult.rows[index];
      const docId = buildClienteDocId(
        tenantId,
        readRowValueByAliases(row, ['CODPARC']),
      );
      const ref = clientesCollection.doc(docId);
      const existingSnapshot = await ref.get();
      const existingData = existingSnapshot.exists
        ? existingSnapshot.data() || {}
        : {};

      const mapped = mapSankhyaClienteRow({
        tenantId,
        row,
        nowIso,
        syncBatchId,
        syncVersion: syncVersionBase + index,
        existingData,
      });

      if (!mapped) {
        skippedInvalidCount += 1;
        continue;
      }

      if (mapped.cep && !mapped.logradouro) {
        if (!cepCache.has(mapped.cep)) {
          cepCache.set(mapped.cep, await lookupCepAddress(mapped.cep));
        }
        const cepInfo = cepCache.get(mapped.cep);
        if (cepInfo) {
          mapped.logradouro = mapped.logradouro || cepInfo.logradouro;
          mapped.bairro = mapped.bairro || cepInfo.bairro;
        }
      }

      writer.set(ref, mapped, { merge: true });
      mappedClienteIds.add(docId);
      importedCount += 1;
    }

    // Prune: so roda em sync completo (sem codigosFiltro), nunca em teste
    // restrito a poucos codigos - do contrario qualquer cliente ERP fora do
    // filtro de teste seria incorretamente marcado como inativo. Clientes ERP
    // que deixaram de aparecer na consulta completa do Sankhya sao apenas
    // marcados como 'inativo' no Firestore (soft, nunca excluidos), pois
    // Sankhya e a fonte da verdade de quem esta ativo/existe no ERP.
    if (isFullSync) {
      const existingErpSnapshot = await clientesCollection
        .where('tenantId', '==', tenantId)
        .where('origemCadastro', '==', 'erp')
        .get();
      for (const doc of existingErpSnapshot.docs) {
        if (mappedClienteIds.has(doc.id)) {
          continue;
        }
        const payload = doc.data() || {};
        if (payload.status === 'inativo') {
          continue;
        }
        writer.set(
          doc.ref,
          { status: 'inativo', updatedAt: nowIso },
          { merge: true },
        );
        prunedInactiveCount += 1;
      }
    }
  } finally {
    await writer.close();
  }

  await updateTenantSyncState({
    firestore,
    tenantId,
    patch: {
      lastClientesSyncAt: nowIso,
      lastClientesSyncMode: codigosFiltro?.length ? 'test_filtered' : 'full',
      lastClientesSourceCount: queryResult.rows.length,
      lastClientesImportedCount: importedCount,
      lastClientesSkippedInvalidCount: skippedInvalidCount,
      lastClientesPrunedInactiveCount: prunedInactiveCount,
      lastClientesEndpoint: queryResult.endpointPath,
    },
  });

  return {
    message: codigosFiltro?.length
      ? `Sincronizacao de teste de clientes concluida (restrita aos codigos: ${codigosFiltro.join(', ')}).`
      : 'Sincronizacao completa de clientes concluida via SQL DbExplorer.',
    endpoint: queryResult.endpointPath,
    sourceCount: queryResult.rows.length,
    importedCount,
    skippedInvalidCount,
    prunedInactiveCount,
    codigosFiltro: codigosFiltro ?? [],
  };
}

function buildSankhyaTaxRulesSql() {
  return `
SELECT DISTINCT
    'active' AS STATUS,
    CASE
        WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('N', '4', 'H')
             AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
            THEN NCM1.CODNCM
        WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('N', '4', 'H')
             AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
            THEN NCM2.CODNCM
        WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
             AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO1.NCM
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('P', '1')
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO2.NCM
    WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'I'
       AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO_GI1.NCM
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'I'
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO_GI2.NCM
    WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'K'
       AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO_GK1.NCM
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'K'
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO_GK2.NCM
        ELSE NULL
    END AS NCM,
  CASE
    WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
       AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO1.CODESPECST
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('P', '1')
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO2.CODESPECST
    WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'I'
       AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO_GI1.CODESPECST
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'I'
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO_GI2.CODESPECST
    WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'K'
       AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
      THEN PRO_GK1.CODESPECST
    WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'K'
       AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
      THEN PRO_GK2.CODESPECST
    ELSE NULL
  END AS CEST,
    NVL(UFO.UF, 'ANY') AS UFORIGEM,
    NVL(UFD.UF, 'ANY') AS UFDESTINO,
    CASE
        WHEN NVL(TRIM(TO_CHAR(ICM.PAUTAVLRSTFIXO)), 'N') NOT IN ('0', '0,0', '0,00', '0.0', '0.00', 'N') THEN 'pmc'
        ELSE 'mva'
    END AS TIPOST,
    TO_CHAR(NULL) AS PRECOPARACALCULOST,
    CASE
        WHEN NVL(TRIM(TO_CHAR(ICM.REDBASEST)), 'N') = 'N' THEN '0'
        ELSE TO_CHAR(ICM.REDBASEST)
    END AS REDUCAOBASEICMSST,
    CASE
        WHEN NVL(TRIM(TO_CHAR(ICM.PAUTAVLRSTFIXO)), 'N') = 'N' THEN '0'
        ELSE TO_CHAR(ICM.PAUTAVLRSTFIXO)
    END AS BASECALCULOICMSST,
    CASE
        WHEN NVL(TRIM(TO_CHAR(ICM.ALIQSUBTRIB)), 'N') <> 'N' THEN TO_CHAR(ICM.ALIQSUBTRIB)
        WHEN NVL(TRIM(TO_CHAR(ICM.ALIQINTDEST)), 'N') <> 'N' THEN TO_CHAR(ICM.ALIQINTDEST)
        WHEN NVL(TRIM(TO_CHAR(ICM.ALIQUOTA)), 'N') <> 'N' THEN TO_CHAR(ICM.ALIQUOTA)
        ELSE '0'
    END AS ALIQUOTADESTINO,
    CASE
        WHEN NVL(TRIM(TO_CHAR(ICM.ALIQUOTA)), 'N') <> 'N' THEN TO_CHAR(ICM.ALIQUOTA)
        WHEN NVL(TRIM(TO_CHAR(ICM.ALIQINTDEST)), 'N') <> 'N' THEN TO_CHAR(ICM.ALIQINTDEST)
        ELSE '0'
    END AS ALIQUOTACREDITO,
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
    TO_CHAR(ICM.CSOSN) AS CST_CSOSN,
    CASE
        WHEN NVL(TRIM(TO_CHAR(ICM.MVAORIGINAL)), 'N') <> 'N' THEN TO_CHAR(ICM.MVAORIGINAL)
        WHEN NVL(TRIM(TO_CHAR(ICM.MVASIMPLIFICADO)), 'N') <> 'N' THEN TO_CHAR(ICM.MVASIMPLIFICADO)
        ELSE '0'
    END AS MVA,
    (
        'TIPRESTRICAO=' || NVL(TO_CHAR(ICM.TIPRESTRICAO), '-') ||
        ';CODRESTRICAO=' || NVL(TO_CHAR(ICM.CODRESTRICAO), '-') ||
        ';TIPRESTRICAO2=' || NVL(TO_CHAR(ICM.TIPRESTRICAO2), '-') ||
        ';CODRESTRICAO2=' || NVL(TO_CHAR(ICM.CODRESTRICAO2), '-') ||
        ';TIPCALCDIFAL=' || NVL(TO_CHAR(ICM.TIPCALCDIFAL), '-')
    ) AS EXCECAOFISCAL,
    ICM.DTINICIOVIGENCIA AS VIGENCIAINICIAL,
    ICM.DTFIMVIGENCIA AS VIGENCIAFINAL,
    TO_CHAR(
        CASE
            WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
                 AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
                THEN 300000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('N', '4', 'H')
                 AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
                THEN 200000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('N', '4', 'H')
                 AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
                THEN 190000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'I'
             AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
            THEN 180000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'I'
             AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
            THEN 170000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO) = 'K'
             AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
            THEN 160000 + NVL(ICM.SEQUENCIA, 0)
          WHEN TO_CHAR(ICM.TIPRESTRICAO2) = 'K'
             AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
            THEN 150000 + NVL(ICM.SEQUENCIA, 0)
            ELSE 100000 + NVL(ICM.SEQUENCIA, 0)
        END
    ) AS PRIORIDADE,
    TO_CHAR(ICM.CODTRIB) AS GRUPOFISCALID,
    TO_CHAR(ICM.CODTAB) AS CODTAB,
    TO_CHAR(ICM.SEQUENCIA) AS SEQUENCIA,
    TO_CHAR(ICM.IDALIQ) AS IDALIQ
FROM TGFICM ICM
LEFT JOIN TSIUFS UFO
    ON ICM.UFORIG = UFO.CODUF
LEFT JOIN TSIUFS UFD
    ON ICM.UFDEST = UFD.CODUF
LEFT JOIN TGFPRO PRO1
    ON TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
  AND ICM.CODRESTRICAO = PRO1.CODPROD
LEFT JOIN TGFPRO PRO2
   ON TO_CHAR(ICM.TIPRESTRICAO2) IN ('P', '1')
  AND ICM.CODRESTRICAO2 = PRO2.CODPROD
LEFT JOIN TGFPRO PRO_GI1
  ON TO_CHAR(ICM.TIPRESTRICAO) = 'I'
  AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
  AND NVL(PRO_GI1.GRUPOICMS, -1) = NVL(ICM.CODRESTRICAO, -2)
LEFT JOIN TGFPRO PRO_GI2
  ON TO_CHAR(ICM.TIPRESTRICAO2) = 'I'
  AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
  AND NVL(PRO_GI2.GRUPOICMS, -1) = NVL(ICM.CODRESTRICAO2, -2)
LEFT JOIN TGFPRO PRO_GK1
  ON TO_CHAR(ICM.TIPRESTRICAO) = 'K'
  AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
  AND NVL(PRO_GK1.GRUPOICMS2, -1) = NVL(ICM.CODRESTRICAO, -2)
LEFT JOIN TGFPRO PRO_GK2
  ON TO_CHAR(ICM.TIPRESTRICAO2) = 'K'
  AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
  AND NVL(PRO_GK2.GRUPOICMS2, -1) = NVL(ICM.CODRESTRICAO2, -2)
LEFT JOIN TGFNCM NCM1
   ON TO_CHAR(ICM.TIPRESTRICAO) IN ('N', '4', 'H')
   AND LTRIM(TO_CHAR(ICM.CODRESTRICAO), '0') = LTRIM(REPLACE(NCM1.CODNCM, '.', ''), '0')
LEFT JOIN TGFNCM NCM2
   ON TO_CHAR(ICM.TIPRESTRICAO2) IN ('N', '4', 'H')
   AND LTRIM(TO_CHAR(ICM.CODRESTRICAO2), '0') = LTRIM(REPLACE(NCM2.CODNCM, '.', ''), '0')
WHERE
    ICM.DTINICIOVIGENCIA IS NULL
    OR ICM.DTINICIOVIGENCIA <= SYSDATE
ORDER BY
    UFORIGEM,
    UFDESTINO,
    PRIORIDADE DESC,
    NCM,
    CEST
`.trim();
}

function mapSankhyaTaxRuleRow({
  tenantId,
  row,
  nowIso,
  syncBatchId,
  syncVersion,
}) {
  const ncmDigits = normalizeDigits(
    readRowValueByAliases(row, ['NCM']),
  );
  const ufDestino = normalizeTaxRuleUf(
    readRowValueByAliases(row, ['UFDESTINO']),
  );
  if (!ufDestino) {
    return null;
  }

  const ufOrigem =
    normalizeTaxRuleUf(readRowValueByAliases(row, ['UFORIGEM'])) || 'ANY';
  const cestDigits = normalizeDigits(
    readRowValueByAliases(row, ['CEST']),
  );
  const stType = normalizeTaxRuleStType(
    readRowValueByAliases(row, ['TIPOST', 'STCALCULATIONTYPE']),
  );
  const aliquotaDestino = toNumberOrNull(
    readRowValueByAliases(row, ['ALIQUOTADESTINO']),
  );
  const aliquotaCredito = toNumberOrNull(
    readRowValueByAliases(row, ['ALIQUOTACREDITO']),
  );
  const mvaIva = toNumberOrNull(readRowValueByAliases(row, ['MVA']));
  const stBaseReductionPercent = toNumberOrNull(
    readRowValueByAliases(row, ['REDUCAOBASEICMSST', 'REDBASEST']),
  );
  const stBaseAmount = toNumberOrNull(
    readRowValueByAliases(row, ['BASECALCULOICMSST', 'PAUTAVLRSTFIXO']),
  );
  const aliquotaDifalValue = toNumberOrNull(
    readRowValueByAliases(row, ['ALIQUOTADIFAL']),
  );
  const aliquotaFcpValue =
    toNumberOrNull(readRowValueByAliases(row, ['PERCFCPINTERNO'])) ??
    toNumberOrNull(readRowValueByAliases(row, ['PERCFCPGERAL']));
  const aliquotaFcpStValue = toNumberOrNull(
    readRowValueByAliases(row, ['PERCSTFCPINTERNO']),
  );

  // Linhas de excecao por NCM/produto/grupo que nao carregam NENHUM valor
  // fiscal real (todos os campos numericos zerados/nulos) sao descartadas:
  // no Sankhya elas so existem para fins de CST/CSOSN/CEST e, se importadas
  // como regra por NCM (tier 2), mascarariam com 0% a regra generica por UF
  // (tier 3) que e quem realmente carrega a aliquota. A regra generica (sem
  // NCM) nunca e descartada por este filtro.
  if (ncmDigits) {
    const hasRealValue = [
      aliquotaDestino,
      aliquotaCredito,
      mvaIva,
      stBaseReductionPercent,
      stBaseAmount,
      aliquotaDifalValue,
      aliquotaFcpValue,
      aliquotaFcpStValue,
    ].some((value) => (value ?? 0) > 0);
    if (!hasRealValue) {
      return null;
    }
  }

  const codTab = sanitizeKeyToken(readRowValueByAliases(row, ['CODTAB']), '-');
  const sequencia = sanitizeKeyToken(
    readRowValueByAliases(row, ['SEQUENCIA']),
    '-',
  );
  const idAliq = sanitizeKeyToken(readRowValueByAliases(row, ['IDALIQ']), '-');

  const identityParts = [
    codTab,
    sequencia,
    idAliq,
    sanitizeKeyToken(ufOrigem, 'ANY'),
    sanitizeKeyToken(ufDestino, 'ANY'),
    sanitizeKeyToken(ncmDigits || 'ANY', 'ANY'),
    sanitizeKeyToken(cestDigits || 'ANY', 'ANY'),
  ];

  const id = `erp_tax_${tenantId}_${identityParts.join('_')}`;

  return {
    id,
    tenantId,
    representedCompanyId: null,
    status: normalizeTaxRuleStatus(
      readRowValueByAliases(row, ['STATUS']),
    ),
    ncm: ncmDigits ? formatNcmMasked(ncmDigits) : null,
    cest: cestDigits ? formatCestMasked(cestDigits) : null,
    fiscalException: nullableString(
      readRowValueByAliases(row, ['EXCECAOFISCAL', 'FISCALEXCEPTION']),
    ),
    stCalculationType: stType,
    stPriceForCalculation: toNumberOrNull(
      readRowValueByAliases(row, ['PRECOPARACALCULOST', 'STPRICEFORCALCULATION']),
    ),
    stBaseReductionPercent,
    stBaseAmount,
    aliquotaDestino,
    aliquotaCredito,
    grupoFiscalId: nullableString(
      readRowValueByAliases(row, ['GRUPOFISCALID', 'CODTRIB']),
    ),
    salePurpose: null,
    ufOrigem,
    ufDestino,
    cstCsosn: nullableString(
      readRowValueByAliases(row, ['CST_CSOSN', 'CSTCSOSN']),
    ),
    aliquotaIcms: aliquotaCredito,
    mvaIva,
    aliquotaSt: aliquotaDestino,
    aliquotaDifal: aliquotaDifalValue,
    aliquotaFcp: aliquotaFcpValue,
    aliquotaFcpSt: aliquotaFcpStValue,
    priority: readInt(readRowValueByAliases(row, ['PRIORIDADE'])),
    validFrom: toIsoDateOrNull(
      readRowValueByAliases(row, ['VIGENCIAINICIAL', 'VALIDFROM']),
      false,
    ),
    validUntil: toIsoDateOrNull(
      readRowValueByAliases(row, ['VIGENCIAFINAL', 'VALIDUNTIL']),
      true,
    ),
    origin: 'erp',
    erpSyncId: syncBatchId,
    syncVersion,
    deletedAt: null,
    createdAt: nowIso,
    updatedAt: nowIso,
  };
}

// --- Agrupamento inteligente de regras fiscais (Grupo Tributario automatico) ---
//
// Objetivo: NCMs que, na pratica, tem exatamente o mesmo "perfil fiscal"
// (mesma aliquota interna/interestadual, MVA, reducao de base, CST/CSOSN,
// FCP etc. em cada par de UF) sao agrupados automaticamente em um unico
// `tax_rule_groups` + um unico conjunto de `tax_rules` por grupo, em vez de
// uma regra por NCM. Isso evita a explosao de regras quase-identicas e
// aproxima o cadastro do que o usuario faria manualmente ao analisar uma
// planilha de produtos (varios NCMs com o mesmo tratamento fiscal).
function roundForFingerprint(value) {
  const numeric = Number(value ?? 0);
  if (!Number.isFinite(numeric)) {
    return 0;
  }
  return Math.round(numeric * 10000) / 10000;
}

function buildTaxFingerprintKey(vectorRows) {
  const parts = vectorRows
    .map((row) =>
      [
        row.ufOrigem,
        row.ufDestino,
        roundForFingerprint(row.aliquotaDestino),
        roundForFingerprint(row.aliquotaCredito),
        roundForFingerprint(row.aliquotaDifal),
        roundForFingerprint(row.mvaIva),
        roundForFingerprint(row.stBaseReductionPercent),
        roundForFingerprint(row.stBaseAmount),
        row.stCalculationType || 'mva',
        row.cstCsosn || '',
        roundForFingerprint(row.aliquotaFcp),
        roundForFingerprint(row.aliquotaFcpSt),
      ].join('|'),
    )
    .sort();
  return parts.join('#');
}

function computeFingerprintHash(key) {
  return crypto.createHash('sha1').update(key).digest('hex').slice(0, 16);
}

function buildAutoGroupName(vectorRows, memberCount) {
  const representative =
    vectorRows.find((row) => (row.aliquotaDestino ?? 0) > 0) || vectorRows[0];
  const icms = roundForFingerprint(representative?.aliquotaDestino);
  const mva = roundForFingerprint(representative?.mvaIva);
  const parts = [`ICMS ${icms}%`];
  if (mva > 0) {
    parts.push(`MVA ${mva}%`);
  }
  return `Grupo Fiscal ERP (${parts.join(' / ')}) - ${memberCount} NCMs`;
}

function buildAutoGroupDescription(vectorRows, memberNcms) {
  const sampleNcms = memberNcms
    .slice(0, 8)
    .map((digits) => formatNcmMasked(digits))
    .join(', ');
  const suffix = memberNcms.length > 8 ? '...' : '';
  const ufCount = new Set(vectorRows.map((row) => row.ufDestino)).size;
  return `Grupo criado automaticamente na sincronizacao com o ERP (Sankhya), agrupando ${memberNcms.length} NCMs com identico tratamento fiscal em ${ufCount} UF(s) de destino. NCMs: ${sampleNcms}${suffix}`;
}

async function applyTaxGroupsToExistingProducts({
  firestore,
  tenantId,
  ncmToGroupId,
}) {
  const snapshot = await firestore
    .collection('produtos')
    .where('tenantId', '==', tenantId)
    .select('ncm', 'grupoTributarioId', 'deletedAt')
    .get();

  const writer = firestore.bulkWriter();
  writer.onWriteError((error) => error.failedAttempts < 3);
  let linkedCount = 0;

  try {
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      if (data.deletedAt) {
        continue;
      }
      const ncmDigits = normalizeDigits(data.ncm);
      if (!ncmDigits) {
        continue;
      }
      const groupId = ncmToGroupId.get(ncmDigits);
      if (!groupId || data.grupoTributarioId === groupId) {
        continue;
      }
      writer.set(
        doc.ref,
        { grupoTributarioId: groupId },
        { merge: true },
      );
      linkedCount += 1;
    }
  } finally {
    await writer.close();
  }

  return linkedCount;
}

function normalizeTaxRuleUf(value) {
  const token = String(value ?? '').trim().toUpperCase();
  if (!token) {
    return 'ANY';
  }
  if (token === 'ANY' || token === 'TODOS' || token === 'TODAS') {
    return 'ANY';
  }
  if (/^[A-Z]{2}$/.test(token)) {
    return token;
  }
  return 'ANY';
}

function normalizeTaxRuleStType(value) {
  const token = String(value ?? '').trim().toLowerCase();
  if (token === 'pmc') {
    return 'pmc';
  }
  return 'mva';
}

function normalizeTaxRuleStatus(value) {
  const token = String(value ?? '').trim().toLowerCase();
  if (
    token === 'inactive' ||
    token === 'inativo' ||
    token === 'desativado'
  ) {
    return 'inactive';
  }
  return 'active';
}

function normalizeDigits(value) {
  const token = String(value ?? '').trim();
  if (!token) {
    return '';
  }
  return token.replace(/[^0-9]/g, '');
}

function formatNcmMasked(digits) {
  const raw = String(digits ?? '').replace(/[^0-9]/g, '');
  if (!raw) {
    return '';
  }
  const normalized = raw.padStart(8, '0');
  return `${normalized.slice(0, 4)}.${normalized.slice(4, 6)}.${normalized.slice(6, 8)}`;
}

function formatCestMasked(digits) {
  const raw = String(digits ?? '').replace(/[^0-9]/g, '');
  if (!raw) {
    return '';
  }
  const normalized = raw.padStart(7, '0');
  return `${normalized.slice(0, 2)}.${normalized.slice(2, 5)}.${normalized.slice(5, 7)}`;
}

function nullableString(value) {
  const token = String(value ?? '').trim();
  return token ? token : null;
}

function sanitizeKeyToken(value, fallback) {
  const token = String(value ?? '').trim();
  if (!token) {
    return fallback;
  }
  const normalized = token
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^A-Za-z0-9_-]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return normalized || fallback;
}

function toIsoDateOrNull(value, endOfDay) {
  if (value === null || value === undefined || value === '') {
    return null;
  }

  if (value instanceof Date) {
    const utc = new Date(value);
    if (endOfDay) {
      utc.setUTCHours(23, 59, 59, 999);
    } else {
      utc.setUTCHours(0, 0, 0, 0);
    }
    return utc.toISOString();
  }

  const text = String(value).trim();
  if (!text) {
    return null;
  }

  const direct = new Date(text);
  if (!Number.isNaN(direct.getTime())) {
    if (endOfDay) {
      direct.setUTCHours(23, 59, 59, 999);
    } else {
      direct.setUTCHours(0, 0, 0, 0);
    }
    return direct.toISOString();
  }

  const br = /^(\d{2})\/(\d{2})\/(\d{4})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?$/.exec(text);
  if (br) {
    const day = Number.parseInt(br[1], 10);
    const month = Number.parseInt(br[2], 10) - 1;
    const year = Number.parseInt(br[3], 10);
    const date = new Date(Date.UTC(year, month, day, 0, 0, 0, 0));
    if (Number.isNaN(date.getTime())) {
      return null;
    }
    if (endOfDay) {
      date.setUTCHours(23, 59, 59, 999);
    }
    return date.toISOString();
  }

  return null;
}