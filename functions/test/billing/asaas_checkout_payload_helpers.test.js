const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildAsaasCheckoutPayload,
  resolveAsaasPortalFallbackUrl,
} = require('../../src/billing/asaas_checkout_helpers');

test('buildAsaasCheckoutPayload builds recurring payload with wallet split', () => {
  const payload = buildAsaasCheckoutPayload({
    payload: {
      chargeType: 'RECURRENT',
      billingTypes: ['PIX'],
      minutesToExpire: 90,
      walletId: 'wallet_123',
    },
    tenantId: 'tenant_1',
    tenantData: {},
    resolvedPlan: {
      mapping: {
        billingPlanKey: 'enterprise',
        amount: 149.9,
        cycle: 'MONTHLY',
        itemName: 'Plano Enterprise',
        itemDescription: 'Plano Enterprise mensal',
        customerData: {
          name: 'Tenant Demo',
          email: 'demo@example.com',
        },
      },
    },
    callback: {
      successUrl: 'https://portal.example/success',
      autoRedirect: true,
    },
  });

  assert.deepEqual(payload.billingTypes, ['PIX']);
  assert.deepEqual(payload.chargeTypes, ['RECURRENT']);
  assert.equal(payload.minutesToExpire, 90);
  assert.ok(payload.externalReference.startsWith('smartsfa:tenant_1:enterprise:'));
  assert.equal(payload.items.length, 1);
  assert.equal(payload.items[0].externalReference, 'enterprise');
  assert.equal(payload.items[0].name, 'Plano Enterprise');
  assert.equal(payload.items[0].value, 149.9);
  assert.equal(payload.customerData.name, 'Tenant Demo');
  assert.equal(payload.subscription.cycle, 'MONTHLY');
  assert.ok(/^\d{4}-\d{2}-\d{2}$/.test(payload.subscription.nextDueDate));
  assert.equal(payload.splits[0].walletId, 'wallet_123');
});

test('buildAsaasCheckoutPayload falls back to tenant wallet when payload omits wallet', () => {
  const payload = buildAsaasCheckoutPayload({
    payload: {
      chargeType: 'DETACHED',
    },
    tenantId: 'tenant_1',
    tenantData: {
      billingAsaasWalletId: 'wallet_tenant',
    },
    resolvedPlan: {
      mapping: {
        billingPlanKey: 'solo',
        amount: 49.9,
        cycle: 'MONTHLY',
        itemName: 'Plano Solo',
        itemDescription: 'Plano Solo mensal',
        customerData: {
          name: 'Tenant Solo',
        },
      },
    },
    callback: {
      successUrl: 'https://portal.example/success',
    },
  });

  assert.equal(payload.subscription, undefined);
  assert.equal(payload.splits[0].walletId, 'wallet_tenant');
  assert.deepEqual(payload.chargeTypes, ['DETACHED']);
});

test('resolveAsaasPortalFallbackUrl returns first valid absolute http(s) URL', () => {
  const url = resolveAsaasPortalFallbackUrl({
    tenantData: {
      asaasInvoiceUrl: 'notaurl',
      asaasLastInvoiceUrl: 'https://portal.example/invoice/1',
      asaasCheckoutLink: 'https://portal.example/checkout/1',
    },
  });

  assert.equal(url, 'https://portal.example/invoice/1');
  assert.equal(resolveAsaasPortalFallbackUrl({ tenantData: {} }), '');
});
