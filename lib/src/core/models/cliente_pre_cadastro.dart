import '../contracts/tenant_scoped_entity.dart';
import 'domain_types.dart';

class ClientePreCadastro implements TenantScopedEntity {
  const ClientePreCadastro({
    required this.id,
    required this.tenantId,
    required this.nome,
    required this.documento,
    required this.status,
    required this.requestedByUid,
    this.approvedByUid,
    this.mergedClienteId,
    this.createdAt,
    this.updatedAt,
  });

  factory ClientePreCadastro.fromMap(Map<String, Object?> map) {
    return ClientePreCadastro(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      nome: map['nome'] as String? ?? '',
      documento: map['documento'] as String? ?? '',
      status: PreRegistrationStatus.fromValue(
        map['status'] as String? ?? PreRegistrationStatus.draft.value,
      ),
      requestedByUid: map['requestedByUid'] as String? ?? '',
      approvedByUid: map['approvedByUid'] as String?,
      mergedClienteId: map['mergedClienteId'] as String?,
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  @override
  final String id;
  @override
  final String tenantId;
  final String nome;
  final String documento;
  final PreRegistrationStatus status;
  final String requestedByUid;
  final String? approvedByUid;
  final String? mergedClienteId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ClientePreCadastro copyWith({
    String? id,
    String? tenantId,
    String? nome,
    String? documento,
    PreRegistrationStatus? status,
    String? requestedByUid,
    String? approvedByUid,
    String? mergedClienteId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ClientePreCadastro(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      nome: nome ?? this.nome,
      documento: documento ?? this.documento,
      status: status ?? this.status,
      requestedByUid: requestedByUid ?? this.requestedByUid,
      approvedByUid: approvedByUid ?? this.approvedByUid,
      mergedClienteId: mergedClienteId ?? this.mergedClienteId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tenantId': tenantId,
      'nome': nome,
      'documento': documento,
      'status': status.value,
      'requestedByUid': requestedByUid,
      'approvedByUid': approvedByUid,
      'mergedClienteId': mergedClienteId,
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