async function processStripeWebhookEvent({
  firestore,
  event,
  enabledEvents,
  defaultEnabledEvents,
  stripeClient,
  applyStripeWebhookEventToTenant,
}) {
  const type = String(event?.type ?? '').trim();
  if (!type) {
    throw new Error('Webhook Stripe sem event.type.');
  }

  const enabledSet = new Set(
    (enabledEvents || defaultEnabledEvents)
      .map((item) => String(item ?? '').trim())
      .filter((item) => item),
  );

  if (!enabledSet.has(type)) {
    return {
      ignored: true,
      duplicate: false,
      tenantId: '',
    };
  }

  const eventId = String(event.id ?? '').trim();
  if (!eventId) {
    throw new Error('Webhook Stripe sem event.id.');
  }

  const eventRef = firestore.collection('billing_webhook_events').doc(eventId);
  let duplicate = false;

  await firestore.runTransaction(async (transaction) => {
    const existingDoc = await transaction.get(eventRef);
    if (existingDoc.exists) {
      const existingData = existingDoc.data() || {};
      const status = String(existingData.processingStatus ?? '')
        .trim()
        .toLowerCase();
      if (status === 'success') {
        duplicate = true;
        return;
      }
      const retryCount = Number(existingData.retryCount ?? 0);
      transaction.set(
        eventRef,
        {
          provider: 'stripe',
          eventId,
          type,
          receivedAt: new Date().toISOString(),
          processingStatus: 'processing',
          retryCount: Number.isFinite(retryCount) ? retryCount + 1 : 1,
        },
        { merge: true },
      );
      return;
    }

    transaction.set(eventRef, {
      provider: 'stripe',
      eventId,
      type,
      receivedAt: new Date().toISOString(),
      processingStatus: 'processing',
      retryCount: 0,
    });
  });

  if (duplicate) {
    return {
      ignored: false,
      duplicate: true,
      tenantId: '',
    };
  }

  try {
    const tenantId = await applyStripeWebhookEventToTenant({
      firestore,
      event,
      stripeClient,
    });

    await eventRef.set(
      {
        tenantId,
        processedAt: new Date().toISOString(),
        processingStatus: 'success',
        errorMessage: '',
      },
      { merge: true },
    );

    return {
      ignored: false,
      duplicate: false,
      tenantId,
    };
  } catch (error) {
    await eventRef.set(
      {
        processedAt: new Date().toISOString(),
        processingStatus: 'error',
        errorMessage: error instanceof Error ? error.message : String(error),
      },
      { merge: true },
    );
    throw error;
  }
}

module.exports = {
  processStripeWebhookEvent,
};
