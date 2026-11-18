const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeSyncSankhyaPriceTablesModuleAction,
} = require('../../src/billing/sankhya_price_tables_module_sync_management_helpers');

function createFirestoreHarness({ tenantData }) {
  const writerSets = [];
  const docSets = [];

  const writer = {
    onWriteError() {},
    set(ref, payload) {
      writerSets.push({ path: ref.path, payload });
    },
    async close() {},
  };

  function docRef(path) {
    return {
      path,
      async get() {
        if (path.startsWith('tenants/')) {
          return {
            exists: true,
            data: () => tenantData,
          };
        }
        return { exists: false, data: () => undefined };
      },
      async set(payload) {
        docSets.push({ path, payload });
      },
    };
  }

  const firestore = {
    collection(name) {
      return {
        doc(id) {
          return docRef(`${name}/${id}`);
        },
      };
    },
    bulkWriter() {
      return writer;
    },
  };

  return {
    firestore,
    writerSets,
    docSets,
  };
}

test('executeSyncSankhyaPriceTablesModuleAction throws when tenant has no configured price table codes', async () => {
  const harness = createFirestoreHarness({
    tenantData: {
      erpIntegration: {
        priceTableCodes: [],
      },
    },
  });

  await assert.rejects(
    executeSyncSankhyaPriceTablesModuleAction({
      firestore: harness.firestore,
      tenantId: 'tenant_1',
      baseUrl: 'https://api',
      bearerToken: 'b',
      xToken: 'x',
      normalizePriceTableCodes: () => [],
      buildDefaultPriceTableDocId: () => 'pt_default_tenant_1',
      upsertDefaultPriceTableDocument: async () => {},
      buildTenantProductIndex: async () => new Map(),
      buildPriceTableDocId: () => 'pt_doc',
      upsertPriceTableDocument: async () => {},
      fetchImpl: async () => ({ status: 200, text: async () => '{}' }),
      tryParseJson: () => ({}),
      readPriceRowsFromPayload: () => [],
      toCodeString: (value) => String(value ?? '').trim(),
      isZeroCode: () => false,
      toNumberOrNull: () => null,
      normalizeTextToken: (_value, fallback) => fallback,
      buildProductBasePriceDocId: () => 'pbp',
      buildDefaultProductBasePriceDocId: () => 'pbp_default',
      updateTenantSyncState: async () => {},
      loggerError: () => {},
    }),
    /Nenhum codigo de tabela foi configurado/,
  );
});

test('executeSyncSankhyaPriceTablesModuleAction imports price rows and updates sync state', async () => {
  const harness = createFirestoreHarness({
    tenantData: {
      erpIntegration: {
        priceTableCodes: ['100'],
      },
    },
  });

  const fetchedUrls = [];
  const syncPatches = [];

  const result = await executeSyncSankhyaPriceTablesModuleAction({
    firestore: harness.firestore,
    tenantId: 'tenant_2',
    baseUrl: 'https://api',
    bearerToken: 'b',
    xToken: 'x',
    normalizePriceTableCodes: () => ['100'],
    buildDefaultPriceTableDocId: (tenantId) => `pt_default_${tenantId}`,
    upsertDefaultPriceTableDocument: async () => {},
    buildTenantProductIndex: async () =>
      new Map([
        ['2001', { productId: 'prod_1' }],
      ]),
    buildPriceTableDocId: (tenantId, tableCode) => `erp_pt_${tenantId}_${tableCode}`,
    upsertPriceTableDocument: async () => {},
    fetchImpl: async (url) => {
      fetchedUrls.push(url);
      return {
        status: 200,
        async text() {
          return JSON.stringify({ temMaisRegistros: false, payload: true });
        },
      };
    },
    tryParseJson: (text) => JSON.parse(text),
    readPriceRowsFromPayload: () => [
      {
        codigoProduto: '2001',
        valor: '12.34',
        codigoLocalEstoque: '1',
        unidade: 'UN',
        controle: '',
      },
      {
        codigoProduto: '0',
        valor: '88.00',
      },
      {
        codigoProduto: '9999',
        valor: '7.00',
      },
    ],
    toCodeString: (value) => String(value ?? '').trim(),
    isZeroCode: (value) => /^0+$/.test(String(value ?? '').trim()),
    toNumberOrNull: (value) => {
      const n = Number(String(value).replace(',', '.'));
      return Number.isFinite(n) ? n : null;
    },
    normalizeTextToken: (value, fallback) => {
      const token = String(value ?? '').trim();
      return token || fallback;
    },
    buildProductBasePriceDocId: ({ tenantId, tableCode, productId }) =>
      `erp_pbp_${tenantId}_${tableCode}_${productId}`,
    buildDefaultProductBasePriceDocId: ({ tenantId, productId, defaultPriceTableDocId }) =>
      `pbp_${tenantId}_${productId}_${defaultPriceTableDocId}`,
    updateTenantSyncState: async ({ patch }) => {
      syncPatches.push(patch);
    },
    loggerError: () => {},
  });

  assert.equal(fetchedUrls.length, 1);
  assert.equal(fetchedUrls[0], 'https://api/v1/precos/tabela/100?pagina=1');

  assert.equal(result.sourceCount, 3);
  assert.equal(result.importedCount, 1);
  assert.equal(result.filteredOutZeroCodeCount, 1);
  assert.equal(result.skippedNotFoundCount, 1);
  assert.equal(result.primaryTableCode, '100');
  assert.equal(result.mirroredDefaultPriceCount, 1);
  assert.equal(result.appliedPriceTableCodes.length, 1);
  assert.equal(result.tableSummaries.length, 1);
  assert.equal(result.tableSummaries[0].uniqueProductCount, 1);

  const wroteBasePrice = harness.writerSets.some(
    (entry) => entry.path === 'product_base_prices/erp_pbp_tenant_2_100_prod_1',
  );
  const wroteDefaultPrice = harness.writerSets.some(
    (entry) => entry.path === 'product_base_prices/pbp_tenant_2_prod_1_pt_default_tenant_2',
  );
  const mirroredProduct = harness.writerSets.some(
    (entry) => entry.path === 'produtos/prod_1',
  );

  assert.equal(wroteBasePrice, true);
  assert.equal(wroteDefaultPrice, true);
  assert.equal(mirroredProduct, true);

  assert.equal(syncPatches.length, 1);
  assert.equal(syncPatches[0].lastPriceSyncReadRows, 3);
  assert.equal(syncPatches[0].lastPriceSyncImportedCount, 1);

  const updatedTableRows = harness.docSets.filter((entry) =>
    entry.path.startsWith('tabelas_preco/'),
  );
  assert.equal(updatedTableRows.length, 2);
});
