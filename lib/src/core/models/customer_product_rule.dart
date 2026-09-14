import '../contracts/tenant_scoped_entity.dart';

class CustomerProductRule implements TenantScopedEntity {
  const CustomerProductRule({
    required this.id,
    required this.tenantId,
    required this.customerId,
    required this.productId,
    required this.discountPolicyId,
    required this.status,
    this.priority = 0,
    this.validFrom,
    this.validUntil,
    this.createdAt,
    this.updatedAt,
  });

  factory CustomerProductRule.fromMap(Map<String, Object?> map) {
    return CustomerProductRule(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      customerId: map['customerId'] as String? ?? '',
      productId: map['productId'] as String? ?? '',
      discountPolicyId: map['discountPolicyId'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      priority: _readInt(map['priority']) ?? 0,
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
  final String productId;
  final String discountPolicyId;
  final String status;
  final int priority;
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
      'productId': productId,
      'discountPolicyId': discountPolicyId,
      'status': status,
      'priority': priority,
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
