async function executeSyncSankhyaProductImagesModuleAction({
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
  buildSankhyaProductImageChunksSql,
  executeSankhyaDbExplorerQuery,
  readRowValueByAliases,
  readInt,
  detectImageFormat,
  buildFirebaseDownloadUrl,
  buildProductDocId,
  defaultProductMediaScopeKey,
  defaultStorageBucket,
  admin,
  crypto,
  updateTenantSyncState,
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
      `Falha ao consultar modulo produtos para sync de imagens (HTTP ${sankhyaResponse.status}): ${sourceText.slice(0, 300)}`,
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

  const validProductCodes = validProducts
    .map((item) => toCodeString(item?.codigoProduto))
    .filter((item) => item && !isZeroCode(item));

  if (validProductCodes.length === 0) {
    return {
      message:
        'Nenhum produto valido foi encontrado no lote temporario para sincronizacao de imagens.',
      endpoint: sankhyaProductsPath,
      sourceStatus: sankhyaResponse.status,
      sourceCount: sourceProducts.length,
      importedCount: 0,
      filteredOutZeroCodeCount,
      skippedNotFoundCount: 0,
      appliedLimit: temporaryImportLimit,
    };
  }

  const imageSql = buildSankhyaProductImageChunksSql(validProductCodes);
  const queryResult = await executeSankhyaDbExplorerQuery({
    baseUrl,
    bearerToken,
    xToken,
    sql: imageSql,
  });

  const chunksByProduct = new Map();
  for (const row of queryResult.rows) {
    const productCode = toCodeString(
      readRowValueByAliases(row, ['CodigoProduto', 'CODPROD']),
    );
    if (!productCode) {
      continue;
    }

    const chunkIndex =
      readInt(readRowValueByAliases(row, ['ChunkIndex', 'CHUNKINDEX'])) || 0;
    const chunkHex = String(
      readRowValueByAliases(row, ['ChunkHex', 'CHUNKHEX']) ?? '',
    )
      .trim()
      .toUpperCase();

    if (!chunkHex) {
      continue;
    }

    const productChunks = chunksByProduct.get(productCode) || [];
    productChunks.push({ chunkIndex, chunkHex });
    chunksByProduct.set(productCode, productChunks);
  }

  const imageByProductCode = new Map();
  for (const [productCode, chunks] of chunksByProduct.entries()) {
    chunks.sort((left, right) => left.chunkIndex - right.chunkIndex);
    const mergedHex = chunks.map((item) => item.chunkHex).join('');
    if (!mergedHex) {
      continue;
    }

    const imageBuffer = Buffer.from(mergedHex, 'hex');
    if (!imageBuffer || imageBuffer.length === 0) {
      continue;
    }

    const imageHash = crypto
      .createHash('sha256')
      .update(imageBuffer)
      .digest('hex');
    imageByProductCode.set(productCode, {
      imageBuffer,
      imageHash,
    });
  }

  const nowIso = new Date().toISOString();
  const syncBatchId = `sankhya_img_${Date.now()}`;
  const productsCollection = firestore.collection('produtos');
  const mediaCollection = firestore.collection('product_media_assets');

  const existingAssetsSnapshot = await mediaCollection
    .where('tenantId', '==', tenantId)
    .get();
  const existingAssetByHash = new Map();
  for (const doc of existingAssetsSnapshot.docs) {
    const data = doc.data() || {};
    const scopeKey = String(data.scopeKey ?? '').trim();
    const imageHash = String(data.imageHash ?? '').trim().toLowerCase();
    if (
      scopeKey !== defaultProductMediaScopeKey ||
      !imageHash ||
      !data.downloadUrl ||
      !data.storagePath
    ) {
      continue;
    }
    existingAssetByHash.set(imageHash, {
      assetId: doc.id,
      downloadUrl: String(data.downloadUrl ?? '').trim(),
      storagePath: String(data.storagePath ?? '').trim(),
      thumbnailBase64: String(data.thumbnailBase64 ?? '').trim(),
    });
  }

  const uploadedAssetByHash = new Map();
  const bucketName =
    process.env.FIREBASE_STORAGE_BUCKET ||
    process.env.GCLOUD_STORAGE_BUCKET ||
    defaultStorageBucket;
  const bucket = admin.storage().bucket(bucketName);

  const sourceCount = validProductCodes.length;
  let importedCount = 0;
  let skippedNotFoundCount = 0;
  let productsWithoutImageCount = 0;
  let reusedWithinBatchCount = 0;
  let reusedExistingAssetCount = 0;
  let uploadedAssetCount = 0;
  let alreadyUpToDateCount = 0;

  for (const productCode of validProductCodes) {
    const docId = buildProductDocId(tenantId, productCode);
    const docRef = productsCollection.doc(docId);
    const existingDoc = await docRef.get();
    if (!existingDoc.exists) {
      skippedNotFoundCount += 1;
      continue;
    }

    const existingData = existingDoc.data() || {};
    const imageData = imageByProductCode.get(productCode);
    if (!imageData) {
      productsWithoutImageCount += 1;
      continue;
    }

    const { imageBuffer, imageHash } = imageData;
    const normalizedHash = String(imageHash).trim().toLowerCase();
    let resolvedAsset = uploadedAssetByHash.get(normalizedHash);

    if (!resolvedAsset) {
      const existingAsset = existingAssetByHash.get(normalizedHash);
      if (existingAsset) {
        resolvedAsset = existingAsset;
        uploadedAssetByHash.set(normalizedHash, resolvedAsset);
        reusedExistingAssetCount += 1;
      }
    } else {
      reusedWithinBatchCount += 1;
    }

    if (!resolvedAsset) {
      const imageFormat = detectImageFormat(imageBuffer);
      const extension = imageFormat === 'png' ? 'png' : 'jpg';
      const contentType = imageFormat === 'png' ? 'image/png' : 'image/jpeg';
      const thumbnailBase64 = imageBuffer.toString('base64');

      const assetId = `erp_pma_${tenantId}_${normalizedHash.slice(0, 24)}`;
      const storagePath =
        `tenants/${tenantId}/product_media/${defaultProductMediaScopeKey}/erp_sync/${assetId}.${extension}`;
      const downloadToken = crypto.randomUUID();
      const file = bucket.file(storagePath);

      await file.save(imageBuffer, {
        resumable: false,
        metadata: {
          contentType,
          metadata: {
            firebaseStorageDownloadTokens: downloadToken,
            origin: 'erp-sync-product-images',
            scopeKey: defaultProductMediaScopeKey,
            imageHash: normalizedHash,
            erpProvider: 'sankhya',
          },
        },
      });

      const downloadUrl = buildFirebaseDownloadUrl({
        bucketName,
        storagePath,
        token: downloadToken,
      });

      await mediaCollection.doc(assetId).set(
        {
          id: assetId,
          tenantId,
          representedCompanyId: null,
          scopeKey: defaultProductMediaScopeKey,
          fileName: `${assetId}.${extension}`,
          downloadUrl,
          storagePath,
          thumbnailBase64,
          width: 500,
          height: 500,
          imageHash: normalizedHash,
          source: 'erp_sync',
          erpProvider: 'sankhya',
          erpSyncId: syncBatchId,
          createdAt: existingDoc.createTime
            ? admin.firestore.Timestamp.fromDate(
                new Date(existingDoc.createTime.toDate()),
              )
            : admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      resolvedAsset = {
        assetId,
        downloadUrl,
        storagePath,
        thumbnailBase64,
      };
      uploadedAssetByHash.set(normalizedHash, resolvedAsset);
      existingAssetByHash.set(normalizedHash, resolvedAsset);
      uploadedAssetCount += 1;
    }

    if (!resolvedAsset) {
      continue;
    }

    const existingPhotoUrl = String(existingData.fotoUrl ?? '').trim();
    const existingStoragePath = String(existingData.storagePath ?? '').trim();
    const existingThumb = String(existingData.thumbnailBase64 ?? '').trim();
    const isAlreadyLinked =
      existingPhotoUrl === resolvedAsset.downloadUrl &&
      existingStoragePath === resolvedAsset.storagePath &&
      existingThumb.length > 0;

    if (isAlreadyLinked) {
      alreadyUpToDateCount += 1;
      continue;
    }

    const nextSyncVersion = readInt(existingData.syncVersion) + 1;
    await docRef.set(
      {
        fotoUrl: resolvedAsset.downloadUrl,
        storagePath: resolvedAsset.storagePath,
        thumbnailBase64: resolvedAsset.thumbnailBase64,
        erpSyncId: syncBatchId,
        syncVersion: nextSyncVersion,
        updatedAt: nowIso,
      },
      { merge: true },
    );
    importedCount += 1;
  }

  await updateTenantSyncState({
    firestore,
    tenantId,
    patch: {
      lastProductImagesSyncedAt: nowIso,
      lastProductImagesSyncAt: nowIso,
      lastProductImagesSourceCount: sourceCount,
      lastProductImagesImportedCount: importedCount,
      lastProductImagesFilteredOutZeroCodeCount: filteredOutZeroCodeCount,
      lastProductImagesSkippedNotFoundCount: skippedNotFoundCount,
      lastProductImagesWithoutImageCount: productsWithoutImageCount,
      lastProductImagesUploadedAssetCount: uploadedAssetCount,
      lastProductImagesReusedWithinBatchCount: reusedWithinBatchCount,
      lastProductImagesReusedExistingAssetCount: reusedExistingAssetCount,
      lastProductImagesAlreadyUpToDateCount: alreadyUpToDateCount,
      lastProductImagesAppliedLimit: temporaryImportLimit,
    },
  });

  return {
    message:
      'Sincronizacao manual de fotos concluida. Imagens repetidas foram deduplicadas e vinculadas aos produtos do lote temporario.',
    endpoint: queryResult.endpointPath,
    sourceStatus: sankhyaResponse.status,
    sourceCount,
    importedCount,
    filteredOutZeroCodeCount,
    skippedNotFoundCount,
    productsWithoutImageCount,
    uploadedAssetCount,
    reusedWithinBatchCount,
    reusedExistingAssetCount,
    alreadyUpToDateCount,
    appliedLimit: temporaryImportLimit,
  };
}

module.exports = {
  executeSyncSankhyaProductImagesModuleAction,
};
