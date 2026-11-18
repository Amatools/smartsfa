async function executeSyncSankhyaPriceTablesModuleAction({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
  normalizePriceTableCodes,
  buildDefaultPriceTableDocId,
  upsertDefaultPriceTableDocument,
  buildTenantProductIndex,
  buildPriceTableDocId,
  upsertPriceTableDocument,
  fetchImpl,
  tryParseJson,
  readPriceRowsFromPayload,
  toCodeString,
  isZeroCode,
  toNumberOrNull,
  normalizeTextToken,
  buildProductBasePriceDocId,
  buildDefaultProductBasePriceDocId,
  updateTenantSyncState,
  loggerError,
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
    if (error.failedAttempts < 3) {
      return true;
    }
    loggerError(
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

        const pageResponse = await fetchImpl(url, {
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

          pricesWriter.set(pricesCollection.doc(priceDocId), payload, {
            merge: true,
          });
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
        const hasMoreByFlag = rawHasMore === true || normalizedHasMore === 'true';
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

module.exports = {
  executeSyncSankhyaPriceTablesModuleAction,
};
