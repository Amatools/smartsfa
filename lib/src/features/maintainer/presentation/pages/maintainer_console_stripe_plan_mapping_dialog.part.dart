part of 'maintainer_console_page.dart';

extension _MaintainerConsoleStripePlanMappingDialogPart
    on _MaintainerConsolePageState {
  Future<void> _openStripePlanMappingDialog({
    _StripePlanSection initialSection = _StripePlanSection.individual,
    String initialPlanSlug = '',
    String initialPlanDisplayName = '',
    String initialPlanDisplayAmount = '',
    String initialProductId = '',
    String initialProductName = '',
    String initialPriceId = '',
    String initialPriceNickname = '',
    int initialUnitAmount = 0,
    String initialCurrency = '',
    String initialRecurringInterval = '',
    int initialRecurringIntervalCount = 0,
    String initialMappingType = 'base',
  }) async {
    final dialogState = _StripePlanMappingDialogState(
      initialSection: initialSection,
      initialPlanSlug: initialPlanSlug,
      initialPlanDisplayName: initialPlanDisplayName,
      initialPlanDisplayAmount: initialPlanDisplayAmount,
      initialProductId: initialProductId,
      initialPriceId: initialPriceId,
      initialUnitAmount: initialUnitAmount,
      initialRecurringIntervalCount: initialRecurringIntervalCount,
      initialMappingType: initialMappingType,
      initialCurrency: initialCurrency,
      initialRecurringInterval: initialRecurringInterval,
      initialProductName: initialProductName,
      initialPriceNickname: initialPriceNickname,
    );

    _initializeStripeDialogLookupKey(
      dialogState: dialogState,
      initialPlanSlug: initialPlanSlug,
      initialRecurringIntervalCount: initialRecurringIntervalCount,
    );

    final saved = await _showStripePlanMappingDialog(
      dialogState: dialogState,
      initialProductName: initialProductName,
    );

    _disposeTextEditingControllersSafely(dialogState.controllers);

    if (saved == true && mounted) {
      _showStripePlanMappingSavedFeedback();
    }
  }

  void _initializeStripeDialogLookupKey({
    required _StripePlanMappingDialogState dialogState,
    required String initialPlanSlug,
    required int initialRecurringIntervalCount,
  }) {
    dialogState.createLookupKeyController.text =
        _buildRecommendedStripeLookupKey(
          billingPlanKey: _buildBillingPlanKey(
            dialogState.selectedSection,
            initialPlanSlug,
          ),
          currency: dialogState.createCurrency,
          recurringInterval: dialogState.createRecurringInterval,
          recurringIntervalCount: initialRecurringIntervalCount,
        );
  }

  Future<bool?> _showStripePlanMappingDialog({
    required _StripePlanMappingDialogState dialogState,
    required String initialProductName,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Novo mapeamento Stripe'),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _buildStripePlanMappingDialogContent(
                      context: context,
                      dialogState: dialogState,
                      setLocalState: setLocalState,
                    ),
                  ),
                ),
              ),
              actions: _buildStripePlanMappingDialogActions(
                dialogContext: dialogContext,
                dialogState: dialogState,
                setLocalState: setLocalState,
                initialProductName: initialProductName,
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildStripePlanMappingDialogActions({
    required BuildContext dialogContext,
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
    required String initialProductName,
  }) {
    return [
      TextButton(
        onPressed: dialogState.isSaving
            ? null
            : () => Navigator.of(dialogContext).pop(false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: dialogState.isSaving
            ? null
            : () => _saveStripePlanMappingFromDialog(
                dialogContext: dialogContext,
                setLocalState: setLocalState,
                dialogState: dialogState,
                initialProductName: initialProductName,
              ),
        child: const Text('Salvar mapeamento'),
      ),
    ];
  }

  void _showStripePlanMappingSavedFeedback() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mapeamento Stripe salvo.')));
  }

  Future<void> _createStripeCatalogArtifactsFromDialog({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) async {
    _beginStripeCatalogCreationState(
      dialogState: dialogState,
      setLocalState: setLocalState,
    );

    final billingPlanKey = _validateStripeCatalogBillingPlanKey(
      dialogState: dialogState,
      setLocalState: setLocalState,
    );
    if (billingPlanKey == null) {
      return;
    }

    final amountMinorUnits = _validateStripeCatalogAmountMinorUnits(
      dialogState: dialogState,
      setLocalState: setLocalState,
    );
    if (amountMinorUnits == null) {
      return;
    }

    final planName = _resolveStripeCatalogPlanName(
      dialogState,
      billingPlanKey: billingPlanKey,
    );
    final intervalCount = _resolveStripeCatalogIntervalCount(dialogState);
    final effectiveLookupKey = _resolveStripeCatalogLookupKey(
      dialogState,
      billingPlanKey: billingPlanKey,
      recurringIntervalCount: intervalCount,
    );

    try {
      final created = await _billingIntegrationService.createStripeCatalogPlan(
        productName: planName,
        productDescription: 'Gerado no painel admin para $billingPlanKey',
        amountMinorUnits: amountMinorUnits,
        currency: dialogState.createCurrency,
        recurringInterval: dialogState.createRecurringInterval,
        recurringIntervalCount: intervalCount,
        priceNickname: planName,
        lookupKey: effectiveLookupKey,
        billingPlanKey: billingPlanKey,
      );

      _applyCreatedStripeCatalogResult(
        dialogState: dialogState,
        created: created,
        setLocalState: setLocalState,
      );
    } catch (error) {
      _finishStripeCatalogCreationWithError(
        dialogState: dialogState,
        setLocalState: setLocalState,
        message: 'Falha ao criar no Stripe: $error',
      );
    }
  }

  Future<void> _saveStripePlanMappingFromDialog({
    required BuildContext dialogContext,
    required StateSetter setLocalState,
    required _StripePlanMappingDialogState dialogState,
    required String initialProductName,
  }) async {
    _beginStripePlanMappingSaveState(
      dialogState: dialogState,
      setLocalState: setLocalState,
    );

    final billingPlanKey = _validateStripePlanMappingBillingPlanKey(
      dialogState: dialogState,
      setLocalState: setLocalState,
    );
    if (billingPlanKey == null) {
      return;
    }

    try {
      final normalizedPlanDisplayName = _normalizeStripePlanDisplayName(
        dialogState,
        initialProductName: initialProductName,
      );
      final normalizedPlanDisplayAmount = _normalizeStripePlanDisplayAmount(
        dialogState,
      );
      final payload = _buildStripePlanMappingUpsertPayload(
        dialogState,
        billingPlanKey: billingPlanKey,
        normalizedPlanDisplayName: normalizedPlanDisplayName,
        normalizedPlanDisplayAmount: normalizedPlanDisplayAmount,
      );
      await _persistStripePlanMapping(payload);

      if (!dialogContext.mounted) {
        return;
      }
      Navigator.of(dialogContext).pop(true);
    } catch (error) {
      _finishStripePlanMappingSaveWithError(
        dialogState: dialogState,
        setLocalState: setLocalState,
        message: 'Falha ao salvar mapeamento Stripe: $error',
      );
    }
  }
}
