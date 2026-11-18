const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const {
  executeSyncSankhyaProductImagesModuleAction,
} = require('../../src/billing/sankhya_product_images_sync_management_helpers');

function createFirestoreHarness({ productDocs = {}, mediaDocs = [] } = {}) {
  const productSets = [];
  const mediaSets = [];

  const produtosCollection = {
    doc(id) {
      const key = `produtos/${id}`;
      const existing = productDocs[key];
      return {
        async get() {
          if (!existing) {
            return { exists: false, data: () => undefined };
          }
          return { exists: true, data: () => existing };
        },
        async set(payload) {
          productSets.push({ key, payload });
        },
      };
    },
  };

  const mediaCollection = {
    where() {
      return {
        async get() {
          return {
            docs: mediaDocs.map((doc) => ({
              id: doc.id,
              data: () => doc.data,
            })),
          };
        },
      };
    },
    doc(id) {
      const key = `product_media_assets/${id}`;
      return {
        async set(payload) {
          mediaSets.push({ key, payload });
        },
      };
    },
  };

  const firestore = {
    collection(name) {
      if (name === 'produtos') {
        return produtosCollection;
      }
      if (name === 'product_media_assets') {
        return mediaCollection;
      }
      throw new Error(`Unexpected collection: ${name}`);
    },
  };

  return {
    firestore,
    productSets,
    mediaSets,
  };
}

test('executeSyncSankhyaProductImagesModuleAction returns early when no valid product codes exist', async () => {
  const harness = createFirestoreHarness();
  let dbExplorerCalls = 0;
  let syncPatchCalls = 0;

  const result = await executeSyncSankhyaProductImagesModuleAction({
    firestore: harness.firestore,
    tenantId: 'tenant_1',
    baseUrl: 'https://api.example.com',
    bearerToken: 'bearer',
    xToken: 'xtoken',
    fetchImpl: async () => ({
      status: 200,
      async text() {
        return JSON.stringify({
          produtos: [{ codigoProduto: 0 }, { codigoProduto: '0000' }],
        });
      },
    }),
    sankhyaProductsPath: '/v1/produtos?page=0',
    tryParseJson: (text) => JSON.parse(text),
    toCodeString: (value) => String(value ?? '').trim(),
    isZeroCode: (value) => /^0+$/.test(String(value ?? '').trim()),
    temporaryImportLimit: 5,
    buildSankhyaProductImageChunksSql: () => 'SELECT 1',
    executeSankhyaDbExplorerQuery: async () => {
      dbExplorerCalls += 1;
      return { rows: [], endpointPath: '/dbexplorer' };
    },
    readRowValueByAliases: () => null,
    readInt: () => 0,
    detectImageFormat: () => 'jpg',
    buildFirebaseDownloadUrl: () => 'https://example.invalid',
    buildProductDocId: (_tenantId, productCode) =>
      `erp_prod_${_tenantId}_${productCode}`,
    defaultProductMediaScopeKey: 'tenant_default',
    defaultStorageBucket: 'bucket',
    admin: {
      storage() {
        return { bucket: () => ({ file: () => ({ save: async () => {} }) }) };
      },
      firestore: {
        Timestamp: { fromDate: (date) => date },
        FieldValue: { serverTimestamp: () => 'ts' },
      },
    },
    crypto,
    updateTenantSyncState: async () => {
      syncPatchCalls += 1;
    },
  });

  assert.equal(result.importedCount, 0);
  assert.equal(result.filteredOutZeroCodeCount, 2);
  assert.equal(result.appliedLimit, 5);
  assert.equal(dbExplorerCalls, 0);
  assert.equal(syncPatchCalls, 0);
  assert.equal(harness.productSets.length, 0);
});

