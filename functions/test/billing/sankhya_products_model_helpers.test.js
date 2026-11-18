const test = require('node:test');
const assert = require('node:assert/strict');

const {
  mapSankhyaProductToFirestore,
  resolveInternalProductCode,
  nextTenantErpProductInternalSequence,
  buildProductDocId,
} = require('../../src/billing/sankhya_products_model_helpers');

test('buildProductDocId keeps ERP product id contract', () => {
  assert.equal(buildProductDocId('tenant_1', '123'), 'erp_prod_tenant_1_123');
  assert.equal(buildProductDocId('tenant_1', 7), 'erp_prod_tenant_1_7');
});

test('mapSankhyaProductToFirestore maps payload and tax fields', () => {
  const payload = mapSankhyaProductToFirestore({
    tenantId: 'tenant_1',
    nowIso: '2026-11-18T00:00:00.000Z',
    syncBatchId: 'batch_1',
    internalCode: 'ERP-000001',
    source: {
      codigoProduto: '2001',
      nome: 'Produto Teste',
      nomeGrupoProduto: 'Grupo A',
      volume: 'UN',
      marca: 'Marca X',
      ncm: '2203.00.00',
      cest: '12.345.67',
      referencia: 'EAN123',
      pesoBruto: '1.50',
      largura: '10',
      altura: '20',
      espessura: '30',
      ativo: true,
      complemento: 'Descricao longa',
    },
    productFiscal: {
      origemMercadoriaCst: '2',
      aliquotaIpiBase: 5.5,
    },
    existingData: {
      representedCompanyId: null,
      createdAt: '2026-10-01T00:00:00.000Z',
      grupoTributarioId: null,
    },
    nextSyncVersion: 3,
    ncmToGroupId: new Map([['22030000', 'grp_1']]),
    normalizeOrigemMercadoriaCst: (value) => String(value ?? '').trim() || null,
    toNumberOrNull: (value) => {
      if (value === null || value === undefined || value === '') {
        return null;
      }
      const n = Number(String(value).replace(',', '.'));
      return Number.isFinite(n) ? n : null;
    },
    normalizeDigits: (value) => String(value ?? '').replace(/\D+/g, ''),
    buildProductDocId,
  });

  assert.equal(payload.id, 'erp_prod_tenant_1_2001');
  assert.equal(payload.codigoInterno, 'ERP-000001');
  assert.equal(payload.descricao, 'Produto Teste');
  assert.equal(payload.grupoTributarioId, 'grp_1');
  assert.equal(payload.origemMercadoriaCst, '2');
  assert.equal(payload.aliquotaIpiBase, 5.5);
  assert.equal(payload.syncVersion, 3);
});

test('resolveInternalProductCode keeps existing manual code and falls back to sequence', async () => {
  const kept = await resolveInternalProductCode({
    firestore: {},
    tenantId: 'tenant_1',
    erpProductCode: '2001',
    existingData: { codigoInterno: 'MAN-001' },
    nextTenantErpProductInternalSequence: async () => 99,
  });
  assert.equal(kept, 'MAN-001');

  const generated = await resolveInternalProductCode({
    firestore: {},
    tenantId: 'tenant_1',
    erpProductCode: '2001',
    existingData: { codigoInterno: '2001' },
    nextTenantErpProductInternalSequence: async () => 42,
  });
  assert.equal(generated, 'ERP-000042');
});

test('nextTenantErpProductInternalSequence increments tenant counter with merge set', async () => {
  const ops = [];
  const tenantRef = { path: 'tenants/tenant_1' };

  const firestore = {
    collection(name) {
      assert.equal(name, 'tenants');
      return {
        doc(id) {
          assert.equal(id, 'tenant_1');
          return tenantRef;
        },
      };
    },
    async runTransaction(handler) {
      const transaction = {
        async get(ref) {
          ops.push({ type: 'get', ref });
          return {
            data() {
              return { erpInternalProductSequence: '7' };
            },
          };
        },
        set(ref, payload, options) {
          ops.push({ type: 'set', ref, payload, options });
        },
      };
      return handler(transaction);
    },
  };

  const next = await nextTenantErpProductInternalSequence({
    firestore,
    tenantId: 'tenant_1',
    readInt: (value) => Number.parseInt(String(value ?? '0'), 10) || 0,
    admin: {
      firestore: {
        FieldValue: {
          serverTimestamp: () => 'SERVER_TS',
        },
      },
    },
  });

  assert.equal(next, 8);
  const setOp = ops.find((item) => item.type === 'set');
  assert.ok(setOp);
  assert.equal(setOp.payload.erpInternalProductSequence, 8);
  assert.equal(setOp.payload.updatedAt, 'SERVER_TS');
  assert.equal(setOp.options.merge, true);
});
