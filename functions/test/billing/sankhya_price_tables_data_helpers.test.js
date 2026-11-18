const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizePriceTableCodes,
  buildTenantProductIndex,
  upsertPriceTableDocument,
  upsertDefaultPriceTableDocument,
  readPriceRowsFromPayload,
  buildPriceTableDocId,
  buildDefaultPriceTableDocId,
  buildDefaultProductBasePriceDocId,
  normalizeTextToken,
  buildProductBasePriceDocId,
} = require('../../src/billing/sankhya_price_tables_data_helpers');

test('normalizePriceTableCodes parses array and string with dedupe', () => {
  assert.deepEqual(normalizePriceTableCodes(['100', '200', '100', 'A']), [
    '100',
    '200',
  ]);
  assert.deepEqual(normalizePriceTableCodes(' 10,20;10|30 abc '), [
    '10',
    '20',
    '30',
  ]);
});

test('build ids helpers keep expected contract', () => {
  assert.equal(buildPriceTableDocId('t1', '100'), 'erp_pt_t1_100');
  assert.equal(buildDefaultPriceTableDocId('t1'), 'pt_default_t1');
  assert.equal(
    buildDefaultProductBasePriceDocId({
      tenantId: 't1',
      productId: 'p1',
      defaultPriceTableDocId: 'pt_default_t1',
    }),
    'pbp_t1_p1_pt_default_t1',
  );
  assert.equal(
    buildProductBasePriceDocId({
      tenantId: 't1',
      tableCode: '100',
      productId: 'p1',
      localCode: '1',
      unitCode: 'cx',
      controlCode: 'Lote 1',
    }),
    'erp_pbp_t1_100_p1_1_cx_Lote_1',
  );
});

test('readPriceRowsFromPayload and normalizeTextToken keep behavior', () => {
  assert.deepEqual(readPriceRowsFromPayload({ produtos: [1, 2] }), [1, 2]);
  assert.deepEqual(readPriceRowsFromPayload({ precos: [3] }), [3]);
  assert.deepEqual(readPriceRowsFromPayload({ other: [] }), []);

  assert.equal(normalizeTextToken('', 'UN'), 'UN');
  assert.equal(normalizeTextToken('  Unid. Caixa  ', 'UN'), 'Unid_Caixa');
  assert.equal(normalizeTextToken('###', 'FALLBACK'), 'FALLBACK');
});

test('buildTenantProductIndex indexes active products by ERP and fabricante codes', async () => {
  const docs = [
    {
      id: 'prod_1',
      data() {
        return {
          erpProductId: '2001',
          codigoFabricante: 'F001',
          deletedAt: null,
        };
      },
    },
    {
      id: 'prod_2',
      data() {
        return {
          erpProductId: '0',
          codigoFabricante: 'F002',
          deletedAt: null,
        };
      },
    },
    {
      id: 'prod_deleted',
      data() {
        return {
          erpProductId: '3003',
          codigoFabricante: 'F003',
          deletedAt: '2026-01-01T00:00:00.000Z',
        };
      },
    },
  ];

  const firestore = {
    collection(name) {
      assert.equal(name, 'produtos');
      return {
        where(field, op, value) {
          assert.equal(field, 'tenantId');
          assert.equal(op, '==');
          assert.equal(value, 'tenant_1');
          return {
            select() {
              return {
                async get() {
                  return { docs };
                },
              };
            },
          };
        },
      };
    },
  };

  const index = await buildTenantProductIndex({
    firestore,
    tenantId: 'tenant_1',
  });

  assert.equal(index.get('2001').productId, 'prod_1');
  assert.equal(index.get('F001').productId, 'prod_1');
  assert.equal(index.get('F002').productId, 'prod_2');
  assert.equal(index.has('3003'), false);
  assert.equal(index.has('0'), false);
});

test('upsert price table helpers write expected documents', async () => {
  const sets = [];

  function makeDocRef(path, existingData) {
    return {
      async get() {
        if (existingData) {
          return {
            exists: true,
            data: () => existingData,
          };
        }
        return { exists: false, data: () => undefined };
      },
      async set(payload, options) {
        sets.push({ path, payload, options });
      },
    };
  }

  const firestore = {
    collection(name) {
      return {
        doc(id) {
          const path = `${name}/${id}`;
          if (name === 'tabelas_preco' && id === 'erp_pt_t1_100') {
            return makeDocRef(path, { nome: 'Nome Existente', createdAt: 'old' });
          }
          return makeDocRef(path, null);
        },
      };
    },
  };

  await upsertPriceTableDocument({
    firestore,
    tenantId: 't1',
    priceTableDocId: 'erp_pt_t1_100',
    tableCode: '100',
    nowIso: '2026-11-18T00:00:00.000Z',
  });

  await upsertDefaultPriceTableDocument({
    firestore,
    tenantId: 't1',
    defaultPriceTableDocId: 'pt_default_t1',
    primaryTableCode: '100',
    nowIso: '2026-11-18T00:00:00.000Z',
  });

  const wroteNamedTable = sets.find((entry) => entry.path === 'tabelas_preco/erp_pt_t1_100');
  const wroteDefaultTable = sets.find((entry) => entry.path === 'tabelas_preco/pt_default_t1');
  const wroteTenantDefaults = sets.find((entry) => entry.path === 'tenants/t1');

  assert.ok(wroteNamedTable);
  assert.equal(wroteNamedTable.payload.nome, 'Nome Existente');
  assert.equal(wroteNamedTable.payload.createdAt, 'old');
  assert.equal(wroteNamedTable.options.merge, true);

  assert.ok(wroteDefaultTable);
  assert.equal(wroteDefaultTable.payload.id, 'pt_default_t1');
  assert.equal(wroteDefaultTable.options.merge, true);

  assert.ok(wroteTenantDefaults);
  assert.equal(wroteTenantDefaults.payload.defaultPriceTableIds.tenant_default, 'pt_default_t1');
  assert.equal(wroteTenantDefaults.options.merge, true);
});
