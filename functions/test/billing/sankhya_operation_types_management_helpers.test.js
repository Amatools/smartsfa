const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeFetchSankhyaOperationTypesAction,
} = require('../../src/billing/sankhya_operation_types_management_helpers');

function createDeps(overrides = {}) {
  const calls = {
    authenticate: [],
    query: [],
    map: [],
  };

  const deps = {
    requestBody: {},
    authenticateInSankhya: async (input) => {
      calls.authenticate.push(input);
      return { access_token: 'bearer_1' };
    },
    readBearerToken: (payload) => String(payload?.access_token ?? '').trim(),
    buildSankhyaOperationTypesSql: () => 'SELECT 1',
    executeSankhyaDbExplorerQuery: async (input) => {
      calls.query.push(input);
      return {
        endpointPath: '/dbexplorer',
        rows: [{ id: 1 }, { id: 2 }],
      };
    },
    mapSankhyaOperationTypeRow: (row) => {
      calls.map.push(row);
      return {
        code: String(row.id),
        description: `row_${row.id}`,
      };
    },
    ...overrides,
  };

  return { deps, calls };
}

test('executeFetchSankhyaOperationTypesAction validates environment', async () => {
  const { deps } = createDeps({
    requestBody: {
      environment: 'dev',
      clientId: 'id',
      clientSecret: 'secret',
      xToken: 'token',
    },
  });

  const result = await executeFetchSankhyaOperationTypesAction(deps);

  assert.equal(result.status, 400);
  assert.equal(result.body.error, 'invalid_environment');
});

test('executeFetchSankhyaOperationTypesAction validates credentials', async () => {
  const { deps } = createDeps({
    requestBody: {
      environment: 'prod',
      clientId: '',
      clientSecret: 'secret',
      xToken: 'token',
    },
  });

  const result = await executeFetchSankhyaOperationTypesAction(deps);

  assert.equal(result.status, 400);
  assert.equal(result.body.error, 'missing_credentials');
});

test('executeFetchSankhyaOperationTypesAction returns missing_bearer', async () => {
  const { deps } = createDeps({
    requestBody: {
      environment: 'prod',
      clientId: 'id',
      clientSecret: 'secret',
      xToken: 'token',
    },
    readBearerToken: () => '',
  });

  const result = await executeFetchSankhyaOperationTypesAction(deps);

  assert.equal(result.status, 502);
  assert.equal(result.body.error, 'missing_bearer');
});

test('executeFetchSankhyaOperationTypesAction returns mapped rows on success', async () => {
  const { deps, calls } = createDeps({
    requestBody: {
      environment: 'homolog',
      clientId: 'id_h',
      clientSecret: 'secret_h',
      xToken: 'token_h',
    },
    mapSankhyaOperationTypeRow: (row) => {
      calls.map.push(row);
      if (row.id === 2) {
        return null;
      }
      return {
        code: String(row.id),
        description: `row_${row.id}`,
      };
    },
  });

  const result = await executeFetchSankhyaOperationTypesAction(deps);

  assert.equal(result.status, 200);
  assert.equal(result.body.ok, true);
  assert.equal(result.body.environment, 'homolog');
  assert.equal(result.body.endpoint, '/dbexplorer');
  assert.equal(result.body.rowCount, 1);
  assert.equal(result.body.operationTypes.length, 1);

  assert.equal(calls.authenticate.length, 1);
  assert.equal(calls.authenticate[0].baseUrl, 'https://api.sandbox.sankhya.com.br');
  assert.equal(calls.query.length, 1);
  assert.equal(calls.query[0].sql, 'SELECT 1');
  assert.equal(calls.map.length, 2);
});

test('executeFetchSankhyaOperationTypesAction maps query failures', async () => {
  const { deps } = createDeps({
    requestBody: {
      environment: 'prod',
      clientId: 'id_p',
      clientSecret: 'secret_p',
      xToken: 'token_p',
    },
    executeSankhyaDbExplorerQuery: async () => {
      throw new Error('dbexplorer_failed');
    },
  });

  const result = await executeFetchSankhyaOperationTypesAction(deps);

  assert.equal(result.status, 502);
  assert.equal(result.body.error, 'sankhya_operation_types_failed');
  assert.equal(result.body.message, 'dbexplorer_failed');
});
