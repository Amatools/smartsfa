import '../../../../core/models/product_base_price.dart';
import 'product_form_value_codec.dart';

class ProductEditorDefaultTablePriceState {
  const ProductEditorDefaultTablePriceState({
    required this.currencyCode,
    required this.formattedValue,
  });

  final String currencyCode;
  final String formattedValue;
}

class ProductEditorDefaultTablePriceLoader {
  static ProductEditorDefaultTablePriceState fromBasePrice({
    required ProductBasePrice selected,
    required String currentCurrencyCode,
    required Map<String, String> currencyLabels,
  }) {
    final loadedCurrency =
        (selected.currencyCode ?? currentCurrencyCode).trim().toUpperCase();
    final resolvedCurrency =
        currencyLabels.containsKey(loadedCurrency) ? loadedCurrency : currentCurrencyCode;
    final formattedValue = ProductFormValueCodec.formatMoneyForCurrency(
      value: selected.basePrice,
      currencyCode: resolvedCurrency,
    );

    return ProductEditorDefaultTablePriceState(
      currencyCode: resolvedCurrency,
      formattedValue: formattedValue,
    );
  }
}