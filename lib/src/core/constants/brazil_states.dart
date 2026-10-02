const List<String> brazilStates = <String>[
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA',
  'PB',
  'PR',
  'PE',
  'PI',
  'RJ',
  'RN',
  'RS',
  'RO',
  'RR',
  'SC',
  'SP',
  'SE',
  'TO',
];

String normalizeBrazilState(String? value) {
  return (value ?? '').trim().toUpperCase();
}

bool isBrazilState(String? value) {
  final normalized = normalizeBrazilState(value);
  return brazilStates.contains(normalized);
}

String? brazilStateOrNull(String? value) {
  final normalized = normalizeBrazilState(value);
  if (brazilStates.contains(normalized)) {
    return normalized;
  }
  return null;
}
