import '../../../../core/models/produto.dart';

class ProductListPriceFormatter {
  static String format(
    Produto produto, {
    required String defaultCurrencyCode,
    required Map<String, String> currencyLabels,
  }) {
    final value = produto.valorBruto;
    if (value == null) {
      return '---';
    }
    final currencyCode =
        (produto.moeda ?? defaultCurrencyCode).trim().toUpperCase();
    final symbol = currencyLabels[currencyCode] ?? currencyCode;
    final normalized = value.toStringAsFixed(2);
    final formatted =
        currencyCode == 'USD' ? normalized : normalized.replaceAll('.', ',');
    return '$symbol $formatted';
  }
}