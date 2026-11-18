const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeSankhyaDbExplorerQuery,
  extractSankhyaXmlError,
  normalizeDbExplorerRows,
} = require('../../src/billing/sankhya_dbexplorer_query_helpers');

test('extractSankhyaXmlError decodes base64 message from status=0 XML', () => {
  const message = 'Falha de permissao';
  const encoded = Buffer.from(message, 'latin1').toString('base64');
  const xml = `<serviceResponse status="0"><statusMessage><![CDATA[${encoded}]]></statusMessage></serviceResponse>`;

  assert.equal(extractSankhyaXmlError(xml), message);
  assert.equal(extractSankhyaXmlError('<serviceResponse status="1"></serviceResponse>'), null);
});

test('normalizeDbExplorerRows maps matrix rows using fieldsMetadata', () => {
  const mapped = normalizeDbExplorerRows({
    responseBody: {
      fieldsMetadata: [{ name: 'CODPROD' }, { name: 'ALIQ' }],
      rows: [
        ['10', 5.5],
        ['11', 6.1],
      ],
    },
  });

  assert.deepEqual(mapped, [
    { CODPROD: '10', ALIQ: 5.5 },
    { CODPROD: '11', ALIQ: 6.1 },
  ]);

  const passthrough = normalizeDbExplorerRows({ rows: [{ A: 1 }, { A: 2 }] });
  assert.deepEqual(passthrough, [{ A: 1 }, { A: 2 }]);
});

test('executeSankhyaDbExplorerQuery retries xml error response and returns normalized rows', async () => {
  const xmlErrorBody =
    '<serviceResponse status="0"><statusMessage><![CDATA[RXJybw==]]></statusMessage></serviceResponse>';
  const jsonBody = JSON.stringify({
    responseBody: {
      fieldsMetadata: [{ name: 'CODPROD' }],
      rows: [['123']],
    },
  });

  let call = 0;
  const result = await executeSankhyaDbExplorerQuery({
    baseUrl: 'https://api',
    bearerToken: 'b',
    xToken: 'x',
    sql: 'SELECT 1',
    endpointPaths: ['/mge/service.sbr'],
    fetchImpl: async () => {
      call += 1;
      if (call === 1) {
        return {
          ok: true,
          status: 200,
          async text() {
            return xmlErrorBody;
          },
        };
      }
      return {
        ok: true,
        status: 200,
        async text() {
          return jsonBody;
        },
      };
    },
    tryParseJson: (text) => {
      try {
        return JSON.parse(text);
      } catch {
        return null;
      }
    },
    extractSankhyaXmlError,
    normalizeDbExplorerRows,
  });

  assert.equal(call, 2);
  assert.equal(result.endpointPath, '/mge/service.sbr');
  assert.equal(result.payloadVariant, 'requestBody_sql');
  assert.deepEqual(result.rows, [{ CODPROD: '123' }]);
});

test('executeSankhyaDbExplorerQuery throws aggregated error when all attempts fail', async () => {
  let call = 0;

  await assert.rejects(
    executeSankhyaDbExplorerQuery({
      baseUrl: 'https://api',
      bearerToken: 'b',
      xToken: 'x',
      sql: 'SELECT 1',
      endpointPaths: ['/e1'],
      fetchImpl: async () => {
        call += 1;
        return {
          ok: false,
          status: 500,
          async text() {
            return `boom_${call}`;
          },
        };
      },
      tryParseJson: () => null,
      extractSankhyaXmlError,
      normalizeDbExplorerRows,
    }),
    /DbExplorer executeQuery falhou/,
  );

  assert.equal(call, 3);
});
