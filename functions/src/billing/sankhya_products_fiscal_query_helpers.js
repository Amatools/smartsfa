function buildSankhyaProductFiscalSql({
  productCodes,
  normalizeSankhyaNumericCodeList,
}) {
  const safeCodes = normalizeSankhyaNumericCodeList(productCodes);
  if (safeCodes.length === 0) {
    return '';
  }

  const codesInClause = safeCodes.join(', ');
  return `
SELECT
    TO_CHAR(PRO.CODPROD) AS CodigoProduto,
    NVL(TO_CHAR(PRO.ORIGPROD), '0') AS OrigemMercadoria,
    COALESCE(
        IPI_ESPECIFICO.PERCENTUAL,
        TO_NUMBER(REPLACE(NCM.IPI, ',', '.')),
        0
    ) AS AliquotaIPI
FROM TGFPRO PRO
LEFT JOIN TGFIPI IPI_ESPECIFICO ON PRO.CODIPI = IPI_ESPECIFICO.CODIPI
LEFT JOIN TGFNCM NCM ON LTRIM(REPLACE(NCM.CODNCM, '.', ''), '0') = LTRIM(REPLACE(PRO.NCM, '.', ''), '0')
WHERE PRO.ATIVO = 'S'
  AND PRO.CODPROD IN (${codesInClause})
`.trim();
}

async function fetchSankhyaProductsFiscalData({
  baseUrl,
  bearerToken,
  xToken,
  productCodes,
  normalizeSankhyaNumericCodeList,
  executeSankhyaDbExplorerQuery,
  toCodeString,
  readRowValueByAliases,
  isZeroCode,
  normalizeOrigemMercadoriaCst,
  toNumberOrNull,
}) {
  const normalizedCodes = normalizeSankhyaNumericCodeList(productCodes);
  if (normalizedCodes.length === 0) {
    return {
      endpointPath: null,
      rowCount: 0,
      byProductCode: new Map(),
    };
  }

  const sql = buildSankhyaProductFiscalSql({
    productCodes: normalizedCodes,
    normalizeSankhyaNumericCodeList,
  });
  const queryResult = await executeSankhyaDbExplorerQuery({
    baseUrl,
    bearerToken,
    xToken,
    sql,
  });

  const byProductCode = new Map();
  for (const row of queryResult.rows) {
    const productCode = toCodeString(
      readRowValueByAliases(row, [
        'CodigoProduto',
        'CODIGOPRODUTO',
        'CODPROD',
      ]),
    );
    if (!productCode || isZeroCode(productCode)) {
      continue;
    }

    const origemMercadoriaCst = normalizeOrigemMercadoriaCst(
      readRowValueByAliases(row, [
        'OrigemMercadoria',
        'ORIGEMMERCADORIA',
        'ORIGPROD',
      ]),
    );
    const aliquotaIpiBase = toNumberOrNull(
      readRowValueByAliases(row, [
        'AliquotaIPI',
        'ALIQUOTAIPI',
        'PERCENTUAL',
        'IPI',
      ]),
    );

    byProductCode.set(productCode, {
      origemMercadoriaCst,
      aliquotaIpiBase,
    });
  }

  return {
    endpointPath: queryResult.endpointPath,
    rowCount: queryResult.rows.length,
    byProductCode,
  };
}

module.exports = {
  fetchSankhyaProductsFiscalData,
  buildSankhyaProductFiscalSql,
};
