import 'domain_types.dart';
import 'tenant_policy.dart';

class Tenant {
  const Tenant({
    required this.tenantId,
    required this.slug,
    required this.nomeFantasia,
    required this.ativo,
    required this.operationMode,
    required this.erpProvider,
    required this.policy,
    this.razaoSocial,
    this.createdAt,
    this.updatedAt,
  });

  factory Tenant.fromMap(Map<String, Object?> map) {
    return Tenant(
      tenantId: map['tenantId'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      nomeFantasia: map['nomeFantasia'] as String? ?? '',
      ativo: map['ativo'] as bool? ?? false,
      operationMode: TenantOperationMode.fromValue(
        map['operationMode'] as String? ?? TenantOperationMode.manual.value,
      ),
      erpProvider: ErpProviderKind.fromValue(
        map['erpProvider'] as String? ?? ErpProviderKind.none.value,
      ),
      policy: map['policy'] is Map<String, Object?>
          ? TenantPolicy.fromMap(map['policy'] as Map<String, Object?>)
          : TenantPolicy.defaultSaas(),
      razaoSocial: map['razaoSocial'] as String?,
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  final String tenantId;
  final String slug;
  final String nomeFantasia;
  final bool ativo;
  final TenantOperationMode operationMode;
  final ErpProviderKind erpProvider;
  final TenantPolicy policy;
  final String? razaoSocial;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Tenant copyWith({
    String? tenantId,
    String? slug,
    String? nomeFantasia,
    bool? ativo,
    TenantOperationMode? operationMode,
    ErpProviderKind? erpProvider,
    TenantPolicy? policy,
    String? razaoSocial,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Tenant(
      tenantId: tenantId ?? this.tenantId,
      slug: slug ?? this.slug,
      nomeFantasia: nomeFantasia ?? this.nomeFantasia,
      ativo: ativo ?? this.ativo,
      operationMode: operationMode ?? this.operationMode,
      erpProvider: erpProvider ?? this.erpProvider,
      policy: policy ?? this.policy,
      razaoSocial: razaoSocial ?? this.razaoSocial,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'tenantId': tenantId,
      'slug': slug,
      'nomeFantasia': nomeFantasia,
      'ativo': ativo,
      'operationMode': operationMode.value,
      'erpProvider': erpProvider.value,
      'policy': policy.toMap(),
      'razaoSocial': razaoSocial,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
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
