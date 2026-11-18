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
