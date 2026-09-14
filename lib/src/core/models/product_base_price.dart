import '../contracts/tenant_scoped_entity.dart';

class ProductBasePrice implements TenantScopedEntity {
  const ProductBasePrice({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.priceTableId,
    required this.regionId,
    required this.basePrice,
    required this.status,
    this.validFrom,
    this.validUntil,
    this.createdAt,
    this.updatedAt,
  });

  factory ProductBasePrice.fromMap(Map<String, Object?> map) {
    return ProductBasePrice(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      productId: map['productId'] as String? ?? '',
      priceTableId: map['priceTableId'] as String? ?? '',
      regionId: map['regionId'] as String? ?? '',
      basePrice: _readDouble(map['basePrice']) ?? 0,
      status: map['status'] as String? ?? 'active',
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
  final String productId;
  final String priceTableId;
  final String regionId;
  final double basePrice;
  final String status;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';

  ProductBasePrice copyWith({
    String? id,
    String? tenantId,
    String? productId,
    String? priceTableId,
    String? regionId,
    double? basePrice,
    String? status,
    DateTime? validFrom,
    DateTime? validUntil,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductBasePrice(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      productId: productId ?? this.productId,
      priceTableId: priceTableId ?? this.priceTableId,
      regionId: regionId ?? this.regionId,
      basePrice: basePrice ?? this.basePrice,
      status: status ?? this.status,
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
      'productId': productId,
      'priceTableId': priceTableId,
      'regionId': regionId,
      'basePrice': basePrice,
      'status': status,
      'validFrom': validFrom?.toIso8601String(),
      'validUntil': validUntil?.toIso8601String(),
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
