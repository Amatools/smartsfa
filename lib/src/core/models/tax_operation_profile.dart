import '../contracts/tenant_scoped_entity.dart';

/// Perfil de operacao fiscal (um dos 10 tipos nativos), com os switches
/// de comportamento usados pelo motor de calculo.
///
/// Mantem compatibilidade com o schema ja usado pela colecao Firestore
/// `tax_operation_profiles` (ver
/// `lib/src/features/portal/presentation/pages/web_portal_taxation_section.dart`).
class TaxOperationProfile implements TenantScopedEntity {
  const TaxOperationProfile({
    required this.id,
    required this.tenantId,
    required this.profileKey,
    required this.status,
    required this.priority,
    required this.calculateIcmsSt,
    required this.calculateDifal,
    required this.includeIpiInIcmsBase,
    required this.addIpiToTotal,
    required this.reduceIcmsForZfm,
    this.representedCompanyId,
    this.name,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  factory TaxOperationProfile.fromMap(Map<String, Object?> map) {
    return TaxOperationProfile(
      id: (map['id'] as String?)?.trim() ?? '',
      tenantId: (map['tenantId'] as String?)?.trim() ?? '',
      representedCompanyId: _readTrimmedStringOrNull(
        map['representedCompanyId'],
      ),
      profileKey: (map['profileKey'] as String?)?.trim() ?? '',
      status: (map['status'] as String? ?? 'active').trim().toLowerCase(),
      priority: _readInt(map['priority']) ?? 0,
      calculateIcmsSt: _readBool(map['calculateIcmsSt']),
      calculateDifal: _readBool(map['calculateDifal']),
      includeIpiInIcmsBase: _readBool(map['includeIpiInIcmsBase']),
      addIpiToTotal: _readBool(map['addIpiToTotal']),
      reduceIcmsForZfm: _readBool(map['reduceIcmsForZfm']),
      name: _readTrimmedStringOrNull(map['name']),
      description: _readTrimmedStringOrNull(map['description']),
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  @override
  final String id;
  @override
  final String tenantId;
  final String? representedCompanyId;
  final String profileKey;
  final String status;
  final int priority;
  final bool calculateIcmsSt;
  final bool calculateDifal;
  final bool includeIpiInIcmsBase;
  final bool addIpiToTotal;
  final bool reduceIcmsForZfm;
  final String? name;
  final String? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'tenantId': tenantId,
      'representedCompanyId': representedCompanyId,
      'profileKey': profileKey,
      'status': status,
      'priority': priority,
      'calculateIcmsSt': calculateIcmsSt,
      'calculateDifal': calculateDifal,
      'includeIpiInIcmsBase': includeIpiInIcmsBase,
      'addIpiToTotal': addIpiToTotal,
      'reduceIcmsForZfm': reduceIcmsForZfm,
      'name': name,
      'description': description,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

bool _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.trim().toLowerCase() == 'true';
  }
  return false;
}

String? _readTrimmedStringOrNull(Object? value) {
  final normalized = (value ?? '').toString().trim();
  if (normalized.isEmpty) {
    return null;
  }
  return normalized;
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}
