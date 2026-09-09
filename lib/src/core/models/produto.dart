import '../contracts/tenant_scoped_entity.dart';
import 'domain_types.dart';

class Produto implements TenantScopedEntity {
  const Produto({
    required this.id,
    required this.tenantId,
    required this.codigoInterno,
    required this.descricao,
    required this.origemCadastro,
    required this.status,
    this.tabelaPrecoVersao,
    this.estoqueVersao,
    this.createdAt,
    this.updatedAt,
  });

  factory Produto.fromMap(Map<String, Object?> map) {
    return Produto(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      codigoInterno: map['codigoInterno'] as String? ?? '',
      descricao: map['descricao'] as String? ?? '',
      origemCadastro: ProductSource.fromValue(
        map['origemCadastro'] as String? ?? ProductSource.manual.value,
      ),
      status: ProductStatus.fromValue(
        map['status'] as String? ?? ProductStatus.active.value,
      ),
      tabelaPrecoVersao: map['tabelaPrecoVersao'] as String?,
      estoqueVersao: map['estoqueVersao'] as String?,
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  @override
  final String id;
  @override
  final String tenantId;
  final String codigoInterno;
  final String descricao;
  final ProductSource origemCadastro;
  final ProductStatus status;
  final String? tabelaPrecoVersao;
  final String? estoqueVersao;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Produto copyWith({
    String? id,
    String? tenantId,
    String? codigoInterno,
    String? descricao,
    ProductSource? origemCadastro,
    ProductStatus? status,
    String? tabelaPrecoVersao,
    String? estoqueVersao,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Produto(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      codigoInterno: codigoInterno ?? this.codigoInterno,
      descricao: descricao ?? this.descricao,
      origemCadastro: origemCadastro ?? this.origemCadastro,
      status: status ?? this.status,
      tabelaPrecoVersao: tabelaPrecoVersao ?? this.tabelaPrecoVersao,
      estoqueVersao: estoqueVersao ?? this.estoqueVersao,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tenantId': tenantId,
      'codigoInterno': codigoInterno,
      'descricao': descricao,
      'origemCadastro': origemCadastro.value,
      'status': status.value,
      'tabelaPrecoVersao': tabelaPrecoVersao,
      'estoqueVersao': estoqueVersao,
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