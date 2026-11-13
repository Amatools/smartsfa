part of 'maintainer_console_page.dart';

extension _MaintainerConsoleStripeHelpersPart on _MaintainerConsolePageState {
  List<String> _parseWebhookEvents(String raw) {
    return raw
        .split(RegExp(r'[\n,;]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
  }

  _StripePlanSection _stripePlanSectionFromPlanKey(String billingPlanKey) {
    final key = billingPlanKey.trim().toLowerCase();
    if (key.startsWith('individual_')) {
      return _StripePlanSection.individual;
    }
    if (key.startsWith('representacoes_')) {
      return _StripePlanSection.representacoes;
    }
    if (key.startsWith('enterprise_')) {
      return _StripePlanSection.enterprise;
    }
    return _StripePlanSection.outros;
  }

  String _stripePlanSectionLabel(_StripePlanSection section) {
    switch (section) {
      case _StripePlanSection.individual:
        return 'Planos - Conta individual';
      case _StripePlanSection.representacoes:
        return 'Planos - Conta representacoes';
      case _StripePlanSection.enterprise:
        return 'Planos - Conta enterprise';
      case _StripePlanSection.outros:
        return 'Outros mapeamentos';
    }
  }

  String _stripePlanSectionDescription(_StripePlanSection section) {
    switch (section) {
      case _StripePlanSection.individual:
        return 'Use para planos da familia individual_* (ex.: individual_base, individual_pro).';
      case _StripePlanSection.representacoes:
        return 'Use para planos da familia representacoes_* (ex.: representacoes_base, representacoes_pro).';
      case _StripePlanSection.enterprise:
        return 'Use para planos da familia enterprise_* (ex.: enterprise_custom).';
      case _StripePlanSection.outros:
        return 'Exibe chaves fora das tres familias principais (ex.: overages legados).';
    }
  }

  String _buildBillingPlanKey(_StripePlanSection section, String rawSlug) {
    final slug = rawSlug.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]+'),
      '_',
    );
    if (slug.isEmpty) {
      return '';
    }
    if (section == _StripePlanSection.outros) {
      return slug;
    }
    final prefix = switch (section) {
      _StripePlanSection.individual => 'individual',
      _StripePlanSection.representacoes => 'representacoes',
      _StripePlanSection.enterprise => 'enterprise',
      _StripePlanSection.outros => '',
    };
    if (prefix.isEmpty) {
      return slug;
    }
    if (slug.startsWith('${prefix}_')) {
      return slug;
    }
    return '${prefix}_$slug';
  }

  String _defaultStripeWebhookBaseUrl() {
    return 'https://${_MaintainerConsolePageState._defaultCloudFunctionsRegion}-${_MaintainerConsolePageState._defaultFirebaseProjectId}.cloudfunctions.net/';
  }

  String _defaultStripeWebhookEndpointUrl() {
    return '${_defaultStripeWebhookBaseUrl()}${_MaintainerConsolePageState._defaultStripeWebhookFunctionName}';
  }

  String _normalizeWebhookEndpointInput({
    required String rawInput,
    required String defaultBaseUrl,
  }) {
    final normalized = rawInput.trim();
    if (normalized.isEmpty) {
      return '';
    }

    final lower = normalized.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return normalized;
    }

    var suffix = normalized;
    if (suffix.startsWith('/')) {
      suffix = suffix.substring(1);
    }
    if (suffix.isEmpty) {
      suffix = _MaintainerConsolePageState._defaultStripeWebhookFunctionName;
    }

    final base = defaultBaseUrl.endsWith('/')
        ? defaultBaseUrl
        : '$defaultBaseUrl/';
    return '$base$suffix';
  }

  String _suggestPlanSlugFromStripe(String productName, String priceNickname) {
    final source = '$productName $priceNickname'.trim().toLowerCase();
    final normalized = source
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    if (normalized.isEmpty) {
      return 'base';
    }

    if (normalized.contains('pro')) {
      return 'pro';
    }
    if (normalized.contains('base') || normalized.contains('basic')) {
      return 'base';
    }
    if (normalized.contains('custom') || normalized.contains('enterprise')) {
      return 'custom';
    }
    return normalized.length > 40 ? normalized.substring(0, 40) : normalized;
  }

  String _formatStripeAmountLabel({
    required int amountInMinorUnit,
    required String currency,
  }) {
    final amount = amountInMinorUnit / 100;
    final symbol = currency.trim().toLowerCase() == 'brl' ? 'R\$' : currency;
    return '$symbol ${amount.toStringAsFixed(2)}';
  }

  int? _parseMinorUnitsFromAmountInput(String rawInput) {
    final normalized = rawInput.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }

    final value = double.tryParse(normalized);
    if (value == null || value <= 0) {
      return null;
    }
    return (value * 100).round();
  }

  String _buildRecommendedStripeLookupKey({
    required String billingPlanKey,
    required String currency,
    required String recurringInterval,
    required int recurringIntervalCount,
  }) {
    final normalizedPlanKey = billingPlanKey
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    if (normalizedPlanKey.isEmpty) {
      return '';
    }

    final normalizedCurrency = currency.trim().toLowerCase();
    final interval = recurringInterval.trim().toLowerCase();
    final intervalCount = recurringIntervalCount <= 0 ? 1 : recurringIntervalCount;
    final countSuffix = intervalCount > 1 ? 'x$intervalCount' : '';

    final raw =
        'smartsfa_${normalizedPlanKey}_${normalizedCurrency}_$interval$countSuffix';
    final compact = raw
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    if (compact.length <= 120) {
      return compact;
    }
    return compact.substring(0, 120);
  }

  String _buildPlanDisplayAmountLabel({
    required int amountInMinorUnit,
    required String currency,
    required String recurringInterval,
    required int recurringIntervalCount,
  }) {
    final amountLabel = _formatStripeAmountLabel(
      amountInMinorUnit: amountInMinorUnit,
      currency: currency,
    );
    final interval = recurringInterval.trim().toLowerCase();
    if (interval.isEmpty) {
      return amountLabel;
    }
    final count = recurringIntervalCount <= 0 ? 1 : recurringIntervalCount;
    return '$amountLabel / $interval x$count';
  }
}
