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
    this.createdAt,
    this.updatedAt,
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
          ? ClienteReference.fromMap(map['clienteReferencia'] as Map<String, Object?>)
          : null,
      ownerId: map['ownerId'] as String?,
      gerenteId: map['gerenteId'] as String?,
      representanteId: map['representanteId'] as String?,
      vendedorId: map['vendedorId'] as String?,
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
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
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Pedido copyWith({
    String? id,
    String? tenantId,
    OrderOrigin? origemPedido,
    OrderStatus? statusFila,
    ClienteReference? clienteReferencia,
    String? ownerId,
    String? gerenteId,
    String? representanteId,
    String? vendedorId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Pedido(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      origemPedido: origemPedido ?? this.origemPedido,
      statusFila: statusFila ?? this.statusFila,
      clienteReferencia: clienteReferencia ?? this.clienteReferencia,
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
      'origemPedido': origemPedido.value,
      'statusFila': statusFila.value,
      'clienteReferencia': clienteReferencia?.toMap(),
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