import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/services/enterprise_represented_scope.dart';

part 'workspace_profile_service_payment_conditions.dart';
part 'workspace_profile_service_commercial_adjustments.dart';
part 'workspace_profile_service_order_discounts.dart';
part 'workspace_profile_service_product_taxonomy.dart';
part 'workspace_profile_service_erp_settings.dart';
part 'workspace_profile_service_represented_companies.dart';

class PaymentConditionRule {
  const PaymentConditionRule({
    required this.description,
    required this.minimumValue,
  });

  final String description;
  final double minimumValue;

  Map<String, Object> toMap() {
    return <String, Object>{
      'description': description,
      'minimumValue': minimumValue,
    };
  }
}

class CommercialAdjustmentRule {
  const CommercialAdjustmentRule({
    required this.name,
    required this.adjustmentType,
    required this.valueType,
    required this.value,
    required this.scope,
    required this.scopeTarget,
    this.scopeTargets = const <String>[],
  });

  final String name;
  final String adjustmentType;
  final String valueType;
  final double value;
  final String scope;
  final String scopeTarget;
  final List<String> scopeTargets;

  Map<String, Object> toMap() {
    final normalizedScopeTargets = <String>[];
    final seen = <String>{};
    for (final value in scopeTargets) {
      final clean = value.trim();
      if (clean.isEmpty) {
        continue;
      }
      final key = clean.toLowerCase();
      if (!seen.add(key)) {
        continue;
      }
      normalizedScopeTargets.add(clean);
    }
    final normalizedScopeTarget = scopeTarget.trim();
    final effectiveScopeTarget = normalizedScopeTarget.isNotEmpty
        ? normalizedScopeTarget
        : normalizedScopeTargets.join(' | ');

    final map = <String, Object>{
      'name': name,
      'adjustmentType': adjustmentType,
      'valueType': valueType,
      'value': value,
      'scope': scope,
      'scopeTarget': effectiveScopeTarget,
    };

    if (normalizedScopeTargets.isNotEmpty) {
      map['scopeTargets'] = normalizedScopeTargets;
    }

    return map;
  }
}

class CommercialAdjustmentTargetCatalog {
  const CommercialAdjustmentTargetCatalog({
    this.brands = const <String>[],
    this.products = const <String>[],
  });

  final List<String> brands;
  final List<String> products;
}

enum OrderDiscountApplyMode {
  beforeTax('before_tax'),
  afterTax('after_tax');

  const OrderDiscountApplyMode(this.storageValue);

  final String storageValue;

  static OrderDiscountApplyMode fromStorage(Object? raw) {
    final normalized = (raw ?? '').toString().trim().toLowerCase();
    if (normalized == beforeTax.storageValue ||
        normalized == 'before' ||
        normalized == 'antes' ||
        normalized == 'pre_tax') {
      return beforeTax;
    }
    if (normalized == afterTax.storageValue ||
        normalized == 'after' ||
        normalized == 'depois' ||
        normalized == 'post_tax') {
      return afterTax;
    }
    return afterTax;
  }
}

class OrderDiscountFieldRule {
  const OrderDiscountFieldRule({
    required this.label,
    required this.minPercent,
    required this.maxPercent,
    this.applyMode = OrderDiscountApplyMode.afterTax,
  });

  final String label;
  final double minPercent;
  final double maxPercent;
  final OrderDiscountApplyMode applyMode;

  Map<String, Object> toMap() {
    return <String, Object>{
      'label': label,
      'minPercent': minPercent,
      'maxPercent': maxPercent,
      'applyMode': applyMode.storageValue,
    };
  }
}

class OrderDiscountPolicy {
  const OrderDiscountPolicy({this.fields = const <OrderDiscountFieldRule>[]});

  final List<OrderDiscountFieldRule> fields;
}

class ProductCategoryTaxonomyItem {
  const ProductCategoryTaxonomyItem({
    required this.name,
    required this.subcategories,
  });

