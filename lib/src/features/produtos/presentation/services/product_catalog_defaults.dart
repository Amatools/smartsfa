class ProductCatalogDefaults {
  ProductCatalogDefaults._();

  static const String defaultCurrencyCode = 'BRL';
  static const String unknownErrorMessage = 'erro desconhecido';

  static const Map<String, String> currencyLabels = <String, String>{
    'BRL': 'R\$',
    'USD': 'US\$',
    'EUR': 'EUR',
  };
}
