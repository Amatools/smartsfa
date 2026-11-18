const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeSyncSankhyaPriceTablesNightlyAction,
} = require('../../src/billing/sankhya_price_tables_sync_management_helpers');

function createFirestoreTenants(docs) {
  return {
    collection(name) {
      assert.equal(name, 'tenants');
      return {
        async get() {
          return { docs };
        },
      };
    },
  };
}

function createTenantDoc(id, data) {
  return {
    id,
    data() {
      return data;
    },
  };
}

test('executeSyncSankhyaPriceTablesNightlyAction skips tenants without valid sankhya credentials', async () => {
  const firestore = createFirestoreTenants([
    createTenantDoc('tenant_invalid_provider', {
      erpIntegration: {
        provider: 'other',
        environment: 'prod',
        credentials: {
          username: 'user',
          password: 'pass',
          accessToken: 'token',
        },
      },
    }),
    createTenantDoc('tenant_missing_credentials', {
      erpIntegration: {
        provider: 'sankhya',
        environment: 'prod',
        credentials: {
          username: '',
          password: 'pass',
          accessToken: 'token',
        },
      },
    }),
  ]);

  let authCalls = 0;
  let syncCalls = 0;
  const logs = [];

  const result = await executeSyncSankhyaPriceTablesNightlyAction({
    firestore,
    authenticateInSankhya: async () => {
      authCalls += 1;
      return {};
    },
    readBearerToken: () => '',
    syncSankhyaPriceTablesModule: async () => {
      syncCalls += 1;
    },
    loggerError: () => {},
    loggerLog: (...args) => {
      logs.push(args);
    },
  });

  assert.equal(authCalls, 0);
  assert.equal(syncCalls, 0);
  assert.equal(result.processedTenants, 0);
  assert.equal(result.skippedTenants, 2);
  assert.equal(result.failedTenants, 0);
  assert.equal(logs.length, 1);
});

test('executeSyncSankhyaPriceTablesNightlyAction processes valid tenants and reports failures', async () => {
  const firestore = createFirestoreTenants([
    createTenantDoc('tenant_prod_ok', {
      erpIntegration: {
        provider: 'sankhya',
        environment: 'prod',
        credentials: {
          username: 'prod_user',
          password: 'prod_pass',
          accessToken: 'prod_token',
        },
      },
    }),
    createTenantDoc('tenant_homolog_fail', {
      erpIntegration: {
        provider: 'sankhya',
        environment: 'homolog',
        credentials: {
          username: 'h_user',
          password: 'h_pass',
          accessToken: 'h_token',
        },
      },
    }),
  ]);

  const authInputs = [];
  const syncInputs = [];
  const errorLogs = [];
  const infoLogs = [];

  const result = await executeSyncSankhyaPriceTablesNightlyAction({
    firestore,
    authenticateInSankhya: async (input) => {
      authInputs.push(input);
      return { access_token: `${input.clientId}_token` };
    },
    readBearerToken: (payload) => String(payload?.access_token ?? '').trim(),
    syncSankhyaPriceTablesModule: async (input) => {
      syncInputs.push(input);
      if (input.tenantId === 'tenant_homolog_fail') {
        throw new Error('sync_failed');
      }
    },
    loggerError: (...args) => {
      errorLogs.push(args);
    },
    loggerLog: (...args) => {
      infoLogs.push(args);
    },
  });

  assert.equal(authInputs.length, 2);
  assert.equal(authInputs[0].baseUrl, 'https://api.sankhya.com.br');
  assert.equal(authInputs[1].baseUrl, 'https://api.sandbox.sankhya.com.br');

  assert.equal(syncInputs.length, 2);
  assert.equal(syncInputs[0].tenantId, 'tenant_prod_ok');
  assert.equal(syncInputs[0].bearerToken, 'prod_user_token');
  assert.equal(syncInputs[1].tenantId, 'tenant_homolog_fail');
  assert.equal(syncInputs[1].bearerToken, 'h_user_token');

  assert.equal(result.processedTenants, 1);
  assert.equal(result.skippedTenants, 0);
  assert.equal(result.failedTenants, 1);

  assert.equal(errorLogs.length, 1);
  assert.equal(errorLogs[0][0], '[syncSankhyaPriceTablesNightly] tenant_failed');
  assert.match(String(errorLogs[0][1]), /tenant_homolog_fail/);

  assert.equal(infoLogs.length, 1);
  assert.equal(infoLogs[0][0], '[syncSankhyaPriceTablesNightly] summary');
  assert.match(String(infoLogs[0][1]), /"processedTenants":1/);
});

test('executeSyncSankhyaPriceTablesNightlyAction treats missing access token as failure', async () => {
  const firestore = createFirestoreTenants([
    createTenantDoc('tenant_missing_token', {
      erpIntegration: {
        provider: 'sankhya',
        environment: 'prod',
        credentials: {
          username: 'user',
          password: 'pass',
          accessToken: 'token',
        },
      },
    }),
  ]);

  let syncCalls = 0;
  const errorLogs = [];

  const result = await executeSyncSankhyaPriceTablesNightlyAction({
    firestore,
    authenticateInSankhya: async () => ({ access_token: '' }),
    readBearerToken: () => '',
    syncSankhyaPriceTablesModule: async () => {
      syncCalls += 1;
    },
    loggerError: (...args) => {
      errorLogs.push(args);
    },
    loggerLog: () => {},
  });

  assert.equal(syncCalls, 0);
  assert.equal(result.processedTenants, 0);
  assert.equal(result.skippedTenants, 0);
  assert.equal(result.failedTenants, 1);
  assert.equal(errorLogs.length, 1);
  assert.match(String(errorLogs[0][1]), /Autenticacao sem access_token/);
});