  final String name;
  final List<String> subcategories;

  Map<String, Object> toMap() {
    return <String, Object>{'name': name, 'subcategories': subcategories};
  }
}

String _normalize(Object? value) {
  return value?.toString().trim() ?? '';
}

String _digitsOnly(Object? value) {
  return _normalize(value).replaceAll(RegExp(r'\D'), '');
}

const Set<String> _validTaxRegimes = <String>{
  'simples_nacional',
  'lucro_presumido',
  'lucro_real',
};

String _normalizeTaxRegime(Object? value) {
  final normalized = _normalize(value).toLowerCase();
  if (_validTaxRegimes.contains(normalized)) {
    return normalized;
  }
  throw StateError('Regime tributário inválido.');
}

bool _isConnectivityLimitedError(FirebaseException error) {
  final code = error.code.trim().toLowerCase();
  return code == 'unavailable' ||
      code == 'network-request-failed' ||
      code == 'deadline-exceeded';
}

bool _isValidEmailAddress(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return true;
  }

  return RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
      .hasMatch(normalized);
}

bool _isValidCnpjDigits(String value) {
  if (value.length != 14) {
    return false;
  }

  if (RegExp(r'^(\d)\1{13}$').hasMatch(value)) {
    return false;
  }

  int calcDigit(String source, List<int> weights) {
    var sum = 0;
    for (var i = 0; i < weights.length; i++) {
      sum += int.parse(source[i]) * weights[i];
    }
    final remainder = sum % 11;
    return remainder < 2 ? 0 : 11 - remainder;
  }

  final firstDigit = calcDigit(value.substring(0, 12), <int>[
    5,
    4,
    3,
    2,
    9,
    8,
    7,
    6,
    5,
    4,
    3,
    2,
  ]);
  final secondDigit = calcDigit(
    value.substring(0, 12) + firstDigit.toString(),
    <int>[6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
  );

  return value.endsWith('$firstDigit$secondDigit');
}

String _formatCnpj(String digits) {
  if (digits.isEmpty) {
    return '';
  }
  final safe = digits.length > 14 ? digits.substring(0, 14) : digits;
  return '${safe.substring(0, 2)}.${safe.substring(2, 5)}.${safe.substring(5, 8)}/${safe.substring(8, 12)}-${safe.substring(12, 14)}';
}

String _formatCep(String digits) {
  if (digits.isEmpty) {
    return '';
  }
  final safe = digits.length > 8 ? digits.substring(0, 8) : digits;
  if (safe.length < 8) {
    return safe;
  }
  return '${safe.substring(0, 5)}-${safe.substring(5, 8)}';
}

String _formatPhone(String digits) {
  if (digits.isEmpty) {
    return '';
  }
  final safe = digits.length > 11 ? digits.substring(0, 11) : digits;
  if (safe.length == 10) {
    return '(${safe.substring(0, 2)}) ${safe.substring(2, 6)}-${safe.substring(6, 10)}';
  }
  if (safe.length == 11) {
    return '(${safe.substring(0, 2)}) ${safe.substring(2, 7)}-${safe.substring(7, 11)}';
  }
  return safe;
}

const Set<String> _validBrazilStates = <String>{
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
};

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }

  if (value is String) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 0;
    }

    final withDotDecimal = normalized.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(withDotDecimal) ??
        double.tryParse(normalized.replaceAll(',', '.')) ??
        0;
  }

  return 0;
}

List<String> _readScopeTargets({
  required Object? raw,
  required String fallbackScopeTarget,
}) {
  if (raw is List) {
    return _normalizeScopeTargets(raw.map((value) => value?.toString() ?? ''));
  }
  return _splitScopeTargets(fallbackScopeTarget);
}

List<String> _splitScopeTargets(String raw) {
  return _normalizeScopeTargets(raw.split(RegExp(r'[,;|\n]+')));
}

