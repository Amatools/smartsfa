class WebPortalDashboardFormatService {
  const WebPortalDashboardFormatService._();

  static String formatCurrencyBr(double value) {
    final negative = value < 0;
    final normalized = value.abs();
    final cents = (normalized * 100).round();
    final integerPart = cents ~/ 100;
    final decimalPart = cents % 100;
    final digits = integerPart.toString();

    final grouped = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      final reverseIndex = digits.length - index;
      grouped.write(digits[index]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        grouped.write('.');
      }
    }

    final base =
        '${grouped.toString()},${decimalPart.toString().padLeft(2, '0')}';
    if (negative) {
      return '-R\$ $base';
    }
    return 'R\$ $base';
  }

  static String formatCompactCurrencyBr(double value) {
    final absolute = value.abs();
    if (absolute >= 1000000) {
      return 'R\$ ${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (absolute >= 1000) {
      return 'R\$ ${(value / 1000).toStringAsFixed(1)}k';
    }
    return formatCurrencyBr(value);
  }

  static String formatDayDdMm(DateTime day) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(day.day)}/${twoDigits(day.month)}';
  }

  static String formatDeltaPercent({
    required double current,
    required double baseline,
  }) {
    if (baseline == 0 && current == 0) {
      return '0.0%';
    }
    if (baseline == 0 && current > 0) {
      return '+100.0%';
    }
    final delta = ((current - baseline) / baseline) * 100;
    final prefix = delta >= 0 ? '+' : '';
    return '$prefix${delta.toStringAsFixed(1)}%';
  }
}
