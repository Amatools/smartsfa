class ProductFormValueCodec {
  const ProductFormValueCodec._();

  static String toText(double? value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  static String formatMoneyForCurrency({
    required double value,
    required String currencyCode,
  }) {
    final normalized = value.toStringAsFixed(2);
    if (currencyCode == 'USD') {
      return normalized;
    }
    return normalized.replaceAll('.', ',');
  }

  static double? parseDecimal(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final raw = normalized.replaceAll(' ', '');
    final lastComma = raw.lastIndexOf(',');
    final lastDot = raw.lastIndexOf('.');

    if (lastComma >= 0 && lastDot >= 0) {
      if (lastComma > lastDot) {
        final brStyle = raw.replaceAll('.', '').replaceAll(',', '.');
        return double.tryParse(brStyle);
      }
      final usStyle = raw.replaceAll(',', '');
      return double.tryParse(usStyle);
    }

    if (lastComma >= 0) {
      return double.tryParse(raw.replaceAll(',', '.'));
    }

    return double.tryParse(raw);
  }

  static String? nullableText(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}