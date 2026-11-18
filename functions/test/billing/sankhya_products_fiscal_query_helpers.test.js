const test = require('node:test');
const assert = require('node:assert/strict');

const {
  fetchSankhyaProductsFiscalData,
  buildSankhyaProductFiscalSql,
} = require('../../src/billing/sankhya_products_fiscal_query_helpers');

test('buildSankhyaProductFiscalSql renders IN clause from normalized numeric codes', () => {
  const sql = buildSankhyaProductFiscalSql({
    productCodes: ['001', '20', 'abc'],
    normalizeSankhyaNumericCodeList: () => ['1', '20'],
  });

  assert.match(sql, /FROM TGFPRO PRO/);
  assert.match(sql, /PRO\.CODPROD IN \(1, 20\)/);
});

test('fetchSankhyaProductsFiscalData returns empty response when no codes are normalized', async () => {
  let queryCalls = 0;

  const result = await fetchSankhyaProductsFiscalData({
    baseUrl: 'https://api',
    bearerToken: 'b',
    xToken: 'x',
    productCodes: ['x'],
    normalizeSankhyaNumericCodeList: () => [],
    executeSankhyaDbExplorerQuery: async () => {
      queryCalls += 1;
      return { endpointPath: '/db', rows: [] };
    },
    toCodeString: (value) => String(value ?? '').trim(),
    readRowValueByAliases: () => null,
    isZeroCode: () => false,
    normalizeOrigemMercadoriaCst: () => null,
    toNumberOrNull: () => null,
  });

  assert.equal(queryCalls, 0);
  assert.equal(result.endpointPath, null);
  assert.equal(result.rowCount, 0);
  assert.equal(result.byProductCode.size, 0);
});

test('fetchSankhyaProductsFiscalData maps fiscal rows by product code', async () => {
  const captured = [];

  const result = await fetchSankhyaProductsFiscalData({
    baseUrl: 'https://api',
    bearerToken: 'b',
    xToken: 'x',
    productCodes: ['10', '11'],
    normalizeSankhyaNumericCodeList: (codes) =>
      codes
        .map((item) => String(item ?? '').trim())
        .filter((item) => /^\d+$/.test(item)),
    executeSankhyaDbExplorerQuery: async (input) => {
      captured.push(input);
      return {
        endpointPath: '/dbexplorer',
        rows: [
          {
            CODPROD: '10',
            ORIGPROD: '2',
            IPI: '5.5',
          },
          {
            CodigoProduto: '0',
            OrigemMercadoria: '1',
            AliquotaIPI: '9.0',
          },
          {
            CODIGOPRODUTO: '11',
            ORIGEMMERCADORIA: null,
            PERCENTUAL: '3,2',
          },
        ],
      };
    },
    toCodeString: (value) => String(value ?? '').trim(),
    readRowValueByAliases: (row, aliases) => {
      for (const key of aliases) {
        if (Object.prototype.hasOwnProperty.call(row, key)) {
          return row[key];
        }
      }
      return null;
    },
    isZeroCode: (value) => /^0+$/.test(String(value ?? '').trim()),
    normalizeOrigemMercadoriaCst: (value) => {
      const raw = String(value ?? '').trim();
      if (!raw) {
        return null;
      }
      return raw;
    },
    toNumberOrNull: (value) => {
      if (value === null || value === undefined || value === '') {
        return null;
      }
      const num = Number(String(value).replace(',', '.'));
      return Number.isFinite(num) ? num : null;
    },
  });

  assert.equal(captured.length, 1);
  assert.equal(captured[0].baseUrl, 'https://api');
  assert.equal(captured[0].bearerToken, 'b');
  assert.equal(captured[0].xToken, 'x');
  assert.match(captured[0].sql, /PRO\.CODPROD IN \(10, 11\)/);

  assert.equal(result.endpointPath, '/dbexplorer');
  assert.equal(result.rowCount, 3);
  assert.equal(result.byProductCode.size, 2);

  assert.deepEqual(result.byProductCode.get('10'), {
    origemMercadoriaCst: '2',
    aliquotaIpiBase: 5.5,
  });
  assert.deepEqual(result.byProductCode.get('11'), {
    origemMercadoriaCst: null,
    aliquotaIpiBase: 3.2,
  });
});
