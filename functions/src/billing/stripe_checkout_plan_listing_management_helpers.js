async function executeListStripeCheckoutPlansAction({
  firestore,
  tenantId,
  authContext,
  assertTenantBillingActorPermission,
  readCheckoutApiConfig,
  resolveStripePlanPrefixByWorkspaceType,
  buildStripePlanMappingFromDocData,
  formatPlanAmountLabel,
  normalizeBillingPlanKey,
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
          'Stripe esta desativado na API Checkout. Habilite Stripe para listar planos Stripe.',
      },
    };
  }

  const tenantDoc = await firestore.collection('tenants').doc(tenantId).get();
  if (!tenantDoc.exists) {
    return {
      status: 404,
      body: {
        error: 'tenant_not_found',
        message: 'Tenant nao encontrado.',
      },
    };
  }

  const tenantData = tenantDoc.data() || {};
  const workspaceType = String(tenantData.workspaceType ?? '')
    .trim()
    .toLowerCase();
  const requiredPrefix = resolveStripePlanPrefixByWorkspaceType(workspaceType);

  const snapshot = await firestore
    .collection('billing_integrations')
    .doc('stripe')
    .collection('plan_mappings')
    .where('active', '==', true)
    .where('mappingType', '==', 'base')
    .limit(200)
    .get();

  const overageSnapshot = await firestore
    .collection('billing_integrations')
    .doc('stripe')
    .collection('plan_mappings')
    .where('active', '==', true)
    .where('mappingType', '==', 'overage')
    .limit(200)
    .get();

  const seatAddonByPlanKey = new Map();
  const linkedSeatAddonByBasePlanKey = new Map();
  for (const overageDoc of overageSnapshot.docs) {
    const overageData = overageDoc.data() || {};
    const overageMapping = buildStripePlanMappingFromDocData(
      overageData,
      overageDoc.id,
    );
    if (!overageMapping) {
      continue;
    }
    if (overageMapping.mappingType !== 'overage') {
      continue;
    }
    if (overageMapping.overageMetric !== 'extra_usuario') {
      continue;
    }
    const overageUnitPriceCentsInput = Number(overageMapping.stripeUnitAmount ?? 0);
    const overageUnitPriceCents = Number.isFinite(overageUnitPriceCentsInput)
      ? Math.max(0, Math.floor(overageUnitPriceCentsInput))
      : 0;
    const overageDisplayAmount =
      String(overageMapping.planDisplayAmount ?? '').trim() ||
      formatPlanAmountLabel({
        amountMinorUnits: overageUnitPriceCents,
        currency: String(overageMapping.stripeCurrency ?? '').trim(),
        recurringInterval: String(overageMapping.stripeRecurringInterval ?? '').trim(),
        recurringIntervalCount: Number(overageMapping.stripeRecurringIntervalCount ?? 0),
      });

    const seatAddonInfo = {
      billingPlanKey: overageMapping.billingPlanKey,
      unitPriceCents: overageUnitPriceCents,
      displayAmount: overageDisplayAmount,
    };

    if (!seatAddonByPlanKey.has(overageMapping.billingPlanKey)) {
      seatAddonByPlanKey.set(overageMapping.billingPlanKey, seatAddonInfo);
    }

    if (!overageMapping.linkedBasePlanKey) {
      continue;
    }
    if (!linkedSeatAddonByBasePlanKey.has(overageMapping.linkedBasePlanKey)) {
      linkedSeatAddonByBasePlanKey.set(
        overageMapping.linkedBasePlanKey,
        seatAddonInfo,
      );
    }
  }

  const plans = [];
  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const billingPlanKey = normalizeBillingPlanKey(data.billingPlanKey ?? doc.id);
    const stripePriceId = String(data.stripePriceId ?? '').trim();
    if (!billingPlanKey || !stripePriceId) {
      continue;
    }

    if (requiredPrefix && !billingPlanKey.startsWith(`${requiredPrefix}_`)) {
      continue;
    }

    const planDisplayName =
      String(data.planDisplayName ?? '').trim() ||
      String(data.stripeProductName ?? '').trim() ||
      String(data.stripePriceNickname ?? '').trim() ||
      billingPlanKey;

    const planDisplayAmount =
      String(data.planDisplayAmount ?? '').trim() ||
      formatPlanAmountLabel({
        amountMinorUnits: Number(data.stripeUnitAmount ?? 0),
        currency: String(data.stripeCurrency ?? '').trim(),
        recurringInterval: String(data.stripeRecurringInterval ?? '').trim(),
        recurringIntervalCount: Number(data.stripeRecurringIntervalCount ?? 0),
      });

    const includedSeatsInput = Number(data.includedSeats ?? 0);
    const includedSeats = Number.isFinite(includedSeatsInput)
      ? Math.max(0, Math.floor(includedSeatsInput))
      : 0;

    let seatAddonInfo = null;
    let seatAddonPlanKey = normalizeBillingPlanKey(data.seatAddonPlanKey);
    if (seatAddonPlanKey) {
      seatAddonInfo = seatAddonByPlanKey.get(seatAddonPlanKey) || null;
    }
    if (!seatAddonPlanKey) {
      seatAddonInfo = linkedSeatAddonByBasePlanKey.get(billingPlanKey) || null;
      seatAddonPlanKey = String(seatAddonInfo?.billingPlanKey ?? '').trim();
    }
    if (!seatAddonInfo && seatAddonPlanKey) {
      seatAddonInfo = seatAddonByPlanKey.get(seatAddonPlanKey) || null;
    }

    const seatAddonUnitPriceCents = Number.isFinite(
      Number(seatAddonInfo?.unitPriceCents ?? 0),
    )
      ? Math.max(0, Math.floor(Number(seatAddonInfo?.unitPriceCents ?? 0)))
      : 0;
    const seatAddonDisplayAmount = String(
      seatAddonInfo?.displayAmount ?? '',
    ).trim();

    plans.push({
      mappingId: doc.id,
      billingPlanKey,
      planDisplayName,
      planDisplayAmount,
      stripePriceId,
      stripeProductId: String(data.stripeProductId ?? '').trim(),
      stripeProductName: String(data.stripeProductName ?? '').trim(),
      includedSeats,
      seatAddonPlanKey,
      seatAddonUnitPriceCents,
      seatAddonDisplayAmount,
    });
  }

  plans.sort((a, b) => {
    const byName = String(a.planDisplayName ?? '').localeCompare(
      String(b.planDisplayName ?? ''),
      'pt-BR',
    );
    if (byName !== 0) {
      return byName;
    }
    return String(a.billingPlanKey ?? '').localeCompare(
      String(b.billingPlanKey ?? ''),
    );
  });

  return {
    status: 200,
    body: {
      tenantId,
      workspaceType,
      requiredPrefix,
      plans,
    },
  };
}

module.exports = {
  executeListStripeCheckoutPlansAction,
};
