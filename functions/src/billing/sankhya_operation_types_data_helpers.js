function buildSankhyaOperationTypesSql() {
  return `
SELECT
    T.CODTIPOPER AS CodTipoOper,
    T.DESCROPER AS Descricao,
    T.TIPMOV AS TipoMovimento,
    T.CALCDIFALPART AS CalcDifalPart,
    T.CALCICMS AS CalcIcms,
    T.CALCFCPINT AS CalcFcpInt,
    T.CALCFUSTTOP AS CalcFustTop
FROM TGFTOP T
WHERE T.ATIVO = 'S'
  AND T.DHALTER = (
        SELECT MAX(T2.DHALTER) FROM TGFTOP T2 WHERE T2.CODTIPOPER = T.CODTIPOPER
      )
ORDER BY T.CODTIPOPER
`.trim();
}

function mapSankhyaOperationTypeRow(row) {
  const code = toCodeString(
    readRowValueByAliases(row, ['CodTipoOper', 'CODTIPOOPER']),
  );
  if (!code) {
    return null;
  }

  return {
    code,
    description: String(
      readRowValueByAliases(row, ['Descricao', 'DESCRICAO']) ?? '',
    ).trim(),
    movementType: String(
      readRowValueByAliases(row, ['TipoMovimento', 'TIPOMOVIMENTO']) ?? '',
    ).trim(),
    calcDifalPart: String(
      readRowValueByAliases(row, ['CalcDifalPart', 'CALCDIFALPART']) ?? '',
    ).trim(),
    calcIcms: String(
      readRowValueByAliases(row, ['CalcIcms', 'CALCICMS']) ?? '',
    ).trim(),
    calcFcpInt: String(
      readRowValueByAliases(row, ['CalcFcpInt', 'CALCFCPINT']) ?? '',
    ).trim(),
    calcFustTop: String(
      readRowValueByAliases(row, ['CalcFustTop', 'CALCFUSTTOP']) ?? '',
    ).trim(),
  };
}

function toCodeString(value) {
  if (value === null || value === undefined) {
    return '';
  }

  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      return '';
    }
    return String(Math.trunc(value));
  }

  return String(value).trim();
}

function readRowValueByAliases(row, aliases) {
  if (!row || typeof row !== 'object') {
    return undefined;
  }

  for (const alias of aliases) {
    if (Object.prototype.hasOwnProperty.call(row, alias)) {
      return row[alias];
    }
  }

  const loweredMap = new Map(
    Object.entries(row).map(([key, value]) => [key.toLowerCase(), value]),
  );
  for (const alias of aliases) {
    const value = loweredMap.get(String(alias).toLowerCase());
    if (value !== undefined) {
      return value;
    }
  }

  return undefined;
}

module.exports = {
  buildSankhyaOperationTypesSql,
  mapSankhyaOperationTypeRow,
};
