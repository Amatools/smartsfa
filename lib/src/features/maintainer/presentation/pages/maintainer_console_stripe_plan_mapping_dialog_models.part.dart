part of 'maintainer_console_page.dart';

class _StripeBasePlanOption {
  const _StripeBasePlanOption({
    required this.billingPlanKey,
    required this.planDisplayName,
  });

  final String billingPlanKey;
  final String planDisplayName;

  String get displayLabel {
    final name = planDisplayName.trim();
    if (name.isEmpty) {
      return billingPlanKey;
    }
    return '$name ($billingPlanKey)';
  }
}

class _StripePlanMappingDialogState {
  _StripePlanMappingDialogState({
    required _StripePlanSection initialSection,
    required String initialPlanSlug,
    required String initialPlanDisplayName,
    required String initialPlanDisplayAmount,
    required String initialProductId,
    required String initialPriceId,
    required int initialUnitAmount,
    required int initialRecurringIntervalCount,
    required String initialMappingType,
    required String initialCurrency,
    required String initialRecurringInterval,
    required String initialProductName,
    required String initialPriceNickname,
    required String initialOverageMetric,
    required int initialIncludedSeats,
    required String initialSeatAddonPlanKey,
    required String initialLinkedBasePlanKey,
    required List<_StripeBasePlanOption> initialBasePlanOptions,
  }) : selectedSection = initialSection,
       planSlugController = TextEditingController(text: initialPlanSlug),
       planDisplayNameController = TextEditingController(
         text: initialPlanDisplayName,
       ),
       planDisplayAmountController = TextEditingController(
         text: initialPlanDisplayAmount,
       ),
       productIdController = TextEditingController(text: initialProductId),
       priceIdController = TextEditingController(text: initialPriceId),
       overageMetricController = TextEditingController(
         text: initialOverageMetric,
       ),
       includedSeatsController = TextEditingController(
         text: initialIncludedSeats > 0 ? initialIncludedSeats.toString() : '',
       ),
       linkedBasePlanKeyController = TextEditingController(
         text: _resolveInitialLinkedBasePlanKey(
           initialMappingType: initialMappingType,
           initialLinkedBasePlanKey: initialLinkedBasePlanKey,
           initialBasePlanOptions: initialBasePlanOptions,
         ),
       ),
       createAmountController = TextEditingController(
         text: initialUnitAmount > 0
             ? (initialUnitAmount / 100).toStringAsFixed(2)
             : '',
       ),
       createIntervalCountController = TextEditingController(
         text: initialRecurringIntervalCount <= 0
             ? '1'
             : initialRecurringIntervalCount.toString(),
       ),
       createLookupKeyController = TextEditingController(),
       mappingType = initialMappingType.trim().toLowerCase() == 'overage'
           ? 'overage'
           : 'base',
       createCurrency = _normalizeCurrency(initialCurrency),
       createRecurringInterval = _normalizeRecurringInterval(
         initialRecurringInterval,
       ),
       stripeProductName = initialProductName.trim(),
       stripePriceNickname = initialPriceNickname.trim(),
       stripeUnitAmount = initialUnitAmount,
       stripeCurrency = initialCurrency.trim().toLowerCase(),
       stripeRecurringInterval = initialRecurringInterval.trim().toLowerCase(),
       stripeRecurringIntervalCount = initialRecurringIntervalCount,
       initialSeatAddonPlanKey = initialSeatAddonPlanKey.trim().toLowerCase(),
       basePlanOptions = _normalizeBasePlanOptions(
         options: initialBasePlanOptions,
         initialLinkedBasePlanKey: initialLinkedBasePlanKey,
       ),
       active = true;

  final TextEditingController planSlugController;
  final TextEditingController planDisplayNameController;
  final TextEditingController planDisplayAmountController;
  final TextEditingController productIdController;
  final TextEditingController priceIdController;
  final TextEditingController overageMetricController;
  final TextEditingController includedSeatsController;
  final TextEditingController linkedBasePlanKeyController;
  final TextEditingController createAmountController;
  final TextEditingController createIntervalCountController;
  final TextEditingController createLookupKeyController;
  final String initialSeatAddonPlanKey;

