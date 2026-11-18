const { normalizeBillingPlanKey } = require('./shared_helpers');
const { loadStripePlanMapping } = require('./stripe_plan_mappings');
const { mapStripeIntervalToAsaasCycle } = require('./asaas_checkout_helpers');

async function resolveAsaasPlanMapping({
  firestore,
  tenantData,
  billingPlanKey,
}) {
  const normalizedPlanKey = normalizeBillingPlanKey(billingPlanKey);
  if (!normalizedPlanKey) {
    return {
      ok: false,
      status: 400,
      error: 'invalid_plan_key',
      message: 'billingPlanKey invalido.',
      mapping: null,
    };
  }

  const stripeMapping = await loadStripePlanMapping({
    firestore,
    billingPlanKey: normalizedPlanKey,
  });
  if (!stripeMapping) {
    return {
      ok: false,
      status: 404,
      error: 'plan_mapping_not_found',
      message: 'Plano nao encontrado no catalogo de billing.',
      mapping: null,
    };
  }

  const amountMinorUnits = Number(stripeMapping.stripeUnitAmount ?? 0);
  if (!Number.isFinite(amountMinorUnits) || amountMinorUnits <= 0) {
    return {
      ok: false,
      status: 409,
      error: 'invalid_plan_amount',
      message: 'Plano sem valor valido para checkout.',
      mapping: null,
    };
  }

  const currency = String(stripeMapping.stripeCurrency ?? '').trim().toLowerCase() || 'brl';
  if (currency !== 'brl') {
    return {
      ok: false,
      status: 409,
      error: 'unsupported_currency',
      message: 'Checkout Asaas suporta apenas planos em BRL neste fluxo.',
      mapping: null,
    };
  }

  const tenantName = String(
    tenantData?.displayName ||
      tenantData?.nomeFantasia ||
      tenantData?.razaoSocial ||
      tenantData?.name ||
      tenantData?.tenantName ||
      '',
  ).trim();

  const fallbackItemName = normalizedPlanKey.slice(0, 30);
  const itemName = String(
    stripeMapping.planDisplayName ||
      stripeMapping.stripeProductName ||
      stripeMapping.stripePriceNickname ||
      fallbackItemName,
  )
    .trim()
    .slice(0, 30);

  const itemDescription = String(
    stripeMapping.planDisplayAmount ||
      stripeMapping.stripeProductName ||
      itemName,
  )
    .trim()
    .slice(0, 150);

  const cycle = mapStripeIntervalToAsaasCycle(
    stripeMapping.stripeRecurringInterval,
    stripeMapping.stripeRecurringIntervalCount,
  );

  const customerData = {
    name: tenantName || `Tenant ${normalizedPlanKey}`,
  };
  const tenantEmail = String(tenantData?.email ?? '').trim().toLowerCase();
  if (tenantEmail) {
    customerData.email = tenantEmail;
  }

  const cpfCnpj = String(tenantData?.cnpj ?? tenantData?.cpfCnpj ?? '').trim();
  if (cpfCnpj) {
    customerData.cpfCnpj = cpfCnpj.replace(/\D+/g, '').slice(0, 14);
  }

  return {
    ok: true,
    status: 200,
    error: '',
    message: '',
    mapping: {
      billingPlanKey: normalizedPlanKey,
      amount: amountMinorUnits / 100,
      cycle,
      itemName: itemName || fallbackItemName,
      itemDescription,
      customerData,
    },
  };
}

module.exports = {
  resolveAsaasPlanMapping,
};
