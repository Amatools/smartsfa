const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildSankhyaOperationTypesSql,
  mapSankhyaOperationTypeRow,
} = require('../../src/billing/sankhya_operation_types_data_helpers');

test('buildSankhyaOperationTypesSql keeps expected source table and ordering', () => {
  const sql = buildSankhyaOperationTypesSql();

  assert.match(sql, /FROM TGFTOP T/);
  assert.match(sql, /WHERE T\.ATIVO = 'S'/);
  assert.match(sql, /ORDER BY T\.CODTIPOPER/);
});

test('mapSankhyaOperationTypeRow maps aliases and trims strings', () => {
  const mapped = mapSankhyaOperationTypeRow({
    codtipooper: ' 1200 ',
    descricao: ' Venda ',
    tipomovimento: ' V ',
    calcdifalpart: ' S ',
    calcicms: ' N ',
    calcfcpint: ' S ',
    calcfusttop: ' N ',
  });

  assert.deepEqual(mapped, {
    code: '1200',
    description: 'Venda',
    movementType: 'V',
    calcDifalPart: 'S',
    calcIcms: 'N',
    calcFcpInt: 'S',
    calcFustTop: 'N',
  });
});

test('mapSankhyaOperationTypeRow returns null when code is missing', () => {
  const mapped = mapSankhyaOperationTypeRow({
    descricao: 'Sem codigo',
  });

  assert.equal(mapped, null);
});
