import '../contracts/tenant_scoped_entity.dart';

class DiscountPolicy implements TenantScopedEntity {
  const DiscountPolicy({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.discountPercentage,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory DiscountPolicy.fromMap(Map<String, Object?> map) {
    return DiscountPolicy(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      discountPercentage: _readDouble(map['discountPercentage']) ?? 0,
      status: map['status'] as String? ?? 'active',
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  @override
  final String id;
  @override
  final String tenantId;
  final String name;
  final double discountPercentage;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tenantId': tenantId,
      'name': name,
      'discountPercentage': discountPercentage,
      'status': status,
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
