const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildClienteDocId,
  buildSankhyaClientesSql,
  mapSankhyaClienteRow,
  lookupCepAddress,
} = require('../../src/billing/sankhya_clientes_data_helpers');

test('buildClienteDocId keeps expected contract', () => {
  assert.equal(buildClienteDocId('tenant_1', '101'), 'erp_cliente_tenant_1_101');
  assert.equal(buildClienteDocId('tenant_1', 202), 'erp_cliente_tenant_1_202');
});

test('buildSankhyaClientesSql adds numeric filter codes only', () => {
  const sql = buildSankhyaClientesSql({
    codigosFiltro: ['101', '00102', '0', 'ABC', '', null, '101'],
  });

  assert.match(sql, /FROM TGFPAR PAR/);
  assert.match(sql, /LEFT JOIN TSICID CID/);
  assert.match(sql, /AND PAR\.CODPARC IN \(101, 102\)/);
  assert.ok(!sql.includes('ABC'));
});

test('mapSankhyaClienteRow maps payload and classification fallback', () => {
  const mapped = mapSankhyaClienteRow({
    tenantId: 'tenant_1',
    nowIso: '2026-11-18T00:00:00.000Z',
    syncBatchId: 'sync_1',
    syncVersion: 7,
    existingData: {
      createdAt: '2026-01-01T00:00:00.000Z',
      salePurpose: 'revenda',
    },
    row: {
      CODPARC: '191',
      RAZAOSOCIAL: 'Cliente LTDA',
      NOMEPARC: 'Cliente',
      CGC_CPF: '12.345.678/0001-99',
      TIPPESSOA: 'J',
      ATIVO: 'S',
      IDENTINSCESTAD: 'ISENTO',
      CLASSIFICMS: 'C',
      CEP: '13000-000',
      NUMEND: '10',
      COMPLEMENTO: 'Sala 2',
      NOMECID: 'Campinas',
      SIGLA_UF: 'sp',
      TELEFONE: '19 99999-9999',
      EMAIL: 'cliente@example.com',
      INSCMUN: '123',
    },
  });

  assert.ok(mapped);
  assert.equal(mapped.id, 'erp_cliente_tenant_1_191');
  assert.equal(mapped.taxProfile, 'nao_contribuinte');
  assert.equal(mapped.salePurpose, 'uso_consumo');
  assert.equal(mapped.status, 'aprovado');
  assert.equal(mapped.cep, '13000000');
  assert.equal(mapped.estado, 'SP');
  assert.equal(mapped.syncVersion, 7);
});

test('lookupCepAddress returns null on non-ok and parses address on success', async () => {
  const notFound = await lookupCepAddress('00000000', {
    fetchImpl: async () => ({ ok: false }),
  });
  assert.equal(notFound, null);

  const success = await lookupCepAddress('13000000', {
    fetchImpl: async () => ({
      ok: true,
      async json() {
        return { street: 'Rua A', neighborhood: 'Centro' };
      },
    }),
  });

  assert.deepEqual(success, {
    logradouro: 'Rua A',
    bairro: 'Centro',
  });
});
