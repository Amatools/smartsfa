const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeSyncSankhyaClientesModuleAction,
} = require('../../src/billing/sankhya_clientes_sync_management_helpers');

function createRef(path, store, existingDataByPath) {
  return {
    path,
    async get() {
      if (Object.prototype.hasOwnProperty.call(existingDataByPath, path)) {
        return {
          exists: true,
          data: () => existingDataByPath[path],
        };
      }
      const value = store.get(path);
      if (!value) {
        return { exists: false, data: () => undefined };
      }
      return { exists: true, data: () => value };
    },
  };
}

function createFirestoreHarness({
  existingDataByPath = {},
  existingErpDocs = [],
} = {}) {
  const sets = [];
  const store = new Map();
  let pruneQueryGetCount = 0;

  const writer = {
    onWriteError() {},
    set(ref, payload) {
      sets.push({ path: ref.path, payload });
      store.set(ref.path, payload);
    },
    async close() {},
  };

  const clientesCollection = {
    doc(id) {
      return createRef(`clientes/${id}`, store, existingDataByPath);
    },
    where() {
      const query = {
        where() {
          return query;
        },
        async get() {
          pruneQueryGetCount += 1;
          return {
            docs: existingErpDocs.map((doc) => ({
              id: doc.id,
              ref: createRef(`clientes/${doc.id}`, store, existingDataByPath),
              data: () => doc.data,
            })),
          };
        },
      };
      return query;
    },
  };

  return {
    firestore: {
      collection(name) {
        if (name === 'clientes') {
          return clientesCollection;
        }
        throw new Error(`Unexpected collection: ${name}`);
      },
      bulkWriter() {
        return writer;
      },
    },
    sets,
    getPruneQueryGetCount() {
      return pruneQueryGetCount;
    },
  };
}

test('executeSyncSankhyaClientesModuleAction imports rows, reuses CEP lookup cache and prunes inactive on full sync', async () => {
  const tenantId = 'tenant_1';
  const docId1 = `erp_cliente_${tenantId}_101`;
  const docId2 = `erp_cliente_${tenantId}_102`;

  const harness = createFirestoreHarness({
    existingDataByPath: {
      [`clientes/${docId1}`]: { createdAt: 'old_created' },
      [`clientes/${docId2}`]: { createdAt: 'old_created_2' },
    },
    existingErpDocs: [
      {
        id: docId1,
        data: { status: 'aprovado' },
      },
      {
        id: 'erp_cliente_tenant_1_999',
        data: { status: 'aprovado' },
      },
      {
        id: 'erp_cliente_tenant_1_888',
        data: { status: 'inativo' },
      },
    ],
  });

  const lookupCalls = [];
  const syncPatches = [];

  const rows = [
    { CODPARC: '101' },
    { CODPARC: '102' },
    { CODPARC: '0' },
  ];

  const result = await executeSyncSankhyaClientesModuleAction({
    firestore: harness.firestore,
    tenantId,
    baseUrl: 'https://api',
    bearerToken: 'b',
    xToken: 'x',
    codigosFiltro: [],
    buildSankhyaClientesSql: ({ codigosFiltro: filtro }) =>
      `SELECT ${Array.isArray(filtro) ? filtro.length : -1}`,
    executeSankhyaDbExplorerQuery: async () => ({
      rows,
      endpointPath: '/dbexplorer',
    }),
    buildClienteDocId: (_tenantId, codigo) => `erp_cliente_${_tenantId}_${codigo}`,
    readRowValueByAliases: (row, aliases) => row[aliases[0]],
    mapSankhyaClienteRow: ({ row, syncVersion }) => {
      if (row.CODPARC === '0') {
        return null;
      }
      return {
        id: `mapped_${row.CODPARC}`,
        tenantId,
        cep: '13000000',
        logradouro: null,
        bairro: null,
        syncVersion,
      };
    },
    lookupCepAddress: async (cep) => {
      lookupCalls.push(cep);
      return { logradouro: 'Rua A', bairro: 'Centro' };
    },
    updateTenantSyncState: async ({ patch }) => {
      syncPatches.push(patch);
    },
    loggerError: () => {},
  });

  assert.equal(result.sourceCount, 3);
  assert.equal(result.importedCount, 2);
  assert.equal(result.skippedInvalidCount, 1);
  assert.equal(result.prunedInactiveCount, 1);
  assert.equal(result.codigosFiltro.length, 0);

  assert.deepEqual(lookupCalls, ['13000000']);
  assert.equal(harness.getPruneQueryGetCount(), 1);

  const pruneSet = harness.sets.find(
    (entry) => entry.path === 'clientes/erp_cliente_tenant_1_999',
  );
  assert.ok(pruneSet);
  assert.equal(pruneSet.payload.status, 'inativo');

  assert.equal(syncPatches.length, 1);
  assert.equal(syncPatches[0].lastClientesSyncMode, 'full');
  assert.equal(syncPatches[0].lastClientesImportedCount, 2);
});

test('executeSyncSankhyaClientesModuleAction skips prune on filtered sync and reports mode', async () => {
  const harness = createFirestoreHarness();
  const syncPatches = [];

  const result = await executeSyncSankhyaClientesModuleAction({
    firestore: harness.firestore,
    tenantId: 'tenant_2',
    baseUrl: 'https://api',
    bearerToken: 'b',
    xToken: 'x',
    codigosFiltro: ['191', '1887'],
    buildSankhyaClientesSql: () => 'SELECT FILTERED',
    executeSankhyaDbExplorerQuery: async () => ({
      rows: [{ CODPARC: '191' }],
      endpointPath: '/dbexplorer_filtered',
    }),
    buildClienteDocId: (tenantId, codigo) => `erp_cliente_${tenantId}_${codigo}`,
    readRowValueByAliases: (row, aliases) => row[aliases[0]],
    mapSankhyaClienteRow: () => ({
      tenantId: 'tenant_2',
      cep: null,
      logradouro: null,
      bairro: null,
    }),
    lookupCepAddress: async () => null,
    updateTenantSyncState: async ({ patch }) => {
      syncPatches.push(patch);
    },
    loggerError: () => {},
  });

  assert.equal(result.importedCount, 1);
  assert.equal(result.prunedInactiveCount, 0);
  assert.deepEqual(result.codigosFiltro, ['191', '1887']);
  assert.match(result.message, /restrita aos codigos: 191, 1887/);

  assert.equal(harness.getPruneQueryGetCount(), 0);
  assert.equal(syncPatches.length, 1);
  assert.equal(syncPatches[0].lastClientesSyncMode, 'test_filtered');
  assert.equal(syncPatches[0].lastClientesEndpoint, '/dbexplorer_filtered');
});