bool _productBelongsToRepresentedScope({
  required Map<String, dynamic> data,
  required String? representedCompanyId,
}) {
  final selectedScope = _normalizeScopeValue(representedCompanyId);
  if (selectedScope.isEmpty) {
    return true;
  }

  final mappedScope = _normalizeScopeValue(
    data['representedCompanyId'] ?? data['representadaId'] ?? data['companyId'],
  );

  if (mappedScope.isEmpty) {
    return true;
  }

  return mappedScope == selectedScope;
}

String _normalizeScopeValue(Object? value) {
  return value?.toString().trim().toLowerCase() ?? '';
}

String _resolveProductTargetLabel({
  required Map<String, dynamic> data,
  required String fallbackId,
}) {
  final description = (data['descricao'] ?? data['nome'] ?? '')
      .toString()
      .trim();
  final code = (data['codigoInterno'] ?? data['codigo'] ?? '')
      .toString()
      .trim();

  if (description.isNotEmpty && code.isNotEmpty) {
    return '$code - $description';
  }
  if (description.isNotEmpty) {
    return description;
  }
  if (code.isNotEmpty) {
    return code;
  }

  return fallbackId.trim();
}

List<String> _normalizeScopeTargets(Iterable<String> values) {
  final normalized = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final clean = value.trim();
    if (clean.isEmpty) {
      continue;
    }
    final key = clean.toLowerCase();
    if (!seen.add(key)) {
      continue;
    }
    normalized.add(clean);
  }
  return normalized;
}

List<String> _normalizePriceTableCodes(Iterable<String> values) {
  final normalized = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final clean = value.trim();
    if (clean.isEmpty) {
      continue;
    }
    if (!RegExp(r'^\d+$').hasMatch(clean)) {
      continue;
    }
    if (!seen.add(clean)) {
      continue;
    }
    normalized.add(clean);
  }
  return normalized;
}

String _normalizeTopCode(String value) {
  final clean = value.trim();
  if (!RegExp(r'^\d+$').hasMatch(clean)) {
    return '';
  }
  return clean;
}

String _scopeKey(String? representedCompanyId) {
  final normalized = (representedCompanyId ?? '').trim();
  if (normalized.isEmpty) {
    return 'tenant_default';
  }
  return normalized.replaceAll('.', '_');
}

/// Contas `brand_owner_workspace` (enterprise) usam um id sintetico de UI
/// (`enterprise_default_<tenantId>`, ver `app_shell.dart`/
/// `web_portal_shell_state_section.dart`) que NUNCA vira um documento ou
/// escopo real cadastrado - nao ha "representada" de verdade para essas
/// contas, so a propria empresa. Tratar esse id sintetico como "sem
/// representada" antes de calcular `_scopeKey`/`_normalizeDefaultPricingScopeKey`
/// evita gravar/ler configuracoes escopadas (acrescimos/descontos comerciais,
/// descontos de pedido, taxonomia de produtos) numa chave que nunca
/// corresponde ao escopo `tenant_default` historicamente usado por essas
/// contas. Mesmo padrao ja aplicado em `_tenantScopedRepresentedCompanyId`
/// (`workspace_profile_service_payment_conditions.dart`) e em
/// `DefaultPriceTableGuard.effectiveRepresentedCompanyId`.
String? _effectiveRepresentedCompanyId(
  String tenantId,
  String? representedCompanyId,
) {
  return EnterpriseRepresentedScope.effectiveRepresentedCompanyId(
    tenantId: tenantId,
    representedCompanyId: representedCompanyId,
  );
}

String _normalizeDefaultPricingScopeKey(String? representedCompanyId) {
  final normalized = (representedCompanyId ?? '').trim();
  if (normalized.isEmpty) {
    return 'tenant_default';
  }
  return normalized.replaceAll('.', '_').replaceAll('/', '_');
}

String _representedCompanyDocId(String tenantId, String representedCompanyId) {
  return '${tenantId}_$representedCompanyId';
}

const String _defaultPriceRegionId = 'default';

