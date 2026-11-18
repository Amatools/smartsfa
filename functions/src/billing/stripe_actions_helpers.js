async function applyTenantBillingActionToStripe({
  stripeClient,
  tenantId,
  tenantData,
  action,
  reason,
  actorUid,
  sanitizeStripeMetadataValue,
}) {
  const stripeCustomerId = String(tenantData?.stripeCustomerId ?? '').trim();
  const stripeSubscriptionId = String(tenantData?.stripeSubscriptionId ?? '').trim();
  if (!stripeCustomerId && !stripeSubscriptionId) {
    return {
      applied: false,
      action: 'no_stripe_reference',
      message: 'Tenant sem stripeCustomerId/stripeSubscriptionId.',
    };
  }

  const nowIso = new Date().toISOString();
  const metadataBase = {
    smartsfaTenantId: sanitizeStripeMetadataValue(tenantId, 120),
    smartsfaBillingAction: sanitizeStripeMetadataValue(action, 60),
    smartsfaBillingReason: sanitizeStripeMetadataValue(reason || 'manual', 120),
    smartsfaBillingActorUid: sanitizeStripeMetadataValue(actorUid, 120),
    smartsfaBillingUpdatedAt: sanitizeStripeMetadataValue(nowIso, 60),
  };

  if (action === 'grant_7_days' || action === 'grant_30_days') {
    metadataBase.smartsfaGraceDays = action === 'grant_30_days' ? '30' : '7';
  }

  if (stripeCustomerId) {
    await stripeClient.customers.update(stripeCustomerId, {
      metadata: metadataBase,
    });
  }

  if (!stripeSubscriptionId) {
    return {
      applied: true,
      action: 'customer_metadata_updated',
      message: 'Subscription ausente; apenas metadata do customer foi atualizada.',
    };
  }

  if (action === 'suspend_billing') {
    await stripeClient.subscriptions.update(stripeSubscriptionId, {
      pause_collection: {
        behavior: 'void',
      },
      metadata: metadataBase,
    });
    return {
      applied: true,
      action: 'subscription_paused_collection_void',
      message: 'Cobranca pausada no Stripe (pause_collection=void).',
    };
  }

  if (action === 'normalize_billing') {
    await stripeClient.subscriptions.update(stripeSubscriptionId, {
      pause_collection: null,
      metadata: metadataBase,
    });
    return {
      applied: true,
      action: 'subscription_resumed_collection',
      message: 'Cobranca normalizada no Stripe (pause_collection removido).',
    };
  }

  if (action === 'clear_plan_link') {
    const subscriptionIdsToCancel = new Set();
    if (stripeSubscriptionId) {
      subscriptionIdsToCancel.add(stripeSubscriptionId);
    }

    if (stripeCustomerId) {
      let hasMore = true;
      let startingAfter = '';
      while (hasMore) {
        const page = await stripeClient.subscriptions.list({
          customer: stripeCustomerId,
          status: 'all',
          limit: 100,
          ...(startingAfter ? { starting_after: startingAfter } : {}),
        });

        const data = Array.isArray(page?.data) ? page.data : [];
        for (const subscription of data) {
          const candidateId = String(subscription?.id ?? '').trim();
          const candidateStatus = String(subscription?.status ?? '')
            .trim()
            .toLowerCase();
          if (!candidateId) {
            continue;
          }
          if (
            candidateStatus === 'canceled' ||
            candidateStatus === 'incomplete_expired'
          ) {
            continue;
          }
          subscriptionIdsToCancel.add(candidateId);
        }

        hasMore = Boolean(page?.has_more);
        if (hasMore && data.length > 0) {
          startingAfter = String(data[data.length - 1]?.id ?? '').trim();
          if (!startingAfter) {
            hasMore = false;
          }
        } else {
          hasMore = false;
        }
      }
    }

    let canceledCount = 0;
    let alreadyMissingCount = 0;
    for (const subscriptionIdToCancel of subscriptionIdsToCancel) {
      try {
        await stripeClient.subscriptions.cancel(subscriptionIdToCancel, {
          invoice_now: false,
          prorate: false,
        });
        canceledCount += 1;
      } catch (error) {
        const code = String(error?.code ?? '').trim().toLowerCase();
        const message = String(error?.message ?? '').trim().toLowerCase();
        const isMissingSubscription =
          code === 'resource_missing' ||
          message.includes('no such subscription');
        if (isMissingSubscription) {
          alreadyMissingCount += 1;
          continue;
        }
        throw error;
      }
    }

    return {
      applied: true,
      action: 'subscriptions_canceled_plan_unlinked',
      message:
        canceledCount > 0 || alreadyMissingCount > 0
          ? `Foram canceladas ${canceledCount} subscription(s) no Stripe, ${alreadyMissingCount} ja nao existiam e o plano foi desvinculado no tenant.`
          : 'Nenhuma subscription ativa encontrada no Stripe; plano desvinculado no tenant.',
    };
  }

  await stripeClient.subscriptions.update(stripeSubscriptionId, {
    metadata: metadataBase,
  });
  return {
    applied: true,
    action: 'subscription_metadata_updated',
    message: 'Metadata da subscription atualizada no Stripe.',
  };
}

module.exports = {
  applyTenantBillingActionToStripe,
};
