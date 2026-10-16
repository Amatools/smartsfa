import '../contracts/tenant_scoped_entity.dart';
import 'cliente_reference.dart';
import 'domain_types.dart';

class Pedido implements TenantScopedEntity {
  const Pedido({
    required this.id,
    required this.tenantId,
    required this.origemPedido,
    required this.statusFila,
    this.clienteReferencia,
    this.ownerId,
    this.gerenteId,
    this.representanteId,
    this.vendedorId,
    this.representedCompanyId,
    this.originCompanyUnitId,
    this.originCompanyUnitLabel,
    this.originCompanyUf,
    this.itens = const [],
    this.totalItens = 0,
    this.totalBruto = 0,
    this.createdAt,
    this.updatedAt,
    this.syncVersion,
    this.deletedAt,
  });

  factory Pedido.fromMap(Map<String, Object?> map) {
    return Pedido(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      origemPedido: OrderOrigin.fromValue(
        map['origemPedido'] as String? ?? OrderOrigin.manual.value,
      ),
      statusFila: OrderStatus.fromValue(
        map['statusFila'] as String? ?? OrderStatus.draft.value,
      ),
      clienteReferencia: map['clienteReferencia'] is Map<String, Object?>
          ? ClienteReference.fromMap(
              map['clienteReferencia'] as Map<String, Object?>,
            )
          : null,
      ownerId: map['ownerId'] as String?,
      gerenteId: map['gerenteId'] as String?,
      representanteId: map['representanteId'] as String?,
      vendedorId: map['vendedorId'] as String?,
      representedCompanyId: map['representedCompanyId'] as String?,
      originCompanyUnitId: map['originCompanyUnitId'] as String?,
      originCompanyUnitLabel: map['originCompanyUnitLabel'] as String?,
      originCompanyUf: map['originCompanyUf'] as String?,
      itens: _readItems(map['itens']),
      totalItens: _readDouble(map['totalItens']) ?? 0,
      totalBruto: _readDouble(map['totalBruto']) ?? 0,
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
      syncVersion: _readInt(map['syncVersion']),
      deletedAt: _readDateTime(map['deletedAt']),
    );
  }

  @override
  final String id;
  @override
  final String tenantId;
  final OrderOrigin origemPedido;
  final OrderStatus statusFila;
  final ClienteReference? clienteReferencia;
  final String? ownerId;
  final String? gerenteId;
  final String? representanteId;
  final String? vendedorId;
  final String? representedCompanyId;
  final String? originCompanyUnitId;
  final String? originCompanyUnitLabel;
  final String? originCompanyUf;
  final List<PedidoItem> itens;
  final double totalItens;
  final double totalBruto;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? syncVersion;
  final DateTime? deletedAt;

