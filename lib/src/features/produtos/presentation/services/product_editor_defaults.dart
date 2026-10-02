class ProductEditorDefaults {
  ProductEditorDefaults._();

  static const String defaultCurrencyCode = 'BRL';
  static const String defaultBitolaUnit = 'milimetro';
  static const String defaultStandardUnit = 'Unidade';
  static const String unknownErrorMessage = 'erro desconhecido';

  static const List<String> bitolaUnits = <String>[
    defaultBitolaUnit,
    'centimetro',
    'metro',
    'ml',
    'litro',
  ];

  static const Map<String, String> bitolaUnitShortCodes = <String, String>{
    'milimetro': 'mm',
    'centimetro': 'cm',
    'metro': 'm',
    'ml': 'ml',
    'litro': 'l',
  };

  static const List<String> standardUnits = <String>[
    defaultStandardUnit,
    'Kit',
    'Jogo',
    'Frasco',
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
