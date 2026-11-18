const test = require('node:test');
const assert = require('node:assert/strict');

const {
  proxyBillingRequestToFunction,
} = require('../../src/billing/http_proxy_helpers');

function createResponseMock() {
  const calls = [];
  return {
    calls,
    status(code) {
      return {
        json(payload) {
          calls.push({ code, payload });
        },
      };
    },
  };
}

test('proxyBillingRequestToFunction forwards GET query and merges JSON response', async () => {
  const request = {
    headers: {
      authorization: 'Bearer token',
    },
    query: {
      tenantId: 'tenant_1',
      tags: ['a', 'b'],
      ignored: null,
    },
  };
  const response = createResponseMock();
  const fetchCalls = [];

  await proxyBillingRequestToFunction({
    request,
    response,
    targetUrl: 'https://example.com/fn',
    method: 'GET',
    extraResponseFields: {
      billingProvider: 'stripe',
    },
    fetchImpl: async (url, options) => {
      fetchCalls.push({ url, options });
      return {
        status: 200,
        text: async () => JSON.stringify({ ok: true, upstream: 1 }),
      };
    },
  });

  assert.equal(fetchCalls.length, 1);
  assert.equal(
    fetchCalls[0].url,
    'https://example.com/fn?tenantId=tenant_1&tags=a&tags=b',
  );
  assert.equal(fetchCalls[0].options.headers.Accept, 'application/json');
  assert.equal(fetchCalls[0].options.headers.Authorization, 'Bearer token');
  assert.equal(fetchCalls[0].options.body, undefined);

  assert.equal(response.calls.length, 1);
  assert.equal(response.calls[0].code, 200);
  assert.deepEqual(response.calls[0].payload, {
    ok: true,
    upstream: 1,
    billingProvider: 'stripe',
  });
});

test('proxyBillingRequestToFunction forwards non-GET body and returns raw text when not JSON object', async () => {
  const request = {
    headers: {},
    body: {
      tenantId: 'tenant_2',
      action: 'cancel',
    },
  };
  const response = createResponseMock();
  const fetchCalls = [];

  await proxyBillingRequestToFunction({
    request,
    response,
    targetUrl: 'https://example.com/fn',
    method: 'POST',
    extraResponseFields: {
      marker: 'x',
    },
    fetchImpl: async (url, options) => {
      fetchCalls.push({ url, options });
      return {
        status: 202,
        text: async () => 'plain-text-body',
      };
    },
  });

  assert.equal(fetchCalls.length, 1);
  assert.equal(fetchCalls[0].url, 'https://example.com/fn');
  assert.equal(fetchCalls[0].options.headers['Content-Type'], 'application/json');
  assert.equal(fetchCalls[0].options.body, JSON.stringify(request.body));

  assert.equal(response.calls.length, 1);
  assert.equal(response.calls[0].code, 202);
  assert.deepEqual(response.calls[0].payload, {
    rawBody: 'plain-text-body',
    marker: 'x',
  });
});

test('proxyBillingRequestToFunction returns provider proxy error when fetch fails', async () => {
  const request = {
    headers: {},
    query: {},
  };
  const response = createResponseMock();

  await proxyBillingRequestToFunction({
    request,
    response,
    targetUrl: 'https://example.com/fn',
    method: 'GET',
    extraResponseFields: {
      billingProvider: 'asaas',
    },
    fetchImpl: async () => {
      throw new Error('network_down');
    },
  });

  assert.equal(response.calls.length, 1);
  assert.equal(response.calls[0].code, 502);
  assert.deepEqual(response.calls[0].payload, {
    error: 'provider_proxy_failed',
    message: 'network_down',
    billingProvider: 'asaas',
  });
});
