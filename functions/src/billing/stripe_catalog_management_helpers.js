async function executeListStripeCatalogAction({
  firestore,
  payload,
  authContext,
  assertPlatformAdminActor,
  loadStripeIntegrationRuntime,
}) {
  const limitProductsInput = Number(payload?.limitProducts ?? 30);
  const limitPricesInput = Number(payload?.limitPricesPerProduct ?? 20);
  const activeOnly = payload?.activeOnly !== false;

  const limitProducts = Number.isFinite(limitProductsInput)
    ? Math.max(1, Math.min(100, Math.floor(limitProductsInput)))
    : 30;
  const limitPricesPerProduct = Number.isFinite(limitPricesInput)
    ? Math.max(1, Math.min(100, Math.floor(limitPricesInput)))
    : 20;

  const platformAccess = await assertPlatformAdminActor({
    firestore,
    uid: authContext.uid,
  });
  if (!platformAccess.allowed) {
    return {
      status: platformAccess.status,
      body: {
        error: platformAccess.error,
        message: platformAccess.message,
      },
    };
  }

  const integrationReady = await loadStripeIntegrationRuntime({
    firestore,
    requireWebhookSecret: false,
  });
  if (!integrationReady.ok) {
    return {
      status: integrationReady.status,
      body: {
        error: integrationReady.error,
        message: integrationReady.message,
      },
    };
  }

  try {
    const stripeClient = integrationReady.stripeClient;
    const stripeAccount = await stripeClient.accounts.retrieve();

    const products = await stripeClient.products.list({
      active: activeOnly ? true : undefined,
      limit: limitProducts,
    });

    const items = [];
    for (const product of products.data) {
      const prices = await stripeClient.prices.list({
        product: product.id,
        active: activeOnly ? true : undefined,
        limit: limitPricesPerProduct,
      });

      items.push({
        productId: String(product.id ?? '').trim(),
        productName: String(product.name ?? '').trim(),
        productDescription: String(product.description ?? '').trim(),
        active: product.active === true,
        defaultPriceId:
          typeof product.default_price === 'string'
            ? String(product.default_price).trim()
            : String(product.default_price?.id ?? '').trim(),
        prices: prices.data.map((price) => ({
          priceId: String(price.id ?? '').trim(),
          lookupKey: String(price.lookup_key ?? '').trim(),
          nickname: String(price.nickname ?? '').trim(),
          active: price.active === true,
          currency: String(price.currency ?? '').trim(),
          type: String(price.type ?? '').trim(),
          recurringInterval: String(price.recurring?.interval ?? '').trim(),
          recurringIntervalCount: Number(price.recurring?.interval_count ?? 0),
          unitAmount: Number(price.unit_amount ?? 0),
          unitAmountDecimal: String(price.unit_amount_decimal ?? '').trim(),
          taxBehavior: String(price.tax_behavior ?? '').trim(),
        })),
      });
    }

    return {
      status: 200,
      body: {
        activeEnvironment: integrationReady.environment,
        stripeAccountId: String(stripeAccount.id ?? '').trim(),
        totalProducts: items.length,
        hasMoreProducts: products.has_more === true,
        products: items,
      },
    };
  } catch (error) {
    return {
      status: 500,
      body: {
        error: 'stripe_catalog_list_failed',
        message: error instanceof Error ? error.message : String(error),
      },
    };
  }
}

