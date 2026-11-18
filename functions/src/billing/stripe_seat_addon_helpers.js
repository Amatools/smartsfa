async function applyStripeSeatAddonDeltaToActiveSubscription({
  firestore,
  stripeClient,
  tenantId,
  tenantData,
  billingPlanKey,
  addonSeatsDelta,
  actorUid,
  normalizeBillingPlanKey,
  readNonNegativeInteger,
  resolveStripePlanMappingByPriceId,
  loadStripePlanMapping,
  resolveStripeSeatAddonMappingForBasePlan,
  sanitizeStripeMetadataValue,
  reconcileTenantStripeState,
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

  const stripeSubscriptionId = String(tenantData?.stripeSubscriptionId ?? '').trim();
  if (!stripeSubscriptionId) {
    return {
      applied: false,
      status: 409,
      error: 'missing_active_subscription',
      action: 'no_active_subscription',
      message:
        'Nao existe stripeSubscriptionId ativo para ajustar seats extras neste tenant.',
    };
  }

  const subscription = await stripeClient.subscriptions.retrieve(
    stripeSubscriptionId,
    { expand: ['items.data.price'] },
  );
  const subscriptionStatus = String(subscription?.status ?? '').trim().toLowerCase();
  if (
    subscriptionStatus === 'canceled' ||
    subscriptionStatus === 'incomplete_expired'
  ) {
    return {
      applied: false,
      status: 409,
      error: 'subscription_not_active',
      action: 'subscription_not_active',
      message:
        'A assinatura Stripe atual nao esta ativa para ajuste de seats extras.',
    };
  }

  const lineItems = Array.isArray(subscription?.items?.data)
    ? subscription.items.data
    : [];

  const mappedItems = [];
  for (const item of lineItems) {
    const priceId = String(item?.price?.id ?? '').trim();
    if (!priceId) {
      continue;
    }
    const mapping = await resolveStripePlanMappingByPriceId({
      firestore,
      stripePriceId: priceId,
    });
    if (!mapping) {
      continue;
    }
    mappedItems.push({
      ...mapping,
      quantity: readNonNegativeInteger(item?.quantity, 0),
    });
  }

  const subscriptionBaseItem =
    mappedItems.find((item) => item.mappingType === 'base') ?? null;
  if (
    normalizedPlanKey &&
    subscriptionBaseItem?.billingPlanKey &&
    subscriptionBaseItem.billingPlanKey !== normalizedPlanKey
  ) {
    return {
      applied: false,
      status: 409,
      error: 'plan_mismatch_with_active_subscription',
      action: 'plan_mismatch',
      message:
        'O plano selecionado nao corresponde ao plano base da assinatura Stripe ativa.',
    };
  }

  let baseMapping = subscriptionBaseItem;
  if (!baseMapping && normalizedPlanKey) {
    const loaded = await loadStripePlanMapping({
      firestore,
      billingPlanKey: normalizedPlanKey,
    });
    if (loaded?.mappingType === 'base') {
      baseMapping = loaded;
    }
  }

  if (!baseMapping || baseMapping.mappingType !== 'base') {
    return {
      applied: false,
      status: 409,
      error: 'base_plan_mapping_not_found',
      action: 'base_mapping_not_found',
      message:
        'Nao foi possivel identificar o mapeamento base da assinatura para aplicar seats extras.',
    };
  }

  const addonMapping = await resolveStripeSeatAddonMappingForBasePlan({
    firestore,
    baseMapping,
  });

  if (
    !addonMapping ||
    addonMapping.mappingType !== 'overage' ||
    addonMapping.overageMetric !== 'extra_usuario' ||
    !addonMapping.stripePriceId
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

  const existingAddonItem = lineItems.find(
    (item) => String(item?.price?.id ?? '').trim() === addonMapping.stripePriceId,
  );
  const previousAddonSeats = readNonNegativeInteger(existingAddonItem?.quantity, 0);
  const currentAddonSeats = previousAddonSeats + delta;

  const seatItemPayload = existingAddonItem
    ? [{ id: String(existingAddonItem.id ?? '').trim(), quantity: currentAddonSeats }]
    : [{ price: addonMapping.stripePriceId, quantity: currentAddonSeats }];

  const nowIso = new Date().toISOString();
  const metadataPatch = {
    smartsfaTenantId: sanitizeStripeMetadataValue(normalizedTenantId, 120),
    smartsfaBillingAction: 'seat_addon_increment',
    smartsfaSeatAddonDelta: String(delta),
    smartsfaSeatAddonQuantity: String(currentAddonSeats),
    smartsfaBillingActorUid: sanitizeStripeMetadataValue(actorUid, 120),
    smartsfaBillingUpdatedAt: sanitizeStripeMetadataValue(nowIso, 60),
  };

  const updatedSubscription = await stripeClient.subscriptions.update(
    stripeSubscriptionId,
    {
      items: seatItemPayload,
      proration_behavior: 'always_invoice',
      payment_behavior: 'allow_incomplete',
      metadata: {
        ...(subscription?.metadata || {}),
        ...metadataPatch,
      },
      expand: ['items.data.price', 'latest_invoice'],
    },
  );

  await reconcileTenantStripeState({
    firestore,
    stripeClient,
    tenantId: normalizedTenantId,
  });

  const latestInvoiceObject =
    updatedSubscription?.latest_invoice &&
    typeof updatedSubscription.latest_invoice === 'object'
      ? updatedSubscription.latest_invoice
      : null;
  const invoiceId = latestInvoiceObject
    ? String(latestInvoiceObject.id ?? '').trim()
    : String(updatedSubscription?.latest_invoice ?? '').trim();
  const invoiceStatus = latestInvoiceObject
    ? String(latestInvoiceObject.status ?? '').trim()
    : '';
  const invoiceUrl = latestInvoiceObject
    ? String(
      latestInvoiceObject.hosted_invoice_url ??
          latestInvoiceObject.invoice_pdf ??
          '',
    ).trim()
    : '';

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
    stripeSubscriptionId,
    stripeAddonPriceId: addonMapping.stripePriceId,
    invoiceId,
    invoiceStatus,
    invoiceUrl,
  };
}

module.exports = {
  applyStripeSeatAddonDeltaToActiveSubscription,
};
