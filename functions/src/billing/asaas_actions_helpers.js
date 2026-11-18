const {
  mapAsaasSubscriptionStatusToBillingStatus,
} = require('./asaas_webhook_helpers');

async function fetchAsaasApiJson({
  apiBaseUrl,
  apiKey,
  path,
  query = null,
  method = 'GET',
  body = null,
  timeoutMs = 20000,
}) {
  const baseUrl = String(apiBaseUrl ?? '').trim().replace(/\/+$/, '');
  const normalizedPath = String(path ?? '').trim();
  if (!baseUrl || !normalizedPath) {
    throw new Error('URL Asaas invalida para requisicao de reconciliacao.');
  }

  const requestUrl = new URL(`${baseUrl}${normalizedPath}`);
  if (query && typeof query === 'object') {
    for (const [key, value] of Object.entries(query)) {
      const normalizedKey = String(key ?? '').trim();
      const normalizedValue = String(value ?? '').trim();
      if (normalizedKey && normalizedValue) {
        requestUrl.searchParams.set(normalizedKey, normalizedValue);
      }
    }
  }

  const normalizedMethod = String(method ?? 'GET').trim().toUpperCase() || 'GET';
  const headers = {
    accept: 'application/json',
    access_token: String(apiKey ?? '').trim(),
    'content-type': 'application/json',
  };

  const fetchOptions = {
    method: normalizedMethod,
    headers,
    signal: AbortSignal.timeout(
      Number.isFinite(Number(timeoutMs)) && Number(timeoutMs) > 0
        ? Number(timeoutMs)
        : 20000,
    ),
  };

  if (normalizedMethod !== 'GET' && body != null) {
    fetchOptions.body = typeof body === 'string' ? body : JSON.stringify(body);
  }

  const response = await fetch(requestUrl.toString(), fetchOptions);

  const rawText = await response.text();
  let payload = {};
  try {
    payload = rawText ? JSON.parse(rawText) : {};
  } catch (_) {
    payload = {};
  }

  if (!response.ok) {
    const apiError = String(
      payload?.errors?.[0]?.description ?? payload?.errors?.[0]?.code ?? '',
    ).trim();
    const fallbackError = String(payload?.message ?? '').trim();
    throw new Error(
      `Asaas API falhou (${response.status}) em ${normalizedMethod} ${normalizedPath}. ${apiError || fallbackError || 'Sem detalhes.'}`,
    );
  }

  return payload;
}

async function applyTenantBillingActionToAsaas({
  asaasRuntime,
  tenantId,
  tenantData,
  action,
}) {
  const asaasSubscriptionId = String(tenantData?.asaasSubscriptionId ?? '').trim();
  const apiKey = String(asaasRuntime?.apiKey ?? '').trim();
  const apiBaseUrl = String(asaasRuntime?.apiBaseUrl ?? '').trim();

  if (!apiKey || !apiBaseUrl) {
    return {
      applied: false,
      action: 'integration_not_ready',
      message: 'Runtime Asaas indisponivel para refletir acao manual.',
    };
  }

  if (!asaasSubscriptionId) {
    return {
      applied: false,
      action: 'no_asaas_subscription_reference',
      message: 'Tenant sem asaasSubscriptionId para acao remota no Asaas.',
    };
  }

  return {
    applied: false,
    action: `manual_action_${action}_local_only`,
    message:
      `Acao manual aplicada no estado local do tenant (${tenantId}). Reflexo remoto no Asaas fica para fluxo financeiro assistido (boleto/NF-e).`,
  };
}

async function applyTenantBillingSelfServiceActionToAsaas({
  asaasRuntime,
  tenantData,
  action,
}) {
  const asaasSubscriptionId = String(tenantData?.asaasSubscriptionId ?? '').trim();
  const apiKey = String(asaasRuntime?.apiKey ?? '').trim();
  const apiBaseUrl = String(asaasRuntime?.apiBaseUrl ?? '').trim();

  if (!apiKey || !apiBaseUrl) {
    return {
      applied: false,
      action: 'integration_not_ready',
      message: 'Runtime Asaas indisponivel para autoatendimento.',
      billingStatus: '',
    };
  }

  if (!asaasSubscriptionId) {
    return {
      applied: false,
      action: 'no_asaas_subscription_reference',
      message: 'Tenant sem asaasSubscriptionId para acao remota no Asaas.',
      billingStatus: '',
    };
  }

  const encodedSubscriptionId = encodeURIComponent(asaasSubscriptionId);

  if (action === 'stop_renewal') {
    const payload = await fetchAsaasApiJson({
      apiKey,
      apiBaseUrl,
      path: `/subscriptions/${encodedSubscriptionId}`,
      method: 'PUT',
      body: {
        status: 'INACTIVE',
      },
      timeoutMs: 20000,
    });

    const billingStatus =
      mapAsaasSubscriptionStatusToBillingStatus(payload?.status) || 'suspended';

    return {
      applied: true,
      action: 'subscription_inactivated',
      message:
        'Renovacao da assinatura interrompida no Asaas. Novas cobrancas nao serao geradas.',
      billingStatus,
    };
  }

  if (action === 'cancel_now') {
    await fetchAsaasApiJson({
      apiKey,
      apiBaseUrl,
      path: `/subscriptions/${encodedSubscriptionId}`,
      method: 'DELETE',
      timeoutMs: 20000,
    });

    return {
      applied: true,
      action: 'subscription_deleted',
      message:
        'Assinatura cancelada no Asaas. Nao havera novas recorrencias para este plano.',
      billingStatus: 'canceled',
    };
  }

  return {
    applied: false,
    action: 'invalid_self_service_action',
    message: `Acao self-service invalida para Asaas: ${action}.`,
    billingStatus: '',
  };
}

module.exports = {
  applyTenantBillingActionToAsaas,
  applyTenantBillingSelfServiceActionToAsaas,
  fetchAsaasApiJson,
};
