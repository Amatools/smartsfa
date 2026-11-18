const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeSyncSankhyaCatalogModuleAction,
} = require('../../src/billing/sankhya_catalog_sync_management_helpers');

function createDeps(overrides = {}) {
  const calls = {
    validate: [],
    authenticate: [],
    products: [],
    taxRules: [],
    clientes: [],
    productImages: [],
    priceTables: [],
  };

  const deps = {
    firestore: { id: 'firestore' },
    request: { headers: { authorization: 'Bearer token' } },
    requestBody: {},
    validateEnterpriseOwnerAccess: async (input) => {
      calls.validate.push(input);
      return { allowed: true };
    },
    authenticateInSankhya: async (input) => {
      calls.authenticate.push(input);
      return { access_token: 'bearer_1' };
    },
    readBearerToken: (payload) => String(payload?.access_token ?? '').trim(),
    syncSankhyaProductsModule: async (input) => {
      calls.products.push(input);
      return { sourceCount: 10 };
    },
    syncSankhyaTaxRulesModule: async (input) => {
      calls.taxRules.push(input);
      return { sourceCount: 20 };
    },
    syncSankhyaClientesModule: async (input) => {
      calls.clientes.push(input);
      return { sourceCount: 30 };
    },
    syncSankhyaProductImagesModule: async (input) => {
      calls.productImages.push(input);
      return { sourceCount: 40 };
    },
    syncSankhyaPriceTablesModule: async (input) => {
      calls.priceTables.push(input);
      return { sourceCount: 50 };
    },
    ...overrides,
  };

  return { deps, calls };
}

test('executeSyncSankhyaCatalogModuleAction validates missing tenant', async () => {
  const { deps } = createDeps({
    requestBody: {
      module: 'produtos',
      environment: 'prod',
      clientId: 'id',
      clientSecret: 'secret',
      xToken: 'token',
    },
  });

  const result = await executeSyncSankhyaCatalogModuleAction(deps);

  assert.equal(result.status, 400);
  assert.equal(result.body.error, 'missing_tenant');
});

test('executeSyncSankhyaCatalogModuleAction maps enterprise access denial', async () => {
  const { deps, calls } = createDeps({
    requestBody: {
      tenantId: 'tenant_1',
      module: 'produtos',
      environment: 'prod',
      clientId: 'id',
      clientSecret: 'secret',
      xToken: 'token',
    },
    validateEnterpriseOwnerAccess: async (input) => {
      calls.validate.push(input);
      return {
        allowed: false,
        status: 403,
        error: 'owner_required',
        message: 'owner only',
      };
    },
  });

  const result = await executeSyncSankhyaCatalogModuleAction(deps);

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'owner_required');
  assert.equal(calls.authenticate.length, 0);
});

test('executeSyncSankhyaCatalogModuleAction returns missing_bearer when token cannot be read', async () => {
  const { deps, calls } = createDeps({
    requestBody: {
      tenantId: 'tenant_1',
      module: 'produtos',
      environment: 'prod',
      clientId: 'id',
      clientSecret: 'secret',
      xToken: 'token',
    },
    readBearerToken: () => '',
  });

  const result = await executeSyncSankhyaCatalogModuleAction(deps);

  assert.equal(result.status, 502);
  assert.equal(result.body.error, 'missing_bearer');
  assert.equal(calls.products.length, 0);
});

test('executeSyncSankhyaCatalogModuleAction dispatches clientes sync and passes codigosFiltro', async () => {
  const { deps, calls } = createDeps({
    requestBody: {
      tenantId: 'tenant_2',
      module: 'clientes',
      environment: 'homolog',
      clientId: 'id_h',
      clientSecret: 'secret_h',
      xToken: 'token_h',
      codigosFiltro: ['191', '1887'],
    },
  });

  const result = await executeSyncSankhyaCatalogModuleAction(deps);

  assert.equal(result.status, 200);
  assert.equal(result.body.success, true);
  assert.equal(result.body.module, 'clientes');
  assert.equal(result.body.environment, 'homolog');
  assert.equal(result.body.sourceCount, 30);

  assert.equal(calls.authenticate.length, 1);
  assert.equal(calls.authenticate[0].baseUrl, 'https://api.sandbox.sankhya.com.br');

  assert.equal(calls.clientes.length, 1);
  assert.equal(calls.clientes[0].tenantId, 'tenant_2');
  assert.deepEqual(calls.clientes[0].codigosFiltro, ['191', '1887']);
});

test('executeSyncSankhyaCatalogModuleAction dispatches default module to tabelas_preco sync', async () => {
  const { deps, calls } = createDeps({
    requestBody: {
      tenantId: 'tenant_3',
      module: 'tabelas_preco',
      environment: 'prod',
      clientId: 'id_p',
      clientSecret: 'secret_p',
      xToken: 'token_p',
    },
  });

  const result = await executeSyncSankhyaCatalogModuleAction(deps);

  assert.equal(result.status, 200);
  assert.equal(result.body.module, 'tabelas_preco');
  assert.equal(calls.priceTables.length, 1);
  assert.equal(calls.priceTables[0].baseUrl, 'https://api.sankhya.com.br');
});

test('executeSyncSankhyaCatalogModuleAction maps module sync exceptions', async () => {
  const { deps } = createDeps({
    requestBody: {
      tenantId: 'tenant_4',
      module: 'tax_rules',
      environment: 'prod',
      clientId: 'id_4',
      clientSecret: 'secret_4',
      xToken: 'token_4',
    },
    syncSankhyaTaxRulesModule: async () => {
      throw new Error('sync exploded');
    },
  });

  const result = await executeSyncSankhyaCatalogModuleAction(deps);

  assert.equal(result.status, 502);
  assert.equal(result.body.error, 'sankhya_sync_failed');
  assert.equal(result.body.message, 'sync exploded');
});
