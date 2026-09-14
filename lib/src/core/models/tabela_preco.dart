import '../contracts/tenant_scoped_entity.dart';

class TabelaPreco implements TenantScopedEntity {
  const TabelaPreco({
    required this.id,
    required this.tenantId,
    required this.nome,
    required this.scopeType,
    required this.scopeLabel,
    required this.scopeIndex,
    required this.origem,
    required this.status,
    this.linkedEntityId,
    this.fileName,
    this.rowCount,
    this.validFrom,
    this.validUntil,
    this.createdAt,
    this.updatedAt,
  });

  factory TabelaPreco.fromMap(Map<String, Object?> map) {
    return TabelaPreco(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      nome: map['nome'] as String? ?? '',
      scopeType: map['scopeType'] as String? ?? 'general',
      scopeLabel: map['scopeLabel'] as String? ?? '',
      scopeIndex: _readStringList(map['scopeIndex']),
      origem: map['origem'] as String? ?? 'manual',
      status: map['status'] as String? ?? 'ativo',
      linkedEntityId: map['linkedEntityId'] as String?,
      fileName: map['fileName'] as String?,
      rowCount: _readInt(map['rowCount']),
      validFrom: _readDateTime(map['validFrom']),
      validUntil: _readDateTime(map['validUntil']),
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  @override
  final String id;
  @override
  final String tenantId;
  final String nome;
  final String scopeType;
  final String scopeLabel;
  final List<String> scopeIndex;
  final String origem;
  final String status;
  final String? linkedEntityId;
  final String? fileName;
  final int? rowCount;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TabelaPreco copyWith({
    String? id,
    String? tenantId,
    String? nome,
    String? scopeType,
    String? scopeLabel,
    List<String>? scopeIndex,
    String? origem,
    String? status,
    String? linkedEntityId,
    String? fileName,
    int? rowCount,
    DateTime? validFrom,
    DateTime? validUntil,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TabelaPreco(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      nome: nome ?? this.nome,
      scopeType: scopeType ?? this.scopeType,
      scopeLabel: scopeLabel ?? this.scopeLabel,
      scopeIndex: scopeIndex ?? this.scopeIndex,
      origem: origem ?? this.origem,
      status: status ?? this.status,
      linkedEntityId: linkedEntityId ?? this.linkedEntityId,
      fileName: fileName ?? this.fileName,
      rowCount: rowCount ?? this.rowCount,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tenantId': tenantId,
      'nome': nome,
      'scopeType': scopeType,
      'scopeLabel': scopeLabel,
      'scopeIndex': scopeIndex,
      'origem': origem,
      'status': status,
      'linkedEntityId': linkedEntityId,
      'fileName': fileName,
      'rowCount': rowCount,
      'validFrom': validFrom?.toIso8601String(),
      'validUntil': validUntil?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

List<String> _readStringList(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
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