async function processAsaasWebhookEvent({
  firestore,
  event,
  enabledEvents,
  defaultEnabledEvents,
  asaasRuntime,
  applyAsaasWebhookEventToTenant,
}) {
  const eventType = String(event?.event ?? '').trim();
  if (!eventType) {
    throw new Error('Webhook Asaas sem event.');
  }

  const enabledSet = new Set(
    (enabledEvents && enabledEvents.length > 0
      ? enabledEvents
      : defaultEnabledEvents
    )
      .map((item) => String(item ?? '').trim())
      .filter((item) => item),
  );

  if (!enabledSet.has(eventType)) {
    return {
      ignored: true,
      duplicate: false,
      tenantId: '',
      billingStatus: '',
    };
  }

  const applied = await applyAsaasWebhookEventToTenant({
    firestore,
    eventPayload: event,
    eventType,
    asaasRuntime,
  });

  return {
    ignored: false,
    duplicate: false,
    tenantId: applied.tenantId,
    billingStatus: applied.billingStatus,
  };
}

module.exports = {
  processAsaasWebhookEvent,
};