async function executeCreateStripeCatalogPlanAction({
  firestore,
  payload,
  authContext,
  assertPlatformAdminActor,
  loadStripeIntegrationRuntime,
  normalizeBillingPlanKey,
  buildStripeRecommendedLookupKey,
  buildStripeCatalogPlanMetadata,
  timestampFromDate,
}) {
  const productName = String(payload?.productName ?? '').trim();
  const productDescription = String(payload?.productDescription ?? '').trim();
  const billingPlanKey = normalizeBillingPlanKey(payload?.billingPlanKey);
  const currency = String(payload?.currency ?? 'brl').trim().toLowerCase();
  const recurringInterval = String(payload?.recurringInterval ?? 'month')
    .trim()
    .toLowerCase();
  const recurringIntervalCountInput = Number(payload?.recurringIntervalCount ?? 1);
  const amountMinorUnitsInput = Number(payload?.amountMinorUnits ?? 0);
  const priceNickname = String(payload?.priceNickname ?? '').trim();
  const lookupKey = String(payload?.lookupKey ?? '').trim();
  const taxBehavior = String(payload?.taxBehavior ?? '').trim().toLowerCase();
  const active = payload?.active !== false;

  const amountMinorUnits = Number.isFinite(amountMinorUnitsInput)
    ? Math.floor(amountMinorUnitsInput)
    : 0;
  const recurringIntervalCount = Number.isFinite(recurringIntervalCountInput)
    ? Math.max(1, Math.min(36, Math.floor(recurringIntervalCountInput)))
    : 1;
  const recommendedLookupKey = buildStripeRecommendedLookupKey({
    billingPlanKey,
    currency,
    recurringInterval,
    recurringIntervalCount,
  });
  const effectiveLookupKey = lookupKey || recommendedLookupKey;

  if (!productName) {
    return {
      status: 400,
      body: {
        error: 'invalid_payload',
        message: 'productName e obrigatorio.',
      },
    };
  }

  if (!billingPlanKey) {
    return {
      status: 400,
      body: {
        error: 'invalid_payload',
        message: 'billingPlanKey e obrigatorio.',
      },
    };
  }

  if (!Number.isInteger(amountMinorUnits) || amountMinorUnits <= 0) {
    return {
      status: 400,
      body: {
        error: 'invalid_payload',
        message: 'amountMinorUnits deve ser inteiro positivo.',
      },
    };
  }

  if (!/^[a-z]{3}$/.test(currency)) {
    return {
      status: 400,
      body: {
        error: 'invalid_payload',
        message: 'currency deve seguir ISO 4217 em 3 letras (ex.: brl, usd).',
      },
    };
  }

  if (!['day', 'week', 'month', 'year'].includes(recurringInterval)) {
    return {
      status: 400,
      body: {
        error: 'invalid_payload',
        message: 'recurringInterval invalido. Use day, week, month ou year.',
      },
    };
  }

  const platformAccess = await assertPlatformAdminActor({
    firestore,
    uid: authContext.uid,
  });
  if (!platformAccess.allowed) {
    return {
      status: platformAccess.status,
      body: {
        error: platformAccess.error,
        message: platformAccess.message,
      },
    };
  }

  const integrationReady = await loadStripeIntegrationRuntime({
    firestore,
    requireWebhookSecret: false,
  });
  if (!integrationReady.ok) {
    return {
      status: integrationReady.status,
      body: {
        error: integrationReady.error,
        message: integrationReady.message,
      },
    };
  }

  try {
    const stripeClient = integrationReady.stripeClient;
    const stripeAccount = await stripeClient.accounts.retrieve();

    const metadata = buildStripeCatalogPlanMetadata({
      billingPlanKey,
      amountMinorUnits,
      currency,
      recurringInterval,
      recurringIntervalCount,
      lookupKey: effectiveLookupKey,
      actorUid: authContext.uid,
      actorEmail: authContext.email,
    });

    const product = await stripeClient.products.create({
      name: productName,
      description: productDescription || undefined,
      active,
      metadata,
    });

    const pricePayload = {
      product: String(product.id ?? '').trim(),
      currency,
      unit_amount: amountMinorUnits,
      recurring: {
        interval: recurringInterval,
        interval_count: recurringIntervalCount,
      },
      nickname: priceNickname || undefined,
      lookup_key: effectiveLookupKey || undefined,
      active,
      metadata,
    };

    if (['inclusive', 'exclusive', 'unspecified'].includes(taxBehavior)) {
      pricePayload.tax_behavior = taxBehavior;
    }

    const price = await stripeClient.prices.create(pricePayload);

    await firestore.collection('platform_admin_audit').add({
      action: 'stripe_catalog_plan_created',
      actorUid: authContext.uid,
      actorEmail: authContext.email,
      actorLabel: authContext.email || authContext.uid,
      targetUid: authContext.uid,
      targetEmail: authContext.email,
      targetDisplayName: authContext.email || authContext.uid,
      details: {
        billingPlanKey,
        activeEnvironment: integrationReady.environment,
        stripeAccountId: String(stripeAccount.id ?? '').trim(),
        productId: String(product.id ?? '').trim(),
        priceId: String(price.id ?? '').trim(),
        amountMinorUnits,
        currency,
        recurringInterval,
        recurringIntervalCount,
      },
      createdAt: timestampFromDate(new Date()),
    });

    return {
      status: 200,
      body: {
        activeEnvironment: integrationReady.environment,
        stripeAccountId: String(stripeAccount.id ?? '').trim(),
        productId: String(product.id ?? '').trim(),
        productName: String(product.name ?? '').trim(),
        productDescription: String(product.description ?? '').trim(),
        priceId: String(price.id ?? '').trim(),
        priceNickname: String(price.nickname ?? '').trim(),
        lookupKey: String(price.lookup_key ?? '').trim() || effectiveLookupKey,
        currency: String(price.currency ?? '').trim(),
        unitAmount: Number(price.unit_amount ?? 0),
        recurringInterval: String(price.recurring?.interval ?? '').trim(),
        recurringIntervalCount: Number(price.recurring?.interval_count ?? 0),
        billingPlanKey,
      },
    };
  } catch (error) {
    const statusCode = Number(error?.statusCode ?? 500);
    const safeStatus = statusCode >= 400 && statusCode < 600 ? statusCode : 500;
    const message =
      String(error?.raw?.message ?? '').trim() ||
      (error instanceof Error ? error.message : String(error));

    return {
      status: safeStatus,
      body: {
        error: 'stripe_catalog_create_plan_failed',
        message: message || 'Falha ao criar Product/Price no Stripe.',
      },
    };
  }
}

module.exports = {
  executeListStripeCatalogAction,
  executeCreateStripeCatalogPlanAction,
};
