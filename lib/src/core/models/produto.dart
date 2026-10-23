import '../contracts/tenant_scoped_entity.dart';
import 'domain_types.dart';

class Produto implements TenantScopedEntity {
  const Produto({
    required this.id,
    required this.tenantId,
    this.representedCompanyId,
    required this.codigoInterno,
    required this.descricao,
    required this.origemCadastro,
    required this.status,
    this.fotoUrl,
    this.storagePath,
    this.thumbnailBase64,
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
    this.moeda,
    this.comprimentoMm,
    this.larguraMm,
    this.alturaMm,
    this.valorBruto,
    this.precoMinimo,
    this.percentualComissao,
    this.unidade,
    this.multiploVenda,
    this.quantidadeMinima,
    this.grupoTributarioId,
    this.ncm,
    this.cest,
    this.origemMercadoriaCst,
    this.aliquotaIpiBase,
    this.pesoKg,
    this.erpProductId,
    this.erpSyncId,
    this.syncVersion = 0,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Produto.fromMap(Map<String, Object?> map) {
    return Produto(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      representedCompanyId: map['representedCompanyId'] as String?,
      codigoInterno: map['codigoInterno'] as String? ?? '',
      descricao: map['descricao'] as String? ?? '',
      origemCadastro: ProductSource.fromValue(
        map['origemCadastro'] as String? ?? ProductSource.manual.value,
      ),
      status: ProductStatus.fromValue(
        map['status'] as String? ?? ProductStatus.active.value,
      ),
      fotoUrl: map['fotoUrl'] as String?,
      storagePath: map['storagePath'] as String?,
      thumbnailBase64: map['thumbnailBase64'] as String?,
      descricaoResumida: map['descricaoResumida'] as String?,
      descricaoLonga:
          map['descricaoLonga'] as String? ??
          map['descricaoResumida'] as String?,
      codigoFabricante: map['codigoFabricante'] as String?,
      sku: map['sku'] as String?,
      ean: map['ean'] as String?,
      marca: map['marca'] as String?,
      categoria: map['categoria'] as String?,
      subcategoria: map['subcategoria'] as String?,
      colecao: map['colecao'] as String?,
      bitola: map['bitola'] as String?,
      bitolaUnidade: map['bitolaUnidade'] as String?,
      moeda: map['moeda'] as String?,
      comprimentoMm: _readDouble(map['comprimentoMm']),
      larguraMm: _readDouble(map['larguraMm']),
      alturaMm: _readDouble(map['alturaMm']),
      valorBruto: _readDouble(map['valorBruto']),
      precoMinimo: _readDouble(map['precoMinimo']),
      percentualComissao: _readDouble(map['percentualComissao']),
      unidade: map['unidade'] as String?,
      multiploVenda: _readDouble(map['multiploVenda']),
      quantidadeMinima: _readDouble(map['quantidadeMinima']),
      grupoTributarioId: _readNullableTrimmedString(
        map['grupo_tributario_id'] ?? map['grupoTributarioId'],
      ),
      ncm: map['ncm'] as String?,
      cest: map['cest'] as String?,
      origemMercadoriaCst: _readOrigemMercadoriaCst(
        map['origemMercadoriaCst'] ??
            map['origemMercadoria'] ??
            map['origem_mercadoria'] ??
            map['cstOrigem'] ??
            map['cst_origem'] ??
            map['origemProduto'] ??
            map['origem_produto'] ??
            map['ORIGPROD'],
      ),
      aliquotaIpiBase: _readDouble(map['aliquotaIpiBase']),
      pesoKg: _readDouble(map['pesoKg']),
      erpProductId: map['erpProductId'] as String?,
      erpSyncId: map['erpSyncId'] as String?,
      syncVersion: _readInt(map['syncVersion']) ?? 0,
      deletedAt: _readDateTime(map['deletedAt']),
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  @override
  final String id;
  @override
  final String tenantId;
  final String? representedCompanyId;
  final String codigoInterno;
  final String descricao;
  final ProductSource origemCadastro;
  final ProductStatus status;
  final String? fotoUrl;
  final String? storagePath;
  final String? thumbnailBase64;
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
  final String? moeda;
  final double? comprimentoMm;
  final double? larguraMm;
  final double? alturaMm;
  final double? valorBruto;
  final double? precoMinimo;
  final double? percentualComissao;
  final String? unidade;
  final double? multiploVenda;
  final double? quantidadeMinima;
  final String? grupoTributarioId;
  final String? ncm;
  final String? cest;
  final String? origemMercadoriaCst;
  final double? aliquotaIpiBase;
  final double? pesoKg;
  final String? erpProductId;
  final String? erpSyncId;
  final int syncVersion;
  final DateTime? deletedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Produto copyWith({
    String? id,
    String? tenantId,
    String? representedCompanyId,
    String? codigoInterno,
    String? descricao,
    ProductSource? origemCadastro,
    ProductStatus? status,
    String? fotoUrl,
    String? storagePath,
    String? thumbnailBase64,
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
    String? moeda,
    double? comprimentoMm,
    double? larguraMm,
    double? alturaMm,
    double? valorBruto,
    double? precoMinimo,
    double? percentualComissao,
    String? unidade,
    double? multiploVenda,
    double? quantidadeMinima,
    String? grupoTributarioId,
    String? ncm,
    String? cest,
    String? origemMercadoriaCst,
    double? aliquotaIpiBase,
    double? pesoKg,
    String? erpProductId,
    String? erpSyncId,
    int? syncVersion,
    DateTime? deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Produto(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      representedCompanyId: representedCompanyId ?? this.representedCompanyId,
      codigoInterno: codigoInterno ?? this.codigoInterno,
      descricao: descricao ?? this.descricao,
      origemCadastro: origemCadastro ?? this.origemCadastro,
      status: status ?? this.status,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      storagePath: storagePath ?? this.storagePath,
      thumbnailBase64: thumbnailBase64 ?? this.thumbnailBase64,
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
      moeda: moeda ?? this.moeda,
      comprimentoMm: comprimentoMm ?? this.comprimentoMm,
      larguraMm: larguraMm ?? this.larguraMm,
      alturaMm: alturaMm ?? this.alturaMm,
      valorBruto: valorBruto ?? this.valorBruto,
      precoMinimo: precoMinimo ?? this.precoMinimo,
      percentualComissao: percentualComissao ?? this.percentualComissao,
      unidade: unidade ?? this.unidade,
      multiploVenda: multiploVenda ?? this.multiploVenda,
      quantidadeMinima: quantidadeMinima ?? this.quantidadeMinima,
      grupoTributarioId: grupoTributarioId ?? this.grupoTributarioId,
      ncm: ncm ?? this.ncm,
      cest: cest ?? this.cest,
      origemMercadoriaCst: origemMercadoriaCst ?? this.origemMercadoriaCst,
      aliquotaIpiBase: aliquotaIpiBase ?? this.aliquotaIpiBase,
      pesoKg: pesoKg ?? this.pesoKg,
      erpProductId: erpProductId ?? this.erpProductId,
      erpSyncId: erpSyncId ?? this.erpSyncId,
      syncVersion: syncVersion ?? this.syncVersion,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tenantId': tenantId,
      'representedCompanyId': representedCompanyId,
      'codigoInterno': codigoInterno,
      'descricao': descricao,
      'origemCadastro': origemCadastro.value,
      'status': status.value,
      'fotoUrl': fotoUrl,
      'storagePath': storagePath,
      'thumbnailBase64': thumbnailBase64,
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
      'moeda': moeda,
      'comprimentoMm': comprimentoMm,
      'larguraMm': larguraMm,
      'alturaMm': alturaMm,
      'valorBruto': valorBruto,
      'precoMinimo': precoMinimo,
      'percentualComissao': percentualComissao,
      'unidade': unidade,
      'multiploVenda': multiploVenda,
      'quantidadeMinima': quantidadeMinima,
      'grupo_tributario_id': grupoTributarioId,
      'ncm': ncm,
      'cest': cest,
      'origemMercadoriaCst': origemMercadoriaCst,
      'aliquotaIpiBase': aliquotaIpiBase,
      'pesoKg': pesoKg,
      'erpProductId': erpProductId,
      'erpSyncId': erpSyncId,
      'syncVersion': syncVersion,
      'deletedAt': deletedAt?.toIso8601String(),
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

String? _readOrigemMercadoriaCst(Object? value) {
  final raw = (value ?? '').toString().trim();
  if (raw.isEmpty) {
    return null;
  }

  final numeric = int.tryParse(raw);
  if (numeric == null || numeric < 0 || numeric > 8) {
    return null;
  }

  return numeric.toString();
}

String? _readNullableTrimmedString(Object? value) {
  final normalized = (value ?? '').toString().trim();
  return normalized.isEmpty ? null : normalized;
}
