async function executeSyncSankhyaProductsModuleAction({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
  fetchImpl,
  sankhyaProductsPath,
  tryParseJson,
  toCodeString,
  isZeroCode,
  temporaryImportLimit,
  buildTenantNcmGroupIndex,
  fetchSankhyaProductsFiscalData,
  resolveInternalProductCode,
  mapSankhyaProductToFirestore,
  updateTenantSyncState,
  readInt,
}) {
  const sourceUrl = `${baseUrl}${sankhyaProductsPath}`;
  const sankhyaResponse = await fetchImpl(sourceUrl, {
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
      `Falha ao consultar modulo produtos no endpoint ${sankhyaProductsPath} (HTTP ${sankhyaResponse.status}): ${sourceText.slice(0, 300)}`,
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
      filteredOutZeroCodeCount += 1;
      continue;
    }

    validProducts.push(rawItem);
    if (validProducts.length >= temporaryImportLimit) {
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
    const docId = `erp_prod_${tenantId}_${toCodeString(erpProductCode)}`;
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
      lastProductsAppliedLimit: temporaryImportLimit,
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
    endpoint: sankhyaProductsPath,
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
    appliedLimit: temporaryImportLimit,
  };
}

module.exports = {
  executeSyncSankhyaProductsModuleAction,
};
