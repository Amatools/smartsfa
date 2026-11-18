function normalizeSankhyaNumericCodeList(values) {
  const seen = new Set();
  const normalized = [];

  for (const item of values || []) {
    const token = String(item ?? '').trim();
    if (!token) {
      continue;
    }
    if (!/^\d+$/.test(token)) {
      continue;
    }

    const numeric = Number(token);
    if (!Number.isFinite(numeric) || numeric === 0) {
      continue;
    }

    const clean = String(Number.parseInt(token, 10));
    if (!clean || seen.has(clean)) {
      continue;
    }
    seen.add(clean);
    normalized.push(clean);
  }

  return normalized;
}

function buildSankhyaProductImageChunksSql(
  productCodes,
  {
    chunkSize = 1800,
    normalizeCodeList = normalizeSankhyaNumericCodeList,
  } = {},
) {
  const safeCodes = normalizeCodeList(productCodes);
  if (safeCodes.length === 0) {
    return '';
  }

  const codesInClause = safeCodes.join(', ');
  return `
SELECT
    TO_CHAR(P.CODPROD) AS CodigoProduto,
    LEVEL AS ChunkIndex,
    RAWTOHEX(
      DBMS_LOB.SUBSTR(
        P.IMAGEM,
        ${chunkSize},
        ((LEVEL - 1) * ${chunkSize}) + 1
      )
    ) AS ChunkHex
FROM TGFPRO P
WHERE P.CODPROD IN (${codesInClause})
  AND P.ATIVO = 'S'
  AND P.IMAGEM IS NOT NULL
CONNECT BY PRIOR P.CODPROD = P.CODPROD
   AND PRIOR SYS_GUID() IS NOT NULL
   AND LEVEL <= CEIL(DBMS_LOB.GETLENGTH(P.IMAGEM) / ${chunkSize})
ORDER BY P.CODPROD, LEVEL
`.trim();
}

function detectImageFormat(buffer) {
  if (!buffer || buffer.length < 4) {
    return 'jpg';
  }

  if (
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47
  ) {
    return 'png';
  }

  return 'jpg';
}

function buildFirebaseDownloadUrl({ bucketName, storagePath, token }) {
  const encodedPath = encodeURIComponent(storagePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedPath}?alt=media&token=${token}`;
}

module.exports = {
  buildSankhyaProductImageChunksSql,
  detectImageFormat,
  buildFirebaseDownloadUrl,
};
