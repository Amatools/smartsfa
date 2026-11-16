part of 'maintainer_console_page.dart';

extension _MaintainerConsoleStripePlanMappingDialogHelpersPart
    on _MaintainerConsolePageState {
  void _maybeApplyAddonPlanSlugSuggestion(
    _StripePlanMappingDialogState dialogState, {
    required String linkedBasePlanKey,
  }) {
    if (!dialogState.isAddonMapping) {
      return;
    }

    final suggestedSlug = _suggestAddonPlanSlug(
      section: dialogState.selectedSection,
      linkedBasePlanKey: linkedBasePlanKey,
    );
    if (suggestedSlug.isEmpty) {
      return;
    }

    final currentSlug = dialogState.planSlugController.text
        .trim()
        .toLowerCase();
    final lastAutoSlug = dialogState.lastAutoSuggestedPlanSlug
        .trim()
        .toLowerCase();

    final canOverride =
        currentSlug.isEmpty ||
        (lastAutoSlug.isNotEmpty && currentSlug == lastAutoSlug);
    if (!canOverride) {
      return;
    }

    dialogState.planSlugController.text = suggestedSlug;
    dialogState.lastAutoSuggestedPlanSlug = suggestedSlug;
  }

  String _suggestAddonPlanSlug({
    required _StripePlanSection section,
    required String linkedBasePlanKey,
  }) {
    final normalizedBaseKey = linkedBasePlanKey
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (normalizedBaseKey.isEmpty) {
      return '';
    }

    if (section != _StripePlanSection.outros) {
      return 'extra_usuario';
    }

    final knownPrefixes = <String>{
      'individual',
      'representacoes',
      'enterprise',
    };
    final firstToken = normalizedBaseKey.split('_').first;
    if (knownPrefixes.contains(firstToken)) {
      return '${firstToken}_extra_usuario';
    }
    return '${normalizedBaseKey}_extra_usuario';
  }

  void _beginStripeCatalogCreationState({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    setLocalState(() {
      dialogState.errorText = null;
      dialogState.stripeCreateStatus = '';
      dialogState.isCreatingInStripe = true;
    });
  }

  String? _validateStripeCatalogBillingPlanKey({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    final billingPlanKey = _buildBillingPlanKey(
      dialogState.selectedSection,
      dialogState.planSlugController.text,
    );
    if (billingPlanKey.isNotEmpty) {
      return billingPlanKey;
    }

    _finishStripeCatalogCreationWithError(
      dialogState: dialogState,
      setLocalState: setLocalState,
      message: 'Informe o identificador do plano antes de criar no Stripe.',
    );
    return null;
  }

  int? _validateStripeCatalogAmountMinorUnits({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    final amountMinorUnits = _parseMinorUnitsFromAmountInput(
      dialogState.createAmountController.text,
    );
    if (amountMinorUnits != null && amountMinorUnits > 0) {
      return amountMinorUnits;
    }

    _finishStripeCatalogCreationWithError(
      dialogState: dialogState,
      setLocalState: setLocalState,
      message: 'Informe valor valido para criar no Stripe.',
    );
    return null;
  }

  String _resolveStripeCatalogPlanName(
    _StripePlanMappingDialogState dialogState, {
    required String billingPlanKey,
  }) {
    final planName = dialogState.planDisplayNameController.text.trim();
    if (planName.isNotEmpty) {
      return planName;
    }
    return billingPlanKey;
  }

  int _resolveStripeCatalogIntervalCount(
    _StripePlanMappingDialogState dialogState,
  ) {
    return int.tryParse(
          dialogState.createIntervalCountController.text.trim(),
        ) ??
        1;
  }

  String _resolveStripeCatalogLookupKey(
    _StripePlanMappingDialogState dialogState, {
    required String billingPlanKey,
    required int recurringIntervalCount,
  }) {
    final recommendedLookupKey = _buildRecommendedStripeLookupKey(
      billingPlanKey: billingPlanKey,
      currency: dialogState.createCurrency,
      recurringInterval: dialogState.createRecurringInterval,
      recurringIntervalCount: recurringIntervalCount,
    );
    final typedLookupKey = dialogState.createLookupKeyController.text.trim();
    if (typedLookupKey.isEmpty) {
      return recommendedLookupKey;
    }
    return typedLookupKey;
  }

  void _applyCreatedStripeCatalogResult({
    required _StripePlanMappingDialogState dialogState,
    required MaintainerStripeCreatedPlan created,
    required StateSetter setLocalState,
  }) {
    setLocalState(() {
      dialogState.createLookupKeyController.text = created.lookupKey;
      dialogState.productIdController.text = created.productId;
      dialogState.priceIdController.text = created.priceId;
      dialogState.stripeProductName = created.productName;
      dialogState.stripePriceNickname = created.priceNickname;
      dialogState.stripeUnitAmount = created.unitAmount;
      dialogState.stripeCurrency = created.currency;
      dialogState.stripeRecurringInterval = created.recurringInterval;
      dialogState.stripeRecurringIntervalCount = created.recurringIntervalCount;
      _fillStripePlanDisplayAmountIfEmpty(dialogState, created);
      dialogState.stripeCreateStatus =
          'Criado no Stripe (${created.activeEnvironment}). Product ${created.productId} e Price ${created.priceId}.';
      dialogState.isCreatingInStripe = false;
    });
  }

  void _fillStripePlanDisplayAmountIfEmpty(
    _StripePlanMappingDialogState dialogState,
    MaintainerStripeCreatedPlan created,
  ) {
    if (dialogState.planDisplayAmountController.text.trim().isNotEmpty) {
      return;
    }

    dialogState.planDisplayAmountController.text = _buildPlanDisplayAmountLabel(
      amountInMinorUnit: created.unitAmount,
      currency: created.currency,
      recurringInterval: created.recurringInterval,
      recurringIntervalCount: created.recurringIntervalCount,
    );
  }

  void _beginStripePlanMappingSaveState({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    setLocalState(() {
      dialogState.isSaving = true;
      dialogState.errorText = null;
    });
  }

  String? _validateStripePlanMappingBillingPlanKey({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    final billingPlanKey = _buildBillingPlanKey(
      dialogState.selectedSection,
      dialogState.planSlugController.text,
    );
    if (billingPlanKey.isNotEmpty) {
      return billingPlanKey;
    }

    _finishStripePlanMappingSaveWithError(
      dialogState: dialogState,
      setLocalState: setLocalState,
      message: 'Informe um identificador valido para o billingPlanKey.',
    );
    return null;
  }

  void _finishStripeCatalogCreationWithError({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
    required String message,
  }) {
    setLocalState(() {
      dialogState.isCreatingInStripe = false;
      dialogState.errorText = message;
    });
  }

  void _finishStripePlanMappingSaveWithError({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
    required String message,
  }) {
    setLocalState(() {
      dialogState.errorText = message;
      dialogState.isSaving = false;
    });
  }

  String _normalizeStripePlanDisplayName(
    _StripePlanMappingDialogState dialogState, {
    required String initialProductName,
  }) {
    final typedName = dialogState.planDisplayNameController.text.trim();
    if (typedName.isNotEmpty) {
      return dialogState.planDisplayNameController.text;
    }
    return initialProductName;
  }

  String _normalizeStripePlanDisplayAmount(
    _StripePlanMappingDialogState dialogState,
  ) {
    final typedAmount = dialogState.planDisplayAmountController.text.trim();
    if (typedAmount.isNotEmpty) {
      return dialogState.planDisplayAmountController.text;
    }
    return _buildPlanDisplayAmountLabel(
      amountInMinorUnit: dialogState.stripeUnitAmount,
      currency: dialogState.stripeCurrency,
      recurringInterval: dialogState.stripeRecurringInterval,
      recurringIntervalCount: dialogState.stripeRecurringIntervalCount,
    );
  }

  _StripePlanMappingUpsertPayload _buildStripePlanMappingUpsertPayload(
    _StripePlanMappingDialogState dialogState, {
    required String billingPlanKey,
    required String normalizedPlanDisplayName,
    required String normalizedPlanDisplayAmount,
  }) {
    final normalizedMappingType =
        dialogState.mappingType.trim().toLowerCase() == 'overage'
        ? 'overage'
        : 'base';

    final includedSeatsRaw = int.tryParse(
      dialogState.includedSeatsController.text.trim(),
    );
    final parsedIncludedSeats = includedSeatsRaw == null
        ? 0
        : (includedSeatsRaw < 0 ? 0 : includedSeatsRaw);

    final normalizedOverageMetric = normalizedMappingType == 'overage'
        ? (dialogState.overageMetricController.text.trim().isEmpty
              ? 'extra_usuario'
              : dialogState.overageMetricController.text.trim())
        : '';

    final normalizedSeatAddonPlanKey = normalizedMappingType == 'base'
        ? dialogState.seatAddonPlanKeyController.text
        : '';

    final normalizedLinkedBasePlanKey = normalizedMappingType == 'overage'
        ? dialogState.linkedBasePlanKeyController.text
        : '';

    final includedSeats = normalizedMappingType == 'base'
        ? parsedIncludedSeats
        : 0;

    return _StripePlanMappingUpsertPayload(
      billingPlanKey: billingPlanKey,
      planDisplayName: normalizedPlanDisplayName,
      planDisplayAmount: normalizedPlanDisplayAmount,
      stripeProductId: dialogState.productIdController.text,
      stripeProductName: dialogState.stripeProductName.trim().isEmpty
          ? normalizedPlanDisplayName
          : dialogState.stripeProductName,
      stripePriceId: dialogState.priceIdController.text,
      stripePriceNickname: dialogState.stripePriceNickname,
      stripeUnitAmount: dialogState.stripeUnitAmount,
      stripeCurrency: dialogState.stripeCurrency,
      stripeRecurringInterval: dialogState.stripeRecurringInterval,
      stripeRecurringIntervalCount: dialogState.stripeRecurringIntervalCount,
      mappingType: normalizedMappingType,
      overageMetric: normalizedOverageMetric,
      includedSeats: includedSeats,
      seatAddonPlanKey: normalizedSeatAddonPlanKey,
      linkedBasePlanKey: normalizedLinkedBasePlanKey,
      active: dialogState.active,
      actorUid: _currentActorUid(),
    );
  }

  bool _validateStripePlanMappingTypeRelations({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
    required String billingPlanKey,
  }) {
    final normalizedMappingType = dialogState.mappingType.trim().toLowerCase();
    if (normalizedMappingType != 'overage') {
      return true;
    }

    final linkedBasePlanKey = dialogState.linkedBasePlanKeyController.text
        .trim()
        .toLowerCase();
    if (linkedBasePlanKey.isEmpty) {
      _finishStripePlanMappingSaveWithError(
        dialogState: dialogState,
        setLocalState: setLocalState,
        message:
            'Para aditivo, selecione um plano base em "Plano base vinculado".',
      );
      return false;
    }

    if (linkedBasePlanKey == billingPlanKey.trim().toLowerCase()) {
      _finishStripePlanMappingSaveWithError(
        dialogState: dialogState,
        setLocalState: setLocalState,
        message: 'Plano aditivo nao pode apontar para ele mesmo como base.',
      );
      return false;
    }

    return true;
  }

  Future<void> _persistStripePlanMapping(
    _StripePlanMappingUpsertPayload payload,
  ) async {
    await _billingIntegrationService.upsertPlanMapping(
      billingPlanKey: payload.billingPlanKey,
      planDisplayName: payload.planDisplayName,
      planDisplayAmount: payload.planDisplayAmount,
      stripeProductId: payload.stripeProductId,
      stripeProductName: payload.stripeProductName,
      stripePriceId: payload.stripePriceId,
      stripePriceNickname: payload.stripePriceNickname,
      stripeUnitAmount: payload.stripeUnitAmount,
      stripeCurrency: payload.stripeCurrency,
      stripeRecurringInterval: payload.stripeRecurringInterval,
      stripeRecurringIntervalCount: payload.stripeRecurringIntervalCount,
      mappingType: payload.mappingType,
      overageMetric: payload.overageMetric,
      includedSeats: payload.includedSeats,
      seatAddonPlanKey: payload.seatAddonPlanKey,
      linkedBasePlanKey: payload.linkedBasePlanKey,
      active: payload.active,
      actorUid: payload.actorUid,
    );
  }
}
