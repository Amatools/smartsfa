/// Pure text/number formatting and normalization helpers used across the
/// pedidos (order) presentation layer. Extracted from `pedidos_page.dart`
/// to reduce that file's size and keep these utilities independently
/// testable (SRP).
class PedidoFormatUtils {
  const PedidoFormatUtils._();

  static double roundCurrency(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  static String formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String formatQuantity(double value) {
    return value.round().toString();
  }

  static String formatPercent(double value) {
    final hasFraction = (value % 1).abs() > 0.00001;
    final formatted = hasFraction
        ? value.toStringAsFixed(2).replaceAll('.', ',')
        : value.toStringAsFixed(0);
    return '$formatted%';
  }

  static int readIntegerQuantity(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    return int.tryParse(trimmed) ?? 0;
  }

  static String taxMatchTierLabel(int? tier) {
    switch (tier) {
      case 0:
        return 'Regra especifica do produto';
      case 1:
        return 'Regra do grupo tributario';
      case 2:
        return 'Regra por NCM';
      case 3:
        return 'Regra geral por UF';
      default:
        return 'Nao identificado';
    }
  }

  static String normalizeSearch(String value) {
    var normalized = value.toLowerCase().trim();
    const replacements = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };
    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  static bool isSubsequence(String needle, String haystack) {
    if (needle.isEmpty) {
      return true;
    }
    var i = 0;
    for (var j = 0; j < haystack.length && i < needle.length; j++) {
      if (needle.codeUnitAt(i) == haystack.codeUnitAt(j)) {
        i++;
      }
    }
    return i == needle.length;
  }

  static String pedidoDisplayNumber(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return '-';
    }

    final parts = normalized.split('_');
    final candidate = parts.isNotEmpty ? parts.last.trim() : normalized;
    if (candidate.isNotEmpty && RegExp(r'^\d+$').hasMatch(candidate)) {
      return candidate;
    }

    final digits = RegExp(
      r'\d+',
    ).allMatches(normalized).map((m) => m.group(0)).whereType<String>().join();
    if (digits.isNotEmpty) {
      return digits;
    }

    return normalized;
  }

  static String formatMoneyBr(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }
}
