part of 'workspace_profile_service.dart';

mixin _WorkspaceProfileOrderDiscountsMixin {
  FirebaseFirestore get _firestore;

  Stream<OrderDiscountPolicy> watchOrderDiscountPolicy({
    required String tenantId,
    required String? representedCompanyId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const OrderDiscountPolicy());
    }

    final scopeKey = _scopeKey(representedCompanyId);
    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .snapshots()
        .map((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          return _readOrderDiscountPolicyForScope(
            data: data,
            scopeKey: scopeKey,
          );
        });
  }

  /// Leitura unica (nao continua) - ver comentario equivalente em
  /// `fetchPaymentConditionRules`.
  Future<OrderDiscountPolicy> fetchOrderDiscountPolicy({
    required String tenantId,
    required String? representedCompanyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const OrderDiscountPolicy();
    }

    final scopeKey = _scopeKey(representedCompanyId);
    final doc = await _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .get();
    final data = doc.data() ?? const <String, dynamic>{};
    return _readOrderDiscountPolicyForScope(data: data, scopeKey: scopeKey);
  }

  Future<void> updateOrderDiscountPolicy({
    required String tenantId,
    required String? representedCompanyId,
    required OrderDiscountPolicy policy,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Dados invalidos para salvar politica de descontos.');
    }

    final scopeKey = _scopeKey(representedCompanyId);
    final normalizedFields = <OrderDiscountFieldRule>[];
    for (var index = 0; index < policy.fields.length; index++) {
      final field = policy.fields[index];
      final label = field.label.trim().isEmpty
          ? 'Desconto ${index + 1}'
          : field.label.trim();
      var minPercent = field.minPercent;
      var maxPercent = field.maxPercent;
      if (minPercent > maxPercent) {
        final swap = minPercent;
        minPercent = maxPercent;
        maxPercent = swap;
      }
      normalizedFields.add(
        OrderDiscountFieldRule(
          label: label,
          minPercent: minPercent,
          maxPercent: maxPercent,
          applyMode: field.applyMode,
        ),
      );
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'representedOrderDiscountPolicy': {
        scopeKey: {
          'fields': normalizedFields
              .map((item) => item.toMap())
              .toList(growable: false),
        },
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  OrderDiscountPolicy _readOrderDiscountPolicyForScope({
    required Map<String, dynamic> data,
    required String scopeKey,
  }) {
    final root = data['representedOrderDiscountPolicy'];
    if (root is! Map) {
      return const OrderDiscountPolicy();
    }

    final scoped = root[scopeKey] ?? root['__tenant__'];
    if (scoped is! Map) {
      return const OrderDiscountPolicy();
    }

    final rawFields = scoped['fields'];
    if (rawFields is! List) {
      return const OrderDiscountPolicy();
    }

    final fields = <OrderDiscountFieldRule>[];
    for (var index = 0; index < rawFields.length; index++) {
      final item = rawFields[index];
      if (item is! Map) {
        continue;
      }
      final map = item.cast<Object?, Object?>();
      final label = (map['label'] ?? '').toString().trim().isEmpty
          ? 'Desconto ${index + 1}'
          : (map['label'] ?? '').toString().trim();
      var minPercent = _toDouble(map['minPercent']);
      var maxPercent = _toDouble(map['maxPercent']);
      if (minPercent > maxPercent) {
        final swap = minPercent;
        minPercent = maxPercent;
        maxPercent = swap;
      }
      fields.add(
        OrderDiscountFieldRule(
          label: label,
          minPercent: minPercent,
          maxPercent: maxPercent,
          applyMode: OrderDiscountApplyMode.fromStorage(map['applyMode']),
        ),
      );
    }

    return OrderDiscountPolicy(fields: fields);
  }
}
