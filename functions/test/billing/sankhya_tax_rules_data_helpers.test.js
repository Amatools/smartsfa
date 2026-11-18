const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildSankhyaTaxRulesSql,
  mapSankhyaTaxRuleRow,
  buildTaxFingerprintKey,
  computeFingerprintHash,
  buildAutoGroupName,
  buildAutoGroupDescription,
  normalizeDigits,
  sanitizeKeyToken,
  toIsoDateOrNull,
} = require('../../src/billing/sankhya_tax_rules_data_helpers');

test('buildSankhyaTaxRulesSql keeps expected source table and status projection', () => {
  const sql = buildSankhyaTaxRulesSql();

  assert.match(sql, /FROM TGFICM ICM/);
  assert.match(sql, /'active' AS STATUS/);
  assert.match(sql, /ORDER BY\s*\n\s*UFORIGEM,/);
});

test('mapSankhyaTaxRuleRow maps normalized payload', () => {
  const mapped = mapSankhyaTaxRuleRow({
    tenantId: 'tenant_1',
    nowIso: '2026-11-18T00:00:00.000Z',
    syncBatchId: 'batch_1',
    syncVersion: 10,
    row: {
      CODTAB: '100',
      SEQUENCIA: '1',
      IDALIQ: '500',
      UFORIGEM: 'sp',
      UFDESTINO: 'mg',
      NCM: '2203.00.00',
      CEST: '12.345.67',
      TIPOST: 'mva',
      ALIQUOTADESTINO: '18',
      ALIQUOTACREDITO: '12',
      MVA: '40',
      REDUCAOBASEICMSST: '5',
      BASECALCULOICMSST: '10',
      ALIQUOTADIFAL: '2',
      PERCFCPINTERNO: '1.5',
      PERCSTFCPINTERNO: '0.5',
      STATUS: 'active',
      EXCECAOFISCAL: 'ex',
      GRUPOFISCALID: 'GF1',
      CST_CSOSN: '060',
      PRIORIDADE: '123',
      VIGENCIAINICIAL: '2026-11-01',
      VIGENCIAFINAL: '2026-11-30',
    },
  });

  assert.ok(mapped);
  assert.equal(mapped.id, 'erp_tax_tenant_1_100_1_500_SP_MG_22030000_1234567');
  assert.equal(mapped.ufOrigem, 'SP');
  assert.equal(mapped.ufDestino, 'MG');
  assert.equal(mapped.ncm, '2203.00.00');
  assert.equal(mapped.cest, '12.345.67');
  assert.equal(mapped.aliquotaDestino, 18);
  assert.equal(mapped.priority, 123);
  assert.equal(mapped.syncVersion, 10);
});

test('mapSankhyaTaxRuleRow drops ncm rows without fiscal numeric values', () => {
  const mapped = mapSankhyaTaxRuleRow({
    tenantId: 'tenant_1',
    nowIso: '2026-11-18T00:00:00.000Z',
    syncBatchId: 'batch_1',
    syncVersion: 10,
    row: {
      CODTAB: '100',
      SEQUENCIA: '1',
      IDALIQ: '500',
      UFORIGEM: 'SP',
      UFDESTINO: 'RJ',
      NCM: '10010010',
      ALIQUOTADESTINO: '0',
      ALIQUOTACREDITO: '0',
      MVA: '0',
      REDUCAOBASEICMSST: '0',
      BASECALCULOICMSST: '0',
      ALIQUOTADIFAL: '0',
      PERCFCPINTERNO: '0',
      PERCSTFCPINTERNO: '0',
    },
  });

  assert.equal(mapped, null);
});

test('fingerprint helpers are deterministic across row order', () => {
  const rowA = {
    ufOrigem: 'SP',
    ufDestino: 'RJ',
    aliquotaDestino: 18,
    aliquotaCredito: 12,
    aliquotaDifal: 2,
    mvaIva: 40,
    stBaseReductionPercent: 0,
    stBaseAmount: 0,
    stCalculationType: 'mva',
    cstCsosn: '060',
    aliquotaFcp: 1,
    aliquotaFcpSt: 0.5,
  };
  const rowB = {
    ...rowA,
    ufDestino: 'MG',
  };

  const key1 = buildTaxFingerprintKey([rowA, rowB]);
  const key2 = buildTaxFingerprintKey([rowB, rowA]);
  assert.equal(key1, key2);
  assert.equal(computeFingerprintHash(key1).length, 16);
});

test('group label, normalization and date helpers keep expected behavior', () => {
  const name = buildAutoGroupName(
    [{ aliquotaDestino: 18, mvaIva: 40, ufDestino: 'RJ' }],
    2,
  );
  assert.match(name, /ICMS 18%/);

  const description = buildAutoGroupDescription(
    [{ ufDestino: 'RJ' }, { ufDestino: 'SP' }],
    ['22030000', '22030010'],
  );
  assert.match(description, /2 NCMs/);
  assert.match(description, /2 UF\(s\)/);

  assert.equal(normalizeDigits('12.345-67'), '1234567');
  assert.equal(sanitizeKeyToken(' São Paulo ', 'x'), 'Sao_Paulo');
  assert.equal(toIsoDateOrNull('18/11/2026', false), '2026-11-18T00:00:00.000Z');
  assert.equal(toIsoDateOrNull('18/11/2026', true), '2026-11-18T23:59:59.999Z');
});
