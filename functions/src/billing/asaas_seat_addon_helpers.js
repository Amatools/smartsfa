async function applyAsaasSeatAddonDeltaToActiveSubscription({
  firestore,
  asaasRuntime,
  tenantId,
  tenantData,
  billingPlanKey,
  addonSeatsDelta,
  actorUid,
  normalizeBillingPlanKey,
  readNonNegativeInteger,
  loadAsaasInternalPlanMapping,
  resolveAsaasSeatAddonMappingForBasePlan,
  fetchAsaasApiJson,
}) {
  const normalizedTenantId = String(tenantId ?? '').trim();
  const normalizedPlanKey = normalizeBillingPlanKey(
    billingPlanKey || tenantData?.billingPlanKey,
  );
  const delta = readNonNegativeInteger(addonSeatsDelta, 0);

  if (!normalizedTenantId) {
    return {
      applied: false,
      status: 400,
      error: 'invalid_tenant_id',
      action: 'invalid_payload',
      message: 'tenantId invalido para ajuste de seats extras.',
    };
  }

  if (delta <= 0 || delta > 10) {
    return {
      applied: false,
      status: 400,
      error: 'invalid_addon_seats_delta',
      action: 'invalid_payload',
      message: 'addonSeatsDelta deve estar entre 1 e 10.',
    };
  }

  const asaasSubscriptionId = String(tenantData?.asaasSubscriptionId ?? '').trim();
  if (!asaasSubscriptionId) {
    return {
      applied: false,
      status: 409,
      error: 'missing_active_subscription',
      action: 'no_active_subscription',
      message:
        'Nao existe asaasSubscriptionId ativo para ajustar seats extras neste tenant.',
    };
  }

  const apiKey = String(asaasRuntime?.asaasApiKey ?? '').trim();
  const apiBaseUrl = String(asaasRuntime?.asaasApiBaseUrl ?? '').trim();
  if (!apiKey || !apiBaseUrl) {
    return {
      applied: false,
      status: 503,
      error: 'integration_not_ready',
      action: 'integration_not_ready',
      message: 'Runtime Asaas indisponivel para ajuste de seats extras.',
    };
  }

  if (!normalizedPlanKey) {
    return {
      applied: false,
      status: 400,
      error: 'invalid_plan_key',
      action: 'invalid_payload',
      message: 'billingPlanKey invalido para ajuste de seats extras.',
    };
  }

  const baseMapping = await loadAsaasInternalPlanMapping({
    firestore,
    billingPlanKey: normalizedPlanKey,
  });
  if (!baseMapping || baseMapping.active === false || baseMapping.mappingType !== 'base') {
    return {
      applied: false,
      status: 409,
      error: 'base_plan_mapping_not_found',
      action: 'base_mapping_not_found',
      message:
        'Nao foi possivel identificar o mapeamento base Asaas para aplicar seats extras.',
    };
  }

  const addonMapping = await resolveAsaasSeatAddonMappingForBasePlan({
    firestore,
    baseMapping,
  });

  if (
    !addonMapping ||
    addonMapping.active === false ||
    addonMapping.mappingType !== 'overage' ||
    addonMapping.overageMetric !== 'extra_usuario'
  ) {
    return {
      applied: false,
      status: 409,
      error: 'invalid_seat_addon_mapping',
      action: 'seat_addon_mapping_invalid',
      message:
        'Plano base sem mapeamento overage extra_usuario valido (seatAddonPlanKey ou linkedBasePlanKey).',
    };
  }

  const baseAmountCents = readNonNegativeInteger(baseMapping.amountCents, 0);
  const addonUnitAmountCents = readNonNegativeInteger(addonMapping.amountCents, 0);
  if (baseAmountCents <= 0 || addonUnitAmountCents <= 0) {
    return {
      applied: false,
      status: 409,
      error: 'invalid_plan_amount',
      action: 'plan_amount_invalid',
      message: 'Plano base/addon sem valor valido para ajuste de seats.',
    };
  }

  const previousAddonSeats = readNonNegativeInteger(
    tenantData?.billingSeatsAddon,
    readNonNegativeInteger(tenantData?.billingSeatAddons, 0),
  );
  const currentAddonSeats = previousAddonSeats + delta;
  const updatedRecurringValue = (baseAmountCents + addonUnitAmountCents * currentAddonSeats) / 100;

  const encodedSubscriptionId = encodeURIComponent(asaasSubscriptionId);
  const currentSubscription = await fetchAsaasApiJson({
    apiBaseUrl,
    apiKey,
    path: `/subscriptions/${encodedSubscriptionId}`,
    method: 'GET',
    timeoutMs: 20000,
  });

  const updatePayload = {
    value: Number(updatedRecurringValue.toFixed(2)),
  };

  const currentCycle = String(currentSubscription?.cycle ?? '').trim();
  if (currentCycle) {
    updatePayload.cycle = currentCycle;
  }

  const currentNextDueDate = String(currentSubscription?.nextDueDate ?? '').trim();
  if (currentNextDueDate) {
    updatePayload.nextDueDate = currentNextDueDate;
  }

  const currentDescription = String(currentSubscription?.description ?? '').trim();
  if (currentDescription) {
    updatePayload.description = currentDescription;
  }

  const updatedSubscription = await fetchAsaasApiJson({
    apiBaseUrl,
    apiKey,
    path: `/subscriptions/${encodedSubscriptionId}`,
    method: 'PUT',
    body: updatePayload,
    timeoutMs: 20000,
  });

  const nowIso = new Date().toISOString();
  await firestore
    .collection('tenants')
    .doc(normalizedTenantId)
    .set(
      {
        billingPlanKey: baseMapping.billingPlanKey,
        billingSeatsIncluded: readNonNegativeInteger(baseMapping.includedSeats, 0),
        billingSeatsAddon: currentAddonSeats,
        billingSeatAddonPlanKey: addonMapping.billingPlanKey,
        billingSeatAddonUnitPriceCents: addonUnitAmountCents,
        billingUpdatedAt: nowIso,
        billingContractProvider: 'asaas',
        billingContractLinkedAt: nowIso,
        asaasSubscriptionId,
        asaasSubscriptionValue: Number(updatePayload.value),
        asaasSubscriptionUpdatedAt: nowIso,
      },
      { merge: true },
    );

  return {
    applied: true,
    status: 200,
    error: '',
    action: 'seat_addon_quantity_incremented',
    message: `Foram adicionados ${delta} seats extras na assinatura atual.`,
    billingPlanKey: baseMapping.billingPlanKey,
    addedSeats: delta,
    previousAddonSeats,
    currentAddonSeats,
    asaasSubscriptionId,
    asaasAddonPlanKey: addonMapping.billingPlanKey,
    asaasSubscriptionValue: Number(updatePayload.value),
    asaasSubscriptionStatus: String(updatedSubscription?.status ?? '').trim(),
  };
}

module.exports = {
  applyAsaasSeatAddonDeltaToActiveSubscription,
};
