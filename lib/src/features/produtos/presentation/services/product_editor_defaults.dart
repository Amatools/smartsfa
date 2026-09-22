class ProductEditorDefaults {
  ProductEditorDefaults._();

  static const String defaultCurrencyCode = 'BRL';
  static const String defaultBitolaUnit = 'mm';
  static const String defaultManualVersion = 'manual-v1';
  static const String unknownErrorMessage = 'erro desconhecido';

  static const List<String> bitolaUnits = <String>[
    defaultBitolaUnit,
    'cm',
    'm',
  ];

  static const Map<String, String> currencyLabels = <String, String>{
    'BRL': 'R\$',
    'USD': 'US\$',
    'EUR': 'EUR',
  };

  static const Map<String, String> currencyHints = <String, String>{
    'BRL': '0,00',
    'USD': '0.00',
    'EUR': '0,00',
  };
}