  Pedido copyWith({
    String? id,
    String? tenantId,
    OrderOrigin? origemPedido,
    OrderStatus? statusFila,
    ClienteReference? clienteReferencia,
    bool clearClienteReferencia = false,
    String? ownerId,
    String? gerenteId,
    String? representanteId,
    String? vendedorId,
    String? representedCompanyId,
    String? originCompanyUnitId,
    String? originCompanyUnitLabel,
    String? originCompanyUf,
    List<PedidoItem>? itens,
    double? totalItens,
    double? totalBruto,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? syncVersion,
    DateTime? deletedAt,
  }) {
    return Pedido(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      origemPedido: origemPedido ?? this.origemPedido,
      statusFila: statusFila ?? this.statusFila,
      clienteReferencia: clearClienteReferencia
          ? null
          : (clienteReferencia ?? this.clienteReferencia),
      ownerId: ownerId ?? this.ownerId,
      gerenteId: gerenteId ?? this.gerenteId,
      representanteId: representanteId ?? this.representanteId,
      vendedorId: vendedorId ?? this.vendedorId,
      representedCompanyId: representedCompanyId ?? this.representedCompanyId,
      originCompanyUnitId: originCompanyUnitId ?? this.originCompanyUnitId,
      originCompanyUnitLabel:
          originCompanyUnitLabel ?? this.originCompanyUnitLabel,
      originCompanyUf: originCompanyUf ?? this.originCompanyUf,
      itens: itens ?? this.itens,
      totalItens: totalItens ?? this.totalItens,
      totalBruto: totalBruto ?? this.totalBruto,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncVersion: syncVersion ?? this.syncVersion,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tenantId': tenantId,
      'origemPedido': origemPedido.value,
      'statusFila': statusFila.value,
      'clienteReferencia': clienteReferencia?.toMap(),
      'ownerId': ownerId,
      'gerenteId': gerenteId,
      'representanteId': representanteId,
      'vendedorId': vendedorId,
      'representedCompanyId': representedCompanyId,
      'originCompanyUnitId': originCompanyUnitId,
      'originCompanyUnitLabel': originCompanyUnitLabel,
      'originCompanyUf': originCompanyUf,
      'itens': itens.map((item) => item.toMap()).toList(),
      'totalItens': totalItens,
      'totalBruto': totalBruto,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'syncVersion': syncVersion,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }
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

class PedidoItem {
  const PedidoItem({
    required this.id,
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.appliedDiscountPercents = const <double>[],
    this.unit,
    this.ncm,
    this.taxSnapshot,
  });

  factory PedidoItem.fromMap(Map<String, Object?> map) {
    return PedidoItem(
      id: map['id'] as String? ?? '',
      productId: map['productId'] as String? ?? '',
      productCode: map['productCode'] as String? ?? '',
      productName: map['productName'] as String? ?? '',
      quantity: _readDouble(map['quantity']) ?? 0,
      unitPrice: _readDouble(map['unitPrice']) ?? 0,
      totalPrice: _readDouble(map['totalPrice']) ?? 0,
      appliedDiscountPercents: _readDoubleList(map['appliedDiscountPercents']),
      unit: map['unit'] as String?,
      ncm: map['ncm'] as String?,
      taxSnapshot: map['taxSnapshot'] is Map
          ? PedidoItemTaxSnapshot.fromMap(
              Map<String, Object?>.from(map['taxSnapshot'] as Map),
            )
          : null,
    );
  }

  final String id;
  final String productId;
  final String productCode;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final List<double> appliedDiscountPercents;
  final String? unit;
  final String? ncm;
  final PedidoItemTaxSnapshot? taxSnapshot;

  PedidoItem copyWith({
    String? id,
    String? productId,
    String? productCode,
    String? productName,
    double? quantity,
    double? unitPrice,
    double? totalPrice,
    List<double>? appliedDiscountPercents,
    String? unit,
    String? ncm,
    PedidoItemTaxSnapshot? taxSnapshot,
  }) {
    return PedidoItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productCode: productCode ?? this.productCode,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      appliedDiscountPercents:
          appliedDiscountPercents ?? this.appliedDiscountPercents,
      unit: unit ?? this.unit,
      ncm: ncm ?? this.ncm,
      taxSnapshot: taxSnapshot ?? this.taxSnapshot,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'productId': productId,
      'productCode': productCode,
      'productName': productName,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalPrice': totalPrice,
      'appliedDiscountPercents': appliedDiscountPercents,
      'unit': unit,
      'ncm': ncm,
      'taxSnapshot': taxSnapshot?.toMap(),
    };
  }
}

class PedidoItemTaxSnapshot {
  const PedidoItemTaxSnapshot({
    this.regraFiscalId,
    this.tabelaId,
    this.ufDestino,
    this.ncm,
    this.cest,
    this.aliquotaIpiPercent,
    this.aliquotaDestinoPercent,
    this.aliquotaCreditoPercent,
    this.aliquotaDifalPercent,
    this.valorIpi,
    this.valorSt,
    this.valorDifal,
    this.valorTotalItem,
  });

