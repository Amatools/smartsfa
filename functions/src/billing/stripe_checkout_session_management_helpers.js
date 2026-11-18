async function executeCreateStripeCheckoutSessionAction({
  firestore,
  payload,
  tenantId,
  billingPlanKey,
  successUrl,
  cancelUrl,
  authContext,
  assertTenantBillingActorPermission,
  readCheckoutApiConfig,
  loadStripeIntegrationRuntime,
  loadStripePlanMapping,
  resolveStripeSeatAddonMappingForBasePlan,
  billingProviderStripe,
}) {
  const actorPermission = await assertTenantBillingActorPermission({
    firestore,
    uid: authContext.uid,
    tenantId,
  });
  if (!actorPermission.allowed) {
    return {
      status: actorPermission.status,
      body: {
        error: actorPermission.error,
        message: actorPermission.message,
      },
    };
  }

  const checkoutApiConfig = await readCheckoutApiConfig(firestore);
  if (!checkoutApiConfig.activeProviders.includes(billingProviderStripe)) {
    return {
      status: 409,
      body: {
        error: 'provider_disabled',
        message:
          'Stripe esta desativado na API Checkout. Habilite Stripe ou use provider Asaas conforme configuracao.',
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

  const tenantRef = firestore.collection('tenants').doc(tenantId);
  const tenantDoc = await tenantRef.get();
  if (!tenantDoc.exists) {
    return {
      status: 404,
      body: {
        error: 'tenant_not_found',
        message: 'Tenant nao encontrado.',
      },
    };
  }

  const mapping = await loadStripePlanMapping({
    firestore,
    billingPlanKey,
  });
  if (!mapping) {
    return {
      status: 404,
      body: {
        error: 'plan_mapping_not_found',
        message: 'Nao existe mapeamento ativo para billingPlanKey informado.',
      },
    };
  }

  if (mapping.mappingType !== 'base') {
    return {
      status: 400,
      body: {
        error: 'invalid_plan_mapping_type',
        message:
          'billingPlanKey informado nao aponta para mapeamento base ativo.',
      },
    };
  }

  const tenantData = tenantDoc.data() || {};
  const addonSeatsInput = Number(
    payload?.addonSeats ?? tenantData.billingSeatsAddon ?? 0,
  );
  const addonSeats = Number.isFinite(addonSeatsInput)
    ? Math.max(0, Math.floor(addonSeatsInput))
    : 0;

  let addonMapping = null;
  if (addonSeats > 0) {
    addonMapping = await resolveStripeSeatAddonMappingForBasePlan({
      firestore,
      baseMapping: mapping,
    });

    if (!addonMapping) {
      return {
        status: 400,
        body: {
          error: 'invalid_seat_addon_mapping',
          message:
            'Plano base sem mapeamento overage/extra_usuario valido (seatAddonPlanKey ou linkedBasePlanKey).',
        },
      };
    }
  }

  const existingCustomerId = String(tenantData.stripeCustomerId ?? '').trim();
  const stripeClient = integrationReady.stripeClient;
  let stripeCustomerId = existingCustomerId;
  if (!stripeCustomerId) {
    const ownerEmail = String(authContext.email ?? '').trim();
    const customer = await stripeClient.customers.create({
      email: ownerEmail || undefined,
      name: String(
        tenantData.razaoSocial ?? tenantData.nomeFantasia ?? tenantId,
      ).trim(),
      metadata: {
        tenantId,
        billingPlanKey,
        source: 'smartsfa',
      },
    });
    stripeCustomerId = String(customer.id ?? '').trim();
  }

  const lineItems = [
    {
      price: mapping.stripePriceId,
      quantity: 1,
    },
  ];
  if (addonMapping && addonSeats > 0) {
    lineItems.push({
      price: addonMapping.stripePriceId,
      quantity: addonSeats,
    });
  }

  const session = await stripeClient.checkout.sessions.create({
    mode: 'subscription',
    customer: stripeCustomerId,
    client_reference_id: tenantId,
    success_url: successUrl,
    cancel_url: cancelUrl,
    line_items: lineItems,
    metadata: {
      tenantId,
      billingPlanKey,
      initiatedByUid: authContext.uid,
      source: 'smartsfa_web_portal',
      billingSeatsAddon: String(addonSeats),
    },
    subscription_data: {
      metadata: {
        tenantId,
        billingPlanKey,
        initiatedByUid: authContext.uid,
        billingSeatsAddon: String(addonSeats),
      },
    },
    allow_promotion_codes: true,
  });

  const tenantPatch = {
    stripeCustomerId,
    stripeCheckoutSessionId: String(session.id ?? '').trim(),
    billingProvider: billingProviderStripe,
    billingPlanKey,
    billingUpdatedAt: new Date().toISOString(),
    billingSeatsAddon: addonSeats,
  };
  if (Number.isInteger(mapping.includedSeats) && mapping.includedSeats > 0) {
    tenantPatch.billingSeatsIncluded = mapping.includedSeats;
  }
  if (addonMapping?.billingPlanKey) {
    tenantPatch.billingSeatAddonPlanKey = addonMapping.billingPlanKey;
  } else if (mapping.seatAddonPlanKey) {
    tenantPatch.billingSeatAddonPlanKey = mapping.seatAddonPlanKey;
  }
  if (addonMapping && Number.isInteger(addonMapping.stripeUnitAmount)) {
    tenantPatch.billingSeatAddonUnitPriceCents = addonMapping.stripeUnitAmount;
  }

  await tenantRef.set(tenantPatch, { merge: true });

  return {
    status: 200,
    body: {
      checkoutUrl: String(session.url ?? '').trim(),
      checkoutSessionId: String(session.id ?? '').trim(),
      stripeCustomerId,
      activeEnvironment: integrationReady.environment,
      billingSeatsAddon: addonSeats,
    },
  };
}

module.exports = {
  executeCreateStripeCheckoutSessionAction,
};
