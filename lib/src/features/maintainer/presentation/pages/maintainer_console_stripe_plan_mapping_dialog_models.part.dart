part of 'maintainer_console_page.dart';

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
       overageMetricController = TextEditingController(),
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
       active = true;

  final TextEditingController planSlugController;
  final TextEditingController planDisplayNameController;
  final TextEditingController planDisplayAmountController;
  final TextEditingController productIdController;
  final TextEditingController priceIdController;
  final TextEditingController overageMetricController;
  final TextEditingController createAmountController;
  final TextEditingController createIntervalCountController;
  final TextEditingController createLookupKeyController;

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
  bool active;
  bool isSaving = false;
  bool isCreatingInStripe = false;
  String stripeCreateStatus = '';
  String? errorText;

  List<TextEditingController> get controllers => [
    planSlugController,
    planDisplayNameController,
    planDisplayAmountController,
    productIdController,
    priceIdController,
    overageMetricController,
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
  final bool active;
  final String actorUid;
}