  _StripePlanSection selectedSection;
  String mappingType;
  String createCurrency;
  String createRecurringInterval;
  String stripeProductName;
  String stripePriceNickname;
  int stripeUnitAmount;
  String stripeCurrency;
  String stripeRecurringInterval;
  int stripeRecurringIntervalCount;
  final List<_StripeBasePlanOption> basePlanOptions;
  bool active;
  bool isSaving = false;
  bool isCreatingInStripe = false;
  String stripeCreateStatus = '';
  String? errorText;
  String lastAutoSuggestedPlanSlug = '';

  bool get isAddonMapping => mappingType.trim().toLowerCase() == 'overage';

  List<TextEditingController> get controllers => [
    planSlugController,
    planDisplayNameController,
    planDisplayAmountController,
    productIdController,
    priceIdController,
    overageMetricController,
    includedSeatsController,
    linkedBasePlanKeyController,
    createAmountController,
    createIntervalCountController,
    createLookupKeyController,
  ];

  static String _normalizeCurrency(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (<String>{'brl', 'usd', 'eur'}.contains(normalized)) {
      return normalized;
    }
    return 'brl';
  }

  static String _normalizeRecurringInterval(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'month';
    }
    if (<String>{'day', 'week', 'month', 'year'}.contains(normalized)) {
      return normalized;
    }
    return 'month';
  }

  static List<_StripeBasePlanOption> _normalizeBasePlanOptions({
    required List<_StripeBasePlanOption> options,
    required String initialLinkedBasePlanKey,
  }) {
    final normalized = <_StripeBasePlanOption>[];
    final seenKeys = <String>{};

    for (final option in options) {
      final key = option.billingPlanKey.trim().toLowerCase();
      if (key.isEmpty || !seenKeys.add(key)) {
        continue;
      }
      normalized.add(
        _StripeBasePlanOption(
          billingPlanKey: key,
          planDisplayName: option.planDisplayName.trim(),
        ),
      );
    }

    normalized.sort((a, b) => a.billingPlanKey.compareTo(b.billingPlanKey));

    final initialKey = initialLinkedBasePlanKey.trim().toLowerCase();
    if (initialKey.isNotEmpty && seenKeys.add(initialKey)) {
      normalized.add(
        _StripeBasePlanOption(billingPlanKey: initialKey, planDisplayName: ''),
      );
    }

    return List<_StripeBasePlanOption>.unmodifiable(normalized);
  }

  static String _resolveInitialLinkedBasePlanKey({
    required String initialMappingType,
    required String initialLinkedBasePlanKey,
    required List<_StripeBasePlanOption> initialBasePlanOptions,
  }) {
    final normalizedInitial = initialLinkedBasePlanKey.trim().toLowerCase();
    if (normalizedInitial.isNotEmpty) {
      return normalizedInitial;
    }

    final isAddon = initialMappingType.trim().toLowerCase() == 'overage';
    if (!isAddon) {
      return '';
    }

    for (final option in initialBasePlanOptions) {
      final key = option.billingPlanKey.trim().toLowerCase();
      if (key.isNotEmpty) {
        return key;
      }
    }
    return '';
  }
}

class _StripePlanMappingUpsertPayload {
  const _StripePlanMappingUpsertPayload({
    required this.billingPlanKey,
    required this.planDisplayName,
    required this.planDisplayAmount,
    required this.stripeProductId,
    required this.stripeProductName,
    required this.stripePriceId,
    required this.stripePriceNickname,
    required this.stripeUnitAmount,
    required this.stripeCurrency,
    required this.stripeRecurringInterval,
    required this.stripeRecurringIntervalCount,
    required this.mappingType,
    required this.overageMetric,
    required this.includedSeats,
    required this.seatAddonPlanKey,
    required this.linkedBasePlanKey,
    required this.active,
    required this.actorUid,
  });

  final String billingPlanKey;
  final String planDisplayName;
  final String planDisplayAmount;
  final String stripeProductId;
  final String stripeProductName;
  final String stripePriceId;
  final String stripePriceNickname;
  final int stripeUnitAmount;
  final String stripeCurrency;
  final String stripeRecurringInterval;
  final int stripeRecurringIntervalCount;
  final String mappingType;
  final String overageMetric;
  final int includedSeats;
  final String seatAddonPlanKey;
  final String linkedBasePlanKey;
  final bool active;
  final String actorUid;
}