  factory PedidoItemTaxSnapshot.fromMap(Map<String, Object?> map) {
    return PedidoItemTaxSnapshot(
      regraFiscalId: map['regraFiscalId'] as String?,
      tabelaId: map['tabelaId'] as String?,
      ufDestino: map['ufDestino'] as String?,
      ncm: map['ncm'] as String?,
      cest: map['cest'] as String?,
      aliquotaIpiPercent: _readDouble(map['aliquotaIpiPercent']),
      aliquotaDestinoPercent: _readDouble(map['aliquotaDestinoPercent']),
      aliquotaCreditoPercent: _readDouble(map['aliquotaCreditoPercent']),
      aliquotaDifalPercent: _readDouble(map['aliquotaDifalPercent']),
      valorIpi: _readDouble(map['valorIpi']),
      valorSt: _readDouble(map['valorSt']),
      valorDifal: _readDouble(map['valorDifal']),
      valorTotalItem: _readDouble(map['valorTotalItem']),
    );
  }

  final String? regraFiscalId;
  final String? tabelaId;
  final String? ufDestino;
  final String? ncm;
  final String? cest;
  final double? aliquotaIpiPercent;
  final double? aliquotaDestinoPercent;
  final double? aliquotaCreditoPercent;
  final double? aliquotaDifalPercent;
  final double? valorIpi;
  final double? valorSt;
  final double? valorDifal;
  final double? valorTotalItem;

  PedidoItemTaxSnapshot copyWith({
    String? regraFiscalId,
    String? tabelaId,
    String? ufDestino,
    String? ncm,
    String? cest,
    double? aliquotaIpiPercent,
    double? aliquotaDestinoPercent,
    double? aliquotaCreditoPercent,
    double? aliquotaDifalPercent,
    double? valorIpi,
    double? valorSt,
    double? valorDifal,
    double? valorTotalItem,
  }) {
    return PedidoItemTaxSnapshot(
      regraFiscalId: regraFiscalId ?? this.regraFiscalId,
      tabelaId: tabelaId ?? this.tabelaId,
      ufDestino: ufDestino ?? this.ufDestino,
      ncm: ncm ?? this.ncm,
      cest: cest ?? this.cest,
      aliquotaIpiPercent: aliquotaIpiPercent ?? this.aliquotaIpiPercent,
      aliquotaDestinoPercent:
          aliquotaDestinoPercent ?? this.aliquotaDestinoPercent,
      aliquotaCreditoPercent:
          aliquotaCreditoPercent ?? this.aliquotaCreditoPercent,
      aliquotaDifalPercent: aliquotaDifalPercent ?? this.aliquotaDifalPercent,
      valorIpi: valorIpi ?? this.valorIpi,
      valorSt: valorSt ?? this.valorSt,
      valorDifal: valorDifal ?? this.valorDifal,
      valorTotalItem: valorTotalItem ?? this.valorTotalItem,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'regraFiscalId': regraFiscalId,
      'tabelaId': tabelaId,
      'ufDestino': ufDestino,
      'ncm': ncm,
      'cest': cest,
      'aliquotaIpiPercent': aliquotaIpiPercent,
      'aliquotaDestinoPercent': aliquotaDestinoPercent,
      'aliquotaCreditoPercent': aliquotaCreditoPercent,
      'aliquotaDifalPercent': aliquotaDifalPercent,
      'valorIpi': valorIpi,
      'valorSt': valorSt,
      'valorDifal': valorDifal,
      'valorTotalItem': valorTotalItem,
    };
  }
}

List<PedidoItem> _readItems(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value
      .whereType<Map>()
      .map((item) => PedidoItem.fromMap(Map<String, Object?>.from(item)))
      .toList();
}

double? _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.'));
  }
  return null;
}

List<double> _readDoubleList(Object? value) {
  if (value is! List) {
    return const <double>[];
  }

  final result = <double>[];
  for (final item in value) {
    final parsed = _readDouble(item);
    if (parsed == null) {
      continue;
    }
    result.add(parsed);
  }
  return result;
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
