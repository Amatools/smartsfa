const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeSyncSankhyaProductsModuleAction,
} = require('../../src/billing/sankhya_products_sync_management_helpers');

function createProductsFirestore(existingDataByDocId = {}) {
  const setCalls = [];

  return {
    firestore: {
      collection(name) {
        assert.equal(name, 'produtos');
        return {
          doc(id) {
            return {
              async get() {
                if (!(id in existingDataByDocId)) {
                  return { exists: false, data: () => ({}) };
                }
                return {
                  exists: true,
                  data: () => existingDataByDocId[id],
                };
              },
              async set(payload, options) {
                setCalls.push({ id, payload, options });
              },
            };
          },
        };
      },
    },
    setCalls,
  };
}

test('executeSyncSankhyaProductsModuleAction imports valid products and updates sync state', async () => {
  const { firestore, setCalls } = createProductsFirestore({
    erp_prod_tenant_1_123: { syncVersion: 7 },
  });

  const updateSyncCalls = [];
  const fiscalCalls = [];

  const result = await executeSyncSankhyaProductsModuleAction({
    firestore,
    tenantId: 'tenant_1',
    baseUrl: 'https://api.sankhya.com.br',
    bearerToken: 'bearer',
    xToken: 'xtoken',
    fetchImpl: async () => ({
      status: 200,
      async text() {
        return JSON.stringify({
          produtos: [
            { codigoProduto: '0', nome: 'Zero' },
            { codigoProduto: '123', nome: 'Produto 123' },
            { codigoProduto: '456', nome: 'Produto 456' },
          ],
        });
      },
    }),
    sankhyaProductsPath: '/v1/produtos?page=0',
    tryParseJson: (text) => JSON.parse(text),
    toCodeString: (value) => String(value ?? '').trim(),
    isZeroCode: (code) => String(code ?? '').trim() === '0',
    temporaryImportLimit: 5,
    buildTenantNcmGroupIndex: async () => new Map([['12345678', 'group_1']]),
    fetchSankhyaProductsFiscalData: async (input) => {
      fiscalCalls.push(input);
      return {
        endpointPath: '/dbexplorer',
        rowCount: 2,
        byProductCode: new Map([
          ['123', { origemMercadoriaCst: '0', aliquotaIpiBase: 5 }],
          ['456', { origemMercadoriaCst: null, aliquotaIpiBase: null }],
        ]),
      };
    },
    resolveInternalProductCode: async ({ erpProductCode }) => `ERP-${erpProductCode}`,
    mapSankhyaProductToFirestore: ({ source, nextSyncVersion }) => ({
      id: `mapped_${source.codigoProduto}`,
      code: String(source.codigoProduto),
      syncVersion: nextSyncVersion,
    }),
    updateTenantSyncState: async (input) => {
      updateSyncCalls.push(input);
    },
    readInt: (value) => {
      const parsed = Number.parseInt(String(value ?? '0'), 10);
      return Number.isFinite(parsed) ? parsed : 0;
    },
  });

  assert.equal(result.sourceStatus, 200);
  assert.equal(result.sourceCount, 3);
  assert.equal(result.importedCount, 2);
  assert.equal(result.filteredOutZeroCodeCount, 1);
  assert.equal(result.fiscalQueryOk, true);
  assert.equal(result.fiscalQueryRowsCount, 2);
  assert.equal(result.fiscalMatchedCount, 2);
  assert.equal(result.fiscalEnrichmentCount, 1);
  assert.equal(result.fiscalOriginEnrichmentCount, 1);
  assert.equal(result.fiscalIpiEnrichmentCount, 1);

  assert.equal(fiscalCalls.length, 1);
  assert.deepEqual(fiscalCalls[0].productCodes, ['123', '456']);

  assert.equal(setCalls.length, 2);
  assert.equal(setCalls[0].id, 'erp_prod_tenant_1_123');
  assert.equal(setCalls[0].payload.syncVersion, 8);
  assert.deepEqual(setCalls[0].options, { merge: true });

  assert.equal(updateSyncCalls.length, 1);
  assert.equal(updateSyncCalls[0].tenantId, 'tenant_1');
  assert.equal(updateSyncCalls[0].patch.lastProductsImportedCount, 2);
  assert.equal(updateSyncCalls[0].patch.lastProductsSourceCount, 3);
  assert.equal(updateSyncCalls[0].patch.lastProductsFilteredOutZeroCodeCount, 1);
});

test('executeSyncSankhyaProductsModuleAction keeps importing when fiscal enrichment fails', async () => {
  const { firestore, setCalls } = createProductsFirestore();
  const updateSyncCalls = [];

  const result = await executeSyncSankhyaProductsModuleAction({
    firestore,
    tenantId: 'tenant_2',
    baseUrl: 'https://api.sankhya.com.br',
    bearerToken: 'bearer',
    xToken: 'xtoken',
    fetchImpl: async () => ({
      status: 200,
      async text() {
        return JSON.stringify({ produtos: [{ codigoProduto: '900' }] });
      },
    }),
    sankhyaProductsPath: '/v1/produtos?page=0',
    tryParseJson: (text) => JSON.parse(text),
    toCodeString: (value) => String(value ?? '').trim(),
    isZeroCode: (code) => String(code ?? '').trim() === '0',
    temporaryImportLimit: 5,
    buildTenantNcmGroupIndex: async () => new Map(),
    fetchSankhyaProductsFiscalData: async () => {
      throw new Error('fiscal_failed');
    },
    resolveInternalProductCode: async () => 'ERP-900',
    mapSankhyaProductToFirestore: () => ({ id: 'mapped_900' }),
    updateTenantSyncState: async (input) => {
      updateSyncCalls.push(input);
    },
    readInt: () => 0,
  });

  assert.equal(result.importedCount, 1);
  assert.equal(result.fiscalQueryOk, false);
  assert.equal(result.fiscalQueryError, 'fiscal_failed');
  assert.equal(setCalls.length, 1);
  assert.equal(updateSyncCalls[0].patch.lastProductsFiscalQueryOk, false);
  assert.equal(updateSyncCalls[0].patch.lastProductsFiscalQueryError, 'fiscal_failed');
});

test('executeSyncSankhyaProductsModuleAction throws when source endpoint fails', async () => {
  await assert.rejects(
    async () =>
      executeSyncSankhyaProductsModuleAction({
        firestore: createProductsFirestore().firestore,
        tenantId: 'tenant_3',
        baseUrl: 'https://api.sankhya.com.br',
        bearerToken: 'bearer',
        xToken: 'xtoken',
        fetchImpl: async () => ({
          status: 500,
          async text() {
            return 'server_error';
          },
        }),
        sankhyaProductsPath: '/v1/produtos?page=0',
        tryParseJson: () => ({}),
        toCodeString: (value) => String(value ?? '').trim(),
        isZeroCode: () => false,
        temporaryImportLimit: 5,
        buildTenantNcmGroupIndex: async () => new Map(),
        fetchSankhyaProductsFiscalData: async () => ({
          endpointPath: null,
          rowCount: 0,
          byProductCode: new Map(),
        }),
        resolveInternalProductCode: async () => 'ERP-0',
        mapSankhyaProductToFirestore: () => ({}),
        updateTenantSyncState: async () => {},
        readInt: () => 0,
      }),
    /Falha ao consultar modulo produtos/,
  );
});
