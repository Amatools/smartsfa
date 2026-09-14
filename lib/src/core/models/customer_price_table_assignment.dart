import '../contracts/tenant_scoped_entity.dart';

class CustomerPriceTableAssignment implements TenantScopedEntity {
  const CustomerPriceTableAssignment({
    required this.id,
    required this.tenantId,
    required this.customerId,
    required this.priceTableId,
    required this.status,
    this.regionId,
    this.priority = 0,
    this.isDefault = false,
    this.validFrom,
    this.validUntil,
    this.createdAt,
    this.updatedAt,
  });

  factory CustomerPriceTableAssignment.fromMap(Map<String, Object?> map) {
    return CustomerPriceTableAssignment(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      customerId: map['customerId'] as String? ?? '',
      priceTableId: map['priceTableId'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      regionId: map['regionId'] as String?,
      priority: _readInt(map['priority']) ?? 0,
      isDefault: map['isDefault'] == true,
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
  final String customerId;
  final String priceTableId;
  final String status;
  final String? regionId;
  final int priority;
  final bool isDefault;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tenantId': tenantId,
      'customerId': customerId,
      'priceTableId': priceTableId,
      'status': status,
      'regionId': regionId,
      'priority': priority,
      'isDefault': isDefault,
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
