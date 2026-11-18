async function applyStripeWebhookEventToTenant({
  firestore,
  event,
  stripeClient,
  normalizeBillingPlanKey,
  resolveTenantIdFromStripeReferences,
  readStripeSubscriptionLineItems,
  resolveStripePlanMappingByPriceId,
  buildTenantPatchFromStripeSubscription,
  reconcileTenantStripePeriodIfMissing,
  reconcileTenantBillingState,
  enforceTenantSeatAllowanceForTenant,
  billingProviderStripe,
}) {
  const type = String(event?.type ?? '').trim();
  const payload = event?.data?.object ?? {};

  if (type === 'checkout.session.completed') {
    const tenantId = await resolveTenantIdFromStripeReferences({
      firestore,
      explicitTenantId: payload?.metadata?.tenantId || payload?.client_reference_id,
      stripeCustomerId: payload?.customer,
      stripeSubscriptionId: payload?.subscription,
    });
    if (!tenantId) {
      throw new Error('checkout.session.completed sem tenantId resolvido.');
    }

    const billingPlanKey = normalizeBillingPlanKey(payload?.metadata?.billingPlanKey);
    const nowIso = new Date().toISOString();
    const stripeSubscriptionId = String(payload?.subscription ?? '').trim();
    await firestore.collection('tenants').doc(tenantId).set(
      {
        stripeCustomerId: String(payload?.customer ?? '').trim(),
        stripeCheckoutSessionId: String(payload?.id ?? '').trim(),
        stripeSubscriptionId,
        billingProvider: billingProviderStripe,
        ...(stripeSubscriptionId
          ? {
            billingContractProvider: billingProviderStripe,
            billingContractLinkedAt: nowIso,
          }
          : {}),
        ...(billingPlanKey ? { billingPlanKey } : {}),
        billingUpdatedAt: nowIso,
      },
      { merge: true },
    );

    await reconcileTenantStripePeriodIfMissing({
      firestore,
      stripeClient,
      tenantId,
      source: type,
      reconcileTenantBillingState,
      stripeProviderKey: billingProviderStripe,
    });

    try {
      await enforceTenantSeatAllowanceForTenant({
        firestore,
        tenantId,
      });
    } catch (error) {
      console.error('stripe checkout seat enforcement failed', {
        tenantId,
        type,
        error: error instanceof Error ? error.message : String(error),
      });
    }

    return tenantId;
  }

  if (
    type === 'customer.subscription.created' ||
    type === 'customer.subscription.updated' ||
    type === 'customer.subscription.deleted'
  ) {
    const rawSubscriptionId = String(payload?.id ?? '').trim();
    let subscriptionPayload = payload;
    if (stripeClient && rawSubscriptionId) {
      try {
        subscriptionPayload = await stripeClient.subscriptions.retrieve(
          rawSubscriptionId,
          { expand: ['items.data.price'] },
        );
      } catch (error) {
        console.error('stripe subscription fetch from event failed', {
          type,
          rawSubscriptionId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    const tenantId = await resolveTenantIdFromStripeReferences({
      firestore,
      explicitTenantId: subscriptionPayload?.metadata?.tenantId,
      stripeCustomerId: subscriptionPayload?.customer,
      stripeSubscriptionId: subscriptionPayload?.id,
    });
    if (!tenantId) {
      throw new Error(`${type} sem tenantId resolvido.`);
    }

    const fallbackPlanKey = normalizeBillingPlanKey(
      subscriptionPayload?.metadata?.billingPlanKey,
    );
    const lineItems = readStripeSubscriptionLineItems(subscriptionPayload);
    const mappedItems = [];

    for (const item of lineItems) {
      const mapping = await resolveStripePlanMappingByPriceId({
        firestore,
        stripePriceId: item.priceId,
      });
      if (mapping) {
        mappedItems.push({
          ...mapping,
          quantity: item.quantity,
        });
      }
    }

    const baseItem =
      mappedItems.find((item) => item.mappingType === 'base') ?? null;
    const effectivePlanKey =
      baseItem?.billingPlanKey || fallbackPlanKey || '';

    const seatAddonQuantity = mappedItems
      .filter((item) => {
        if (
          item.mappingType !== 'overage' ||
          item.overageMetric !== 'extra_usuario'
        ) {
          return false;
        }
        if (!effectivePlanKey) {
          return true;
        }
        return !item.linkedBasePlanKey || item.linkedBasePlanKey === effectivePlanKey;
      })
      .reduce((sum, item) => sum + (Number(item.quantity) || 0), 0);

    const tenantPatch = buildTenantPatchFromStripeSubscription({
      subscription: subscriptionPayload,
      billingPlanKey: effectivePlanKey,
    });

    if (baseItem?.stripePriceId) {
      tenantPatch.stripePriceId = baseItem.stripePriceId;
    }
    if (baseItem && Number.isInteger(baseItem.includedSeats) && baseItem.includedSeats > 0) {
      tenantPatch.billingSeatsIncluded = baseItem.includedSeats;
    }
    const seatAddonItem = mappedItems.find(
      (item) =>
        item.mappingType === 'overage' && item.overageMetric === 'extra_usuario',
    );
    if (baseItem?.seatAddonPlanKey) {
      tenantPatch.billingSeatAddonPlanKey = baseItem.seatAddonPlanKey;
    } else if (seatAddonItem?.billingPlanKey) {
      tenantPatch.billingSeatAddonPlanKey = seatAddonItem.billingPlanKey;
    }
    tenantPatch.billingSeatsAddon = seatAddonQuantity < 0 ? 0 : seatAddonQuantity;

    if (seatAddonItem && Number.isFinite(seatAddonItem.stripeUnitAmount)) {
      tenantPatch.billingSeatAddonUnitPriceCents = Math.max(
        0,
        Math.floor(Number(seatAddonItem.stripeUnitAmount) || 0),
      );
    }

    await firestore
      .collection('tenants')
      .doc(tenantId)
      .set(tenantPatch, { merge: true });

    await reconcileTenantStripePeriodIfMissing({
      firestore,
      stripeClient,
      tenantId,
      source: type,
      reconcileTenantBillingState,
      stripeProviderKey: billingProviderStripe,
    });

    try {
      await enforceTenantSeatAllowanceForTenant({
        firestore,
        tenantId,
      });
    } catch (error) {
      console.error('stripe subscription seat enforcement failed', {
        tenantId,
        type,
        error: error instanceof Error ? error.message : String(error),
      });
    }

    return tenantId;
  }

  if (
    type === 'invoice.paid' ||
    type === 'invoice.payment_failed' ||
    type === 'invoice.finalized'
  ) {
    const tenantId = await resolveTenantIdFromStripeReferences({
      firestore,
      explicitTenantId: payload?.metadata?.tenantId,
      stripeCustomerId: payload?.customer,
      stripeSubscriptionId: payload?.subscription,
    });
    if (!tenantId) {
      return '';
    }

    const nowIso = new Date().toISOString();
    const patch = {
      billingUpdatedAt: nowIso,
    };

    const stripeCustomerId = String(payload?.customer ?? '').trim();
    if (stripeCustomerId) {
      patch.stripeCustomerId = stripeCustomerId;
    }

    const stripeSubscriptionId = String(payload?.subscription ?? '').trim();
    if (stripeSubscriptionId) {
      patch.stripeSubscriptionId = stripeSubscriptionId;
      patch.billingContractProvider = billingProviderStripe;
      patch.billingContractLinkedAt = nowIso;
    }

    const stripeInvoiceId = String(payload?.id ?? '').trim();
    if (stripeInvoiceId) {
      patch.stripeInvoiceId = stripeInvoiceId;
    }

    const stripePaymentIntentId = String(payload?.payment_intent ?? '').trim();
    if (stripePaymentIntentId) {
      patch.stripePaymentIntentId = stripePaymentIntentId;
    }

    if (type === 'invoice.paid') {
      patch.billingStatus = 'active';
      patch.billingPastDueSinceAt = '';
    } else if (type === 'invoice.payment_failed') {
      patch.billingStatus = 'past_due';
      patch.billingPastDueSinceAt = nowIso;
    }

    await firestore.collection('tenants').doc(tenantId).set(patch, { merge: true });

    await reconcileTenantStripePeriodIfMissing({
      firestore,
      stripeClient,
      tenantId,
      source: type,
      reconcileTenantBillingState,
      stripeProviderKey: billingProviderStripe,
    });

    try {
      await enforceTenantSeatAllowanceForTenant({
        firestore,
        tenantId,
      });
    } catch (error) {
      console.error('stripe invoice seat enforcement failed', {
        tenantId,
        type,
        error: error instanceof Error ? error.message : String(error),
      });
    }

    return tenantId;
  }

  return '';
}

module.exports = {
  applyStripeWebhookEventToTenant,
};
