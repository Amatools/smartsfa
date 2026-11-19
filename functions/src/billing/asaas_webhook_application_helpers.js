async function applyAsaasWebhookEventToTenant({
  firestore,
  eventPayload,
  eventType,
  asaasRuntime,
  resolveTenantIdFromAsaasReferences,
  buildTenantPatchFromAsaasEvent,
  enforceTenantSeatAllowanceForTenant,
}) {
  const tenantId = await resolveTenantIdFromAsaasReferences({
    firestore,
    eventPayload,
  });

  if (!tenantId) {
    return {
      tenantId: '',
      billingStatus: '',
    };
  }

  const tenantRef = firestore.collection('tenants').doc(tenantId);
  const tenantDoc = await tenantRef.get();
  if (!tenantDoc.exists) {
    return {
      tenantId: '',
      billingStatus: '',
    };
  }

  const tenantData = tenantDoc.data() || {};
  const patch = buildTenantPatchFromAsaasEvent({
    eventPayload,
    eventType,
    currentTenantData: tenantData,
    webhookEnvironment: String(asaasRuntime?.environment ?? '').trim(),
  });

  await tenantRef.set(patch, { merge: true });

  try {
    const nowIso = new Date().toISOString();
    await firestore.collection('billing_provider_refs').doc(tenantId).set(
      {
        tenantId,
        billingProvider: 'asaas',
        asaasCustomerId: String(
          patch.asaasCustomerId ?? eventPayload?.payment?.customer ?? '',
        ).trim(),
        asaasSubscriptionId: String(
          patch.asaasSubscriptionId ??
            eventPayload?.subscription?.id ??
            eventPayload?.payment?.subscription ??
            '',
        ).trim(),
        asaasCheckoutId: String(
          patch.asaasCheckoutId ?? eventPayload?.checkout?.id ?? '',
        ).trim(),
        lastWebhookEventId: String(eventPayload?.id ?? '').trim(),
        lastWebhookEventType: String(eventType ?? '').trim(),
        lastWebhookEventAt: String(
          eventPayload?.dateCreated ?? patch.billingUpdatedAt ?? nowIso,
        ).trim(),
        lastWebhookEnvironment: String(asaasRuntime?.environment ?? '').trim(),
        updatedAt: nowIso,
      },
      { merge: true },
    );
  } catch (error) {
    console.error('asaas webhook provider refs persistence failed', {
      tenantId,
      eventType,
      error: error instanceof Error ? error.message : String(error),
    });
  }

  if (typeof enforceTenantSeatAllowanceForTenant === 'function') {
    try {
      await enforceTenantSeatAllowanceForTenant({
        firestore,
        tenantId,
      });
    } catch (error) {
      console.error('asaas webhook seat enforcement failed', {
        tenantId,
        eventType,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return {
    tenantId,
    billingStatus: String(patch.billingStatus ?? '').trim(),
  };
}

module.exports = {
  applyAsaasWebhookEventToTenant,
};
