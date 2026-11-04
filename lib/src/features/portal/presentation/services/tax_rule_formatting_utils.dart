import '../../../../core/models/tax_rule.dart';

/// Utilitarios puros de normalizacao/formatacao/fingerprint de `TaxRule`,
/// compartilhados entre a UI de Regras de Tributacao
/// (`web_portal_tax_rules_section.dart`, `tax_rule_form_dialog.dart`) e o
/// servico de import/export (`tax_rule_import_export_service.dart`), para
/// evitar duplicacao de regras de negocio entre as camadas.

/// Valores tratados como "sem UF selecionada" ao normalizar para storage.
const Set<String> _noUfStorageSentinels = <String>{'', 'ANY', 'SELECIONE'};

/// Converte um texto numerico (vírgula ou ponto decimal) em `double`,
/// retornando `null` quando o texto estiver vazio ou nao for um numero
/// valido (ex.: mais de um separador decimal, caracteres nao numericos).
double? parseDoubleOrNull(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return null;
  }
  if (RegExp(r'[^0-9.]').hasMatch(normalized)) {
    return null;
  }
  if ('.'.allMatches(normalized).length > 1) {
    return null;
  }
  return double.tryParse(normalized);
}

/// Igual a [parseDoubleOrNull], mas aceita `value` nulo (trata como vazio).
double? nullableDouble(String? value) {
  final normalized = (value ?? '').trim();
  if (normalized.isEmpty) {
    return null;
  }
  return parseDoubleOrNull(normalized);
}

String normalizeNcmDigits(String? value) {
  return (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
}

String normalizeCestDigits(String? value) {
  return (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
}

bool isValidNcmDigits(String digits) {
  return RegExp(r'^\d{8}$').hasMatch(digits);
}

bool isValidCestDigits(String digits) {
  return RegExp(r'^\d{7}$').hasMatch(digits);
}

String formatNcmMasked(String? value) {
  final digits = normalizeNcmDigits(value);
  if (digits.isEmpty) {
    return '';
  }
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length && i < 8; i++) {
    if (i == 4 || i == 6) {
      buffer.write('.');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String formatCestMasked(String? value) {
  final digits = normalizeCestDigits(value);
  if (digits.isEmpty) {
    return '';
  }
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length && i < 7; i++) {
    if (i == 2 || i == 5) {
      buffer.write('.');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Normaliza um valor de UF para armazenamento: vazio, "ANY" e o placeholder
/// de selecao do dropdown ("SELECIONE") viram string vazia (sem restricao).
String normalizeUfForStorage(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  if (_noUfStorageSentinels.contains(normalized)) {
    return '';
  }
  return normalized;
}

DateTime? toUtcStartOfDay(DateTime? value) {
  if (value == null) {
    return null;
  }
  return DateTime.utc(value.year, value.month, value.day);
}

DateTime? toUtcEndOfDay(DateTime? value) {
  if (value == null) {
    return null;
  }
  return DateTime.utc(value.year, value.month, value.day, 23, 59, 59, 999);
}

String? nullableTrimmed(String? value) {
  final normalized = (value ?? '').trim();
  if (normalized.isEmpty) {
    return null;
  }
  return normalized;
}

String withFallback(String? value, String fallback) {
  final normalized = (value ?? '').trim();
  return normalized.isEmpty ? fallback : normalized;
}

/// Fingerprint deterministico do perfil fiscal de uma regra, usado para
/// deduplicacao no agrupamento automatico e na importacao de planilha
/// (evita regravar/duplicar uma regra cujo conteudo fiscal nao mudou).
String taxRuleFingerprint(TaxRule rule) {
  String numberKey(double? value) {
    if (value == null) {
      return '';
    }
    return value.toStringAsFixed(6);
  }

  final scope = (rule.representedCompanyId ?? '').trim();
  final status = rule.status.trim().toLowerCase();
  final stType = (rule.stCalculationType ?? 'mva').trim().toLowerCase();
  final ncm = normalizeNcmDigits(rule.ncm);
  final cest = normalizeCestDigits(rule.cest);
  final ufOrigem = rule.ufOrigem.trim().toUpperCase();
  final ufDestino = rule.ufDestino.trim().toUpperCase();
  final fiscalException = (rule.fiscalException ?? '').trim().toLowerCase();
  final grupoFiscalId = (rule.grupoFiscalId ?? '').trim().toLowerCase();
  final taxGroupId = (rule.taxGroupId ?? '').trim().toLowerCase();
  final cstCsosn = (rule.cstCsosn ?? '').trim().toLowerCase();
  final buyerRegime =
      (rule.applicableBuyerTaxRegime ?? '').trim().toLowerCase();
  final stReductionAppliesToIcmsProprio =
      rule.stReductionAppliesToIcmsProprio ? '1' : '0';
  final validFrom = rule.validFrom?.toUtc().toIso8601String() ?? '';
  final validUntil = rule.validUntil?.toUtc().toIso8601String() ?? '';

  return <String>[
    scope,
    status,
    ncm,
    cest,
    ufOrigem,
    ufDestino,
    stType,
    numberKey(rule.stPriceForCalculation),
    numberKey(rule.stBaseReductionPercent),
    numberKey(rule.stBaseAmount),
    numberKey(rule.aliquotaDestino),
    numberKey(rule.aliquotaCredito),
    numberKey(rule.aliquotaDifal),
    numberKey(rule.mvaIva),
    numberKey(rule.aliquotaFcp),
    numberKey(rule.aliquotaFcpSt),
    numberKey(rule.aliquotaFcpDifal),
    buyerRegime,
    stReductionAppliesToIcmsProprio,
    fiscalException,
    grupoFiscalId,
    taxGroupId,
    cstCsosn,
    numberKey(rule.reformaAliquotaIbsEstadual),
    numberKey(rule.reformaAliquotaIbsMunicipal),
    numberKey(rule.reformaPercentualReducaoIbs),
    numberKey(rule.reformaAliquotaReferenciaCbs),
    numberKey(rule.reformaPercentualReducaoCbs),
    numberKey(rule.reformaAliquotaReferenciaIs),
    validFrom,
    validUntil,
  ].join('|');
}
