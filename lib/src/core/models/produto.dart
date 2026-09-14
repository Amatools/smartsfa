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
    this.descricaoLonga,
    this.codigoFabricante,
    this.sku,
    this.ean,
    this.marca,
    this.categoria,
    this.subcategoria,
    this.colecao,
    this.bitola,
    this.bitolaUnidade,
    this.comprimentoMm,
    this.larguraMm,
    this.alturaMm,
    this.valorBruto,
    this.precoMinimo,
    this.percentualComissao,
    this.unidade,
    this.multiploVenda,
    this.quantidadeMinima,
    this.ncm,
    this.cfop,
    this.aliquotaIcms,
    this.aliquotaPis,
    this.aliquotaCofins,
    this.pesoKg,
    this.erpProductId,
    this.erpSyncId,
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
      descricaoLonga: map['descricaoLonga'] as String? ?? map['descricaoResumida'] as String?,
      codigoFabricante: map['codigoFabricante'] as String?,
      sku: map['sku'] as String?,
      ean: map['ean'] as String?,
      marca: map['marca'] as String?,
      categoria: map['categoria'] as String?,
      subcategoria: map['subcategoria'] as String?,
      colecao: map['colecao'] as String?,
      bitola: map['bitola'] as String?,
      bitolaUnidade: map['bitolaUnidade'] as String?,
      comprimentoMm: _readDouble(map['comprimentoMm']),
      larguraMm: _readDouble(map['larguraMm']),
      alturaMm: _readDouble(map['alturaMm']),
      valorBruto: _readDouble(map['valorBruto']),
      precoMinimo: _readDouble(map['precoMinimo']),
      percentualComissao: _readDouble(map['percentualComissao']),
      unidade: map['unidade'] as String?,
      multiploVenda: _readDouble(map['multiploVenda']),
      quantidadeMinima: _readDouble(map['quantidadeMinima']),
      ncm: map['ncm'] as String?,
      cfop: map['cfop'] as String?,
      aliquotaIcms: _readDouble(map['aliquotaIcms']),
      aliquotaPis: _readDouble(map['aliquotaPis']),
      aliquotaCofins: _readDouble(map['aliquotaCofins']),
      pesoKg: _readDouble(map['pesoKg']),
      erpProductId: map['erpProductId'] as String?,
      erpSyncId: map['erpSyncId'] as String?,
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
  final String? descricaoLonga;
  final String? codigoFabricante;
  final String? sku;
  final String? ean;
  final String? marca;
  final String? categoria;
  final String? subcategoria;
  final String? colecao;
  final String? bitola;
  final String? bitolaUnidade;
  final double? comprimentoMm;
  final double? larguraMm;
  final double? alturaMm;
  final double? valorBruto;
  final double? precoMinimo;
  final double? percentualComissao;
  final String? unidade;
  final double? multiploVenda;
  final double? quantidadeMinima;
  final String? ncm;
  final String? cfop;
  final double? aliquotaIcms;
  final double? aliquotaPis;
  final double? aliquotaCofins;
  final double? pesoKg;
  final String? erpProductId;
  final String? erpSyncId;
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
    String? descricaoLonga,
    String? codigoFabricante,
    String? sku,
    String? ean,
    String? marca,
    String? categoria,
    String? subcategoria,
    String? colecao,
    String? bitola,
    String? bitolaUnidade,
    double? comprimentoMm,
    double? larguraMm,
    double? alturaMm,
    double? valorBruto,
    double? precoMinimo,
    double? percentualComissao,
    String? unidade,
    double? multiploVenda,
    double? quantidadeMinima,
    String? ncm,
    String? cfop,
    double? aliquotaIcms,
    double? aliquotaPis,
    double? aliquotaCofins,
    double? pesoKg,
    String? erpProductId,
    String? erpSyncId,
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
      descricaoLonga: descricaoLonga ?? this.descricaoLonga,
      codigoFabricante: codigoFabricante ?? this.codigoFabricante,
      sku: sku ?? this.sku,
      ean: ean ?? this.ean,
      marca: marca ?? this.marca,
      categoria: categoria ?? this.categoria,
      subcategoria: subcategoria ?? this.subcategoria,
      colecao: colecao ?? this.colecao,
      bitola: bitola ?? this.bitola,
      bitolaUnidade: bitolaUnidade ?? this.bitolaUnidade,
      comprimentoMm: comprimentoMm ?? this.comprimentoMm,
      larguraMm: larguraMm ?? this.larguraMm,
      alturaMm: alturaMm ?? this.alturaMm,
      valorBruto: valorBruto ?? this.valorBruto,
      precoMinimo: precoMinimo ?? this.precoMinimo,
      percentualComissao: percentualComissao ?? this.percentualComissao,
      unidade: unidade ?? this.unidade,
      multiploVenda: multiploVenda ?? this.multiploVenda,
      quantidadeMinima: quantidadeMinima ?? this.quantidadeMinima,
      ncm: ncm ?? this.ncm,
      cfop: cfop ?? this.cfop,
      aliquotaIcms: aliquotaIcms ?? this.aliquotaIcms,
      aliquotaPis: aliquotaPis ?? this.aliquotaPis,
      aliquotaCofins: aliquotaCofins ?? this.aliquotaCofins,
      pesoKg: pesoKg ?? this.pesoKg,
      erpProductId: erpProductId ?? this.erpProductId,
      erpSyncId: erpSyncId ?? this.erpSyncId,
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
      'descricaoLonga': descricaoLonga,
      'codigoFabricante': codigoFabricante,
      'sku': sku,
      'ean': ean,
      'marca': marca,
      'categoria': categoria,
      'subcategoria': subcategoria,
      'colecao': colecao,
      'bitola': bitola,
      'bitolaUnidade': bitolaUnidade,
      'comprimentoMm': comprimentoMm,
      'larguraMm': larguraMm,
      'alturaMm': alturaMm,
      'valorBruto': valorBruto,
      'precoMinimo': precoMinimo,
      'percentualComissao': percentualComissao,
      'unidade': unidade,
      'multiploVenda': multiploVenda,
      'quantidadeMinima': quantidadeMinima,
      'ncm': ncm,
      'cfop': cfop,
      'aliquotaIcms': aliquotaIcms,
      'aliquotaPis': aliquotaPis,
      'aliquotaCofins': aliquotaCofins,
      'pesoKg': pesoKg,
      'erpProductId': erpProductId,
      'erpSyncId': erpSyncId,
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