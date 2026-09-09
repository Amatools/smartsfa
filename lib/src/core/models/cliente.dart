import '../contracts/tenant_scoped_entity.dart';
import 'domain_types.dart';

class Cliente implements TenantScopedEntity {
  const Cliente({
    required this.id,
    required this.tenantId,
    required this.nome,
    required this.documento,
    required this.origemCadastro,
    required this.status,
    this.ownerId,
    this.gerenteId,
    this.representanteId,
    this.vendedorId,
    this.createdAt,
    this.updatedAt,
  });

  factory Cliente.fromMap(Map<String, Object?> map) {
    return Cliente(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      nome: map['nome'] as String? ?? '',
      documento: map['documento'] as String? ?? '',
      origemCadastro: CustomerOrigin.fromValue(
        map['origemCadastro'] as String? ?? CustomerOrigin.manual.value,
      ),
      status: CustomerStatus.fromValue(
        map['status'] as String? ?? CustomerStatus.approved.value,
      ),
      ownerId: map['ownerId'] as String?,
      gerenteId: map['gerenteId'] as String?,
      representanteId: map['representanteId'] as String?,
      vendedorId: map['vendedorId'] as String?,
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  final String id;
  @override
  final String tenantId;
  final String nome;
  final String documento;
  final CustomerOrigin origemCadastro;
  final CustomerStatus status;
  final String? ownerId;
  final String? gerenteId;
  final String? representanteId;
  final String? vendedorId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Cliente copyWith({
    String? id,
    String? tenantId,
    String? nome,
    String? documento,
    CustomerOrigin? origemCadastro,
    CustomerStatus? status,
    String? ownerId,
    String? gerenteId,
    String? representanteId,
    String? vendedorId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Cliente(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      nome: nome ?? this.nome,
      documento: documento ?? this.documento,
      origemCadastro: origemCadastro ?? this.origemCadastro,
      status: status ?? this.status,
      ownerId: ownerId ?? this.ownerId,
      gerenteId: gerenteId ?? this.gerenteId,
      representanteId: representanteId ?? this.representanteId,
      vendedorId: vendedorId ?? this.vendedorId,
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
      'origemCadastro': origemCadastro.value,
      'status': status.value,
      'ownerId': ownerId,
      'gerenteId': gerenteId,
      'representanteId': representanteId,
      'vendedorId': vendedorId,
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