class WorkspaceProfileService
    with
        _WorkspaceProfilePaymentConditionsMixin,
        _WorkspaceProfileCommercialAdjustmentsMixin,
        _WorkspaceProfileOrderDiscountsMixin,
        _WorkspaceProfileProductTaxonomyMixin,
        _WorkspaceProfileErpSettingsMixin,
        _WorkspaceProfileRepresentedCompaniesMixin {
  WorkspaceProfileService(this._firestore);

  @override
  final FirebaseFirestore _firestore;

  @override
  CollectionReference<Map<String, dynamic>>
  get _representedCompaniesCollection =>
      _firestore.collection('tenant_represented_companies');

  @override
  Stream<Map<String, dynamic>?> watchWorkspace(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(null);
    }

    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .snapshots()
        .map((doc) => doc.data());
  }

  Stream<List<String>> watchTextRuleList({
    required String tenantId,
    required String fieldName,
  }) {
    final normalizedTenantId = tenantId.trim();
    final normalizedFieldName = fieldName.trim();
    if (normalizedTenantId.isEmpty || normalizedFieldName.isEmpty) {
      return Stream.value(const <String>[]);
    }

    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .snapshots()
        .map((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          final raw = data[normalizedFieldName];
          if (raw is! List) {
            return const <String>[];
          }

          final result = <String>[];
          for (final item in raw) {
            final value = item?.toString().trim() ?? '';
            if (value.isNotEmpty) {
              result.add(value);
            }
          }
          return result;
        });
  }

  Future<void> updateTextRuleList({
    required String tenantId,
    required String fieldName,
    required List<String> values,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedFieldName = fieldName.trim();
    if (normalizedTenantId.isEmpty || normalizedFieldName.isEmpty) {
      throw StateError('Dados invalidos para salvar regras textuais.');
    }

    final normalizedValues = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      normalizedFieldName: normalizedValues,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateWorkspaceProfile({
    required String tenantId,
    required String workspaceType,
    required Map<String, Object?> values,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedWorkspaceType = workspaceType.trim();
    if (normalizedTenantId.isEmpty || normalizedWorkspaceType.isEmpty) {
      throw StateError('Workspace invalido para atualizacao.');
    }

    final payload = <String, Object?>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!values.containsKey('taxRegime')) {
      throw StateError('Regime tributário é obrigatório.');
    }

    void writeIfPresent(String key, Object? value) {
      if (value == null) {
        return;
      }
      payload[key] = value;
    }

    writeIfPresent('nomeFantasia', _normalize(values['nomeFantasia']));
    writeIfPresent(
      'contatoResponsavel',
      _normalize(values['contatoResponsavel']),
    );
    writeIfPresent(
      'telefoneComercial',
      _normalize(values['telefoneComercial']),
    );
    writeIfPresent('emailComercial', _normalize(values['emailComercial']));
    writeIfPresent('website', _normalize(values['website']));
    writeIfPresent('segmento', _normalize(values['segmento']));
    writeIfPresent('regiaoAtuacao', _normalize(values['regiaoAtuacao']));
    writeIfPresent(
      'marcasRepresentadas',
      _normalize(values['marcasRepresentadas']),
    );
    writeIfPresent('logradouro', _normalize(values['logradouro']));
    writeIfPresent('numero', _normalize(values['numero']));
    writeIfPresent('complemento', _normalize(values['complemento']));
    writeIfPresent('bairro', _normalize(values['bairro']));
    writeIfPresent('cep', _normalize(values['cep']));
    writeIfPresent('cidade', _normalize(values['cidade']));
    writeIfPresent('uf', _normalize(values['uf']));
    writeIfPresent('taxRegime', _normalizeTaxRegime(values['taxRegime']));

    if (normalizedWorkspaceType == 'seller_solo_workspace') {
      payload.remove('regiaoAtuacao');
      payload.remove('marcasRepresentadas');
    }

    await _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .set(payload, SetOptions(merge: true));
  }
}
