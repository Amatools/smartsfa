part of 'workspace_profile_service.dart';

mixin _WorkspaceProfileCommercialAdjustmentsMixin {
  FirebaseFirestore get _firestore;

  Stream<CommercialAdjustmentTargetCatalog>
  watchCommercialAdjustmentTargetCatalog({
    required String tenantId,
    required String? representedCompanyId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const CommercialAdjustmentTargetCatalog());
    }

    return _firestore
        .collection('produtos')
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map((snapshot) {
          final brandsByKey = <String, String>{};
          final productsByKey = <String, String>{};

          for (final doc in snapshot.docs) {
            final data = doc.data();
            if (!_productBelongsToRepresentedScope(
              data: data,
              representedCompanyId: representedCompanyId,
            )) {
              continue;
            }

            final brand = (data['marca'] ?? '').toString().trim();
            if (brand.isNotEmpty) {
              brandsByKey.putIfAbsent(brand.toLowerCase(), () => brand);
            }

            final product = _resolveProductTargetLabel(
              data: data,
              fallbackId: doc.id,
            );
            if (product.isNotEmpty) {
              productsByKey.putIfAbsent(product.toLowerCase(), () => product);
            }
          }

          final brands = brandsByKey.values.toList(growable: false)
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          final products = productsByKey.values.toList(growable: false)
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          return CommercialAdjustmentTargetCatalog(
            brands: brands,
            products: products,
          );
        });
  }

  Stream<List<CommercialAdjustmentRule>> watchCommercialAdjustmentRules({
    required String tenantId,
    required String? representedCompanyId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <CommercialAdjustmentRule>[]);
    }

    final scopeKey = _scopeKey(representedCompanyId);
    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .snapshots()
        .map((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          return _readCommercialAdjustmentRulesForScope(
            data: data,
            scopeKey: scopeKey,
          );
        });
  }

  /// Leitura unica (nao continua) - ver comentario equivalente em
  /// `fetchPaymentConditionRules`.
  Future<List<CommercialAdjustmentRule>> fetchCommercialAdjustmentRules({
    required String tenantId,
    required String? representedCompanyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const <CommercialAdjustmentRule>[];
    }

    final scopeKey = _scopeKey(representedCompanyId);
    final doc = await _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .get();
    final data = doc.data() ?? const <String, dynamic>{};
    return _readCommercialAdjustmentRulesForScope(
      data: data,
      scopeKey: scopeKey,
    );
  }

  List<CommercialAdjustmentRule> _readCommercialAdjustmentRulesForScope({
    required Map<String, dynamic> data,
    required String scopeKey,
  }) {
    final root = data['representedCommercialAdjustments'];
    if (root is! Map) {
      return const <CommercialAdjustmentRule>[];
    }
    final scoped = root[scopeKey] ?? root['__tenant__'];
    if (scoped is! List) {
      return const <CommercialAdjustmentRule>[];
    }

    final rules = <CommercialAdjustmentRule>[];
    for (final item in scoped) {
      if (item is! Map) {
        continue;
      }
      final map = item.cast<Object?, Object?>();
      final name = (map['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        continue;
      }
      final rawScopeTarget = (map['scopeTarget'] ?? '').toString();
      final scopeTargets = _readScopeTargets(
        raw: map['scopeTargets'],
        fallbackScopeTarget: rawScopeTarget,
      );
      rules.add(
        CommercialAdjustmentRule(
          name: name,
          adjustmentType: (map['adjustmentType'] ?? 'discount').toString(),
          valueType: (map['valueType'] ?? 'percent').toString(),
          value: _toDouble(map['value']),
          scope: (map['scope'] ?? 'geral').toString(),
          scopeTarget: rawScopeTarget.trim().isEmpty
              ? scopeTargets.join(' | ')
              : rawScopeTarget,
          scopeTargets: scopeTargets,
        ),
      );
    }
    return rules;
  }

  Future<void> updateCommercialAdjustmentRules({
    required String tenantId,
    required String? representedCompanyId,
    required List<CommercialAdjustmentRule> rules,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError(
        'Dados invalidos para salvar regras de acrescimos e descontos.',
      );
    }

    final normalizedRules = rules
        .where((rule) => rule.name.trim().isNotEmpty)
        .map(
          (rule) => CommercialAdjustmentRule(
            name: rule.name.trim(),
            adjustmentType: rule.adjustmentType,
            valueType: rule.valueType,
            value: rule.value,
            scope: rule.scope,
            scopeTarget: rule.scope == 'geral'
                ? ''
                : _normalizeScopeTargets(
                    rule.scopeTargets.isEmpty
                        ? _splitScopeTargets(rule.scopeTarget)
                        : rule.scopeTargets,
                  ).join(' | '),
            scopeTargets: rule.scope == 'geral'
                ? const <String>[]
                : _normalizeScopeTargets(
                    rule.scopeTargets.isEmpty
                        ? _splitScopeTargets(rule.scopeTarget)
                        : rule.scopeTargets,
                  ),
          ),
        )
        .map((rule) => rule.toMap())
        .toList(growable: false);
    final scopeKey = _scopeKey(representedCompanyId);

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'representedCommercialAdjustments': {scopeKey: normalizedRules},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
