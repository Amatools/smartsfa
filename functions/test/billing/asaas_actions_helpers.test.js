const test = require('node:test');
const assert = require('node:assert/strict');

const {
  applyTenantBillingActionToAsaas,
  applyTenantBillingSelfServiceActionToAsaas,
  fetchAsaasApiJson,
} = require('../../src/billing/asaas_actions_helpers');

async function withMockedFetch(mock, callback) {
  const previousFetch = global.fetch;
  global.fetch = mock;
  try {
    await callback();
  } finally {
    global.fetch = previousFetch;
  }
}

test('fetchAsaasApiJson builds request and parses JSON payload', { concurrency: false }, async () => {
  const calls = [];

  await withMockedFetch(async (url, options) => {
    calls.push({ url, options });
    return {
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({ ok: true, id: 'resp_1' });
      },
    };
  }, async () => {
    const payload = await fetchAsaasApiJson({
      apiBaseUrl: 'https://sandbox.asaas.com/',
      apiKey: 'api_key_1',
      path: '/payments',
      query: {
        customer: 'cus_1',
        limit: 1,
      },
      method: 'POST',
      body: { amount: 10 },
      timeoutMs: 1234,
    });

    assert.deepEqual(payload, { ok: true, id: 'resp_1' });
  });

  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /https:\/\/sandbox\.asaas\.com\/payments\?/);
  assert.match(calls[0].url, /customer=cus_1/);
  assert.match(calls[0].url, /limit=1/);
  assert.equal(calls[0].options.method, 'POST');
  assert.equal(calls[0].options.headers.access_token, 'api_key_1');
  assert.equal(calls[0].options.body, JSON.stringify({ amount: 10 }));
});

test('fetchAsaasApiJson throws descriptive error on API failure', { concurrency: false }, async () => {
  await withMockedFetch(async () => ({
    ok: false,
    status: 422,
    async text() {
      return JSON.stringify({
        errors: [{ description: 'Campo invalido' }],
      });
    },
  }), async () => {
    await assert.rejects(
      () =>
        fetchAsaasApiJson({
          apiBaseUrl: 'https://sandbox.asaas.com',
          apiKey: 'api_key_2',
          path: '/subscriptions/sub_1',
          method: 'PUT',
          body: { status: 'INACTIVE' },
        }),
      /Asaas API falhou \(422\).*Campo invalido/,
    );
  });
});

test('applyTenantBillingActionToAsaas validates runtime and subscription reference', async () => {
  const runtimeNotReady = await applyTenantBillingActionToAsaas({
    asaasRuntime: {},
    tenantId: 'tenant_1',
    tenantData: { asaasSubscriptionId: 'sub_1' },
    action: 'grant_7_days',
  });
  assert.equal(runtimeNotReady.applied, false);
  assert.equal(runtimeNotReady.action, 'integration_not_ready');

  const missingReference = await applyTenantBillingActionToAsaas({
    asaasRuntime: {
      apiKey: 'key',
      apiBaseUrl: 'https://sandbox.asaas.com',
    },
    tenantId: 'tenant_1',
    tenantData: {},
    action: 'grant_7_days',
  });
  assert.equal(missingReference.applied, false);
  assert.equal(missingReference.action, 'no_asaas_subscription_reference');
});

test('applyTenantBillingSelfServiceActionToAsaas stop_renewal updates status', { concurrency: false }, async () => {
  const calls = [];

  await withMockedFetch(async (url, options) => {
    calls.push({ url, options });
    return {
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({ status: 'INACTIVE' });
      },
    };
  }, async () => {
    const result = await applyTenantBillingSelfServiceActionToAsaas({
      asaasRuntime: {
        apiKey: 'api_key_3',
        apiBaseUrl: 'https://sandbox.asaas.com',
      },
      tenantData: {
        asaasSubscriptionId: 'sub_99',
      },
      action: 'stop_renewal',
    });

    assert.equal(result.applied, true);
    assert.equal(result.action, 'subscription_inactivated');
    assert.equal(result.billingStatus, 'suspended');
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].options.method, 'PUT');
  assert.match(calls[0].url, /\/subscriptions\/sub_99$/);
});

test('applyTenantBillingSelfServiceActionToAsaas cancel_now deletes subscription', { concurrency: false }, async () => {
  const calls = [];

  await withMockedFetch(async (url, options) => {
    calls.push({ url, options });
    return {
      ok: true,
      status: 200,
      async text() {
        return '{}';
      },
    };
  }, async () => {
    const result = await applyTenantBillingSelfServiceActionToAsaas({
      asaasRuntime: {
        apiKey: 'api_key_4',
        apiBaseUrl: 'https://sandbox.asaas.com',
      },
      tenantData: {
        asaasSubscriptionId: 'sub_88',
      },
      action: 'cancel_now',
    });

    assert.equal(result.applied, true);
    assert.equal(result.action, 'subscription_deleted');
    assert.equal(result.billingStatus, 'canceled');
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].options.method, 'DELETE');
  assert.match(calls[0].url, /\/subscriptions\/sub_88$/);
});