test('executeSyncSankhyaProductImagesModuleAction reuses existing media asset and updates product link', async () => {
  const tenantId = 'tenant_2';
  const productCode = '101';
  const docId = `erp_prod_${tenantId}_${productCode}`;
  const imageBuffer = Buffer.from([0x01, 0x02, 0x03, 0x04]);
  const imageHash = crypto.createHash('sha256').update(imageBuffer).digest('hex');

  const harness = createFirestoreHarness({
    productDocs: {
      [`produtos/${docId}`]: {
        syncVersion: 7,
        fotoUrl: 'https://old',
        storagePath: 'old/path',
        thumbnailBase64: 'old-thumb',
      },
    },
    mediaDocs: [
      {
        id: 'asset_existing',
        data: {
          scopeKey: 'tenant_default',
          imageHash,
          downloadUrl: 'https://cdn/new-url',
          storagePath: 'tenants/tenant_2/product_media/tenant_default/erp_sync/asset_existing.jpg',
          thumbnailBase64: 'thumb-new',
        },
      },
    ],
  });

  const syncPatches = [];

  const result = await executeSyncSankhyaProductImagesModuleAction({
    firestore: harness.firestore,
    tenantId,
    baseUrl: 'https://api.example.com',
    bearerToken: 'bearer',
    xToken: 'xtoken',
    fetchImpl: async () => ({
      status: 200,
      async text() {
        return JSON.stringify({
          produtos: [{ codigoProduto: productCode }],
        });
      },
    }),
    sankhyaProductsPath: '/v1/produtos?page=0',
    tryParseJson: (text) => JSON.parse(text),
    toCodeString: (value) => String(value ?? '').trim(),
    isZeroCode: (value) => /^0+$/.test(String(value ?? '').trim()),
    temporaryImportLimit: 5,
    buildSankhyaProductImageChunksSql: (codes) => {
      assert.deepEqual(codes, [productCode]);
      return 'SELECT IMAGE CHUNKS';
    },
    executeSankhyaDbExplorerQuery: async () => ({
      rows: [
        {
          CODPROD: productCode,
          CHUNKINDEX: 0,
          CHUNKHEX: imageBuffer.toString('hex').toUpperCase(),
        },
      ],
      endpointPath: '/dbexplorer/images',
    }),
    readRowValueByAliases: (row, aliases) => {
      for (const key of aliases) {
        if (Object.prototype.hasOwnProperty.call(row, key)) {
          return row[key];
        }
      }
      return null;
    },
    readInt: (value) => Number.parseInt(String(value ?? '0'), 10) || 0,
    detectImageFormat: () => 'jpg',
    buildFirebaseDownloadUrl: () => 'https://generated-url',
    buildProductDocId: (_tenantId, code) => `erp_prod_${_tenantId}_${code}`,
    defaultProductMediaScopeKey: 'tenant_default',
    defaultStorageBucket: 'bucket',
    admin: {
      storage() {
        return {
          bucket() {
            return { file: () => ({ save: async () => {} }) };
          },
        };
      },
      firestore: {
        Timestamp: { fromDate: (date) => date },
        FieldValue: { serverTimestamp: () => 'ts' },
      },
    },
    crypto,
    updateTenantSyncState: async ({ patch }) => {
      syncPatches.push(patch);
    },
  });

  assert.equal(result.sourceCount, 1);
  assert.equal(result.importedCount, 1);
  assert.equal(result.uploadedAssetCount, 0);
  assert.equal(result.reusedExistingAssetCount, 1);
  assert.equal(result.reusedWithinBatchCount, 0);

  assert.equal(harness.mediaSets.length, 0);
  assert.equal(harness.productSets.length, 1);
  assert.equal(harness.productSets[0].key, `produtos/${docId}`);
  assert.equal(harness.productSets[0].payload.fotoUrl, 'https://cdn/new-url');
  assert.equal(harness.productSets[0].payload.storagePath.includes('asset_existing'), true);
  assert.equal(harness.productSets[0].payload.thumbnailBase64, 'thumb-new');
  assert.equal(harness.productSets[0].payload.syncVersion, 8);

  assert.equal(syncPatches.length, 1);
  assert.equal(syncPatches[0].lastProductImagesImportedCount, 1);
  assert.equal(syncPatches[0].lastProductImagesReusedExistingAssetCount, 1);
  assert.equal(syncPatches[0].lastProductImagesUploadedAssetCount, 0);
});
