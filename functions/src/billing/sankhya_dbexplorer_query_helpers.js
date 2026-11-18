async function executeSankhyaDbExplorerQuery({
  baseUrl,
  bearerToken,
  xToken,
  sql,
  endpointPaths,
  fetchImpl,
  tryParseJson,
  extractSankhyaXmlError,
  normalizeDbExplorerRows,
}) {
  const payloadVariants = [
    {
      name: 'serviceName_requestBody_sql',
      payload: {
        serviceName: 'DbExplorerSP.executeQuery',
        requestBody: { sql },
      },
    },
    {
      name: 'requestBody_sql',
      payload: {
        requestBody: { sql },
      },
    },
    {
      name: 'requestBody_query',
      payload: {
        requestBody: { query: sql },
      },
    },
  ];

  const failures = [];
  for (const endpointPath of endpointPaths) {
    for (const payloadVariant of payloadVariants) {
      const response = await fetchImpl(`${baseUrl}${endpointPath}`, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          Authorization: `Bearer ${bearerToken}`,
          'content-type': 'application/json',
          'x-token': xToken,
        },
        body: JSON.stringify(payloadVariant.payload),
        signal: AbortSignal.timeout(30000),
      });

      const bodyText = await response.text();
      const parsed = tryParseJson(bodyText);
      const xmlError = extractSankhyaXmlError(bodyText);
      if (response.ok) {
        if (xmlError) {
          failures.push({
            endpointPath,
            payloadVariant: payloadVariant.name,
            status: response.status,
            bodyPreview: xmlError,
          });
          continue;
        }
        return {
          endpointPath,
          payloadVariant: payloadVariant.name,
          rows: normalizeDbExplorerRows(parsed),
        };
      }

      failures.push({
        endpointPath,
        payloadVariant: payloadVariant.name,
        status: response.status,
        bodyPreview: bodyText.slice(0, 220),
      });
    }
  }

  const details = failures
    .map(
      (item) =>
        `${item.endpointPath} [${item.payloadVariant}] -> HTTP ${item.status}: ${item.bodyPreview}`,
    )
    .join(' | ')
    .slice(0, 1800);

  throw new Error(`DbExplorer executeQuery falhou. Tentativas: ${details}`);
}

function extractSankhyaXmlError(bodyText) {
  if (!bodyText || !bodyText.includes('<serviceResponse')) {
    return null;
  }

  const statusMatch = bodyText.match(/status="(\d+)"/i);
  if (!statusMatch || statusMatch[1] !== '0') {
    return null;
  }

  const cdataMatch = bodyText.match(
    /<statusMessage><!\[CDATA\[(.*?)\]\]><\/statusMessage>/is,
  );
  const encoded = String(cdataMatch?.[1] ?? '').trim();
  if (!encoded) {
    return 'Sankhya XML status=0 (sem mensagem detalhada).';
  }

  try {
    const decoded = Buffer.from(encoded, 'base64').toString('latin1').trim();
    return decoded || `Sankhya XML status=0: ${encoded}`;
  } catch {
    return `Sankhya XML status=0: ${encoded}`;
  }
}

function normalizeDbExplorerRows(payload) {
  if (!payload || typeof payload !== 'object') {
    return [];
  }

  const root =
    payload.responseBody && typeof payload.responseBody === 'object'
      ? payload.responseBody
      : payload;
  const rawRows = Array.isArray(root.rows) ? root.rows : [];
  if (rawRows.length === 0) {
    return [];
  }

  if (
    rawRows.every(
      (row) => row && typeof row === 'object' && !Array.isArray(row),
    )
  ) {
    return rawRows;
  }

  const fields = Array.isArray(root.fieldsMetadata) ? root.fieldsMetadata : [];
  if (fields.length === 0) {
    return [];
  }

  return rawRows
    .filter((row) => Array.isArray(row))
    .map((row) => {
      const mapped = {};
      for (let index = 0; index < fields.length; index++) {
        const fieldName = String(fields[index]?.name ?? '').trim();
        if (!fieldName) {
          continue;
        }
        mapped[fieldName] = row[index] ?? null;
      }
      return mapped;
    });
}

module.exports = {
  executeSankhyaDbExplorerQuery,
  extractSankhyaXmlError,
  normalizeDbExplorerRows,
};
