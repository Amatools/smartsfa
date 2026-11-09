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
    final parts = normalized.split('.');
    final integerPart = parts.first;
    final decimalPart = parts.length > 1 ? parts[1] : '00';

    if (currencyCode == 'USD') {
      return '${_groupThousands(integerPart, ',')}.$decimalPart';
    }

    return '${_groupThousands(integerPart, '.')},$decimalPart';
  }

  static String _groupThousands(String integerPart, String separator) {
    final negative = integerPart.startsWith('-');
    final digits = negative ? integerPart.substring(1) : integerPart;
    if (digits.length <= 3) {
      return negative ? '-$digits' : digits;
    }

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final reverseIndex = digits.length - i;
      buffer.write(digits[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(separator);
      }
    }

    final grouped = buffer.toString();
    return negative ? '-$grouped' : grouped;
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
