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
    this.fotoUrl,
    this.descricaoResumida,
    this.valorBruto,
    this.unidade,
    this.ncm,
    this.cfop,
    this.aliquotaIcms,
    this.aliquotaPis,
    this.aliquotaCofins,
    this.pesoKg,
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
      fotoUrl: map['fotoUrl'] as String?,
      descricaoResumida: map['descricaoResumida'] as String?,
      valorBruto: _readDouble(map['valorBruto']),
      unidade: map['unidade'] as String?,
      ncm: map['ncm'] as String?,
      cfop: map['cfop'] as String?,
      aliquotaIcms: _readDouble(map['aliquotaIcms']),
      aliquotaPis: _readDouble(map['aliquotaPis']),
      aliquotaCofins: _readDouble(map['aliquotaCofins']),
      pesoKg: _readDouble(map['pesoKg']),
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
  final String? fotoUrl;
  final String? descricaoResumida;
  final double? valorBruto;
  final String? unidade;
  final String? ncm;
  final String? cfop;
  final double? aliquotaIcms;
  final double? aliquotaPis;
  final double? aliquotaCofins;
  final double? pesoKg;
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
    String? fotoUrl,
    String? descricaoResumida,
    double? valorBruto,
    String? unidade,
    String? ncm,
    String? cfop,
    double? aliquotaIcms,
    double? aliquotaPis,
    double? aliquotaCofins,
    double? pesoKg,
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
      fotoUrl: fotoUrl ?? this.fotoUrl,
      descricaoResumida: descricaoResumida ?? this.descricaoResumida,
      valorBruto: valorBruto ?? this.valorBruto,
      unidade: unidade ?? this.unidade,
      ncm: ncm ?? this.ncm,
      cfop: cfop ?? this.cfop,
      aliquotaIcms: aliquotaIcms ?? this.aliquotaIcms,
      aliquotaPis: aliquotaPis ?? this.aliquotaPis,
      aliquotaCofins: aliquotaCofins ?? this.aliquotaCofins,
      pesoKg: pesoKg ?? this.pesoKg,
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
      'fotoUrl': fotoUrl,
      'descricaoResumida': descricaoResumida,
      'valorBruto': valorBruto,
      'unidade': unidade,
      'ncm': ncm,
      'cfop': cfop,
      'aliquotaIcms': aliquotaIcms,
      'aliquotaPis': aliquotaPis,
      'aliquotaCofins': aliquotaCofins,
      'pesoKg': pesoKg,
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

double? _readDouble(Object? value) {
  if (value is double) {
    return value;
  }

  if (value is int) {
    return value.toDouble();
  }

  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.'));
  }

  return null;
}