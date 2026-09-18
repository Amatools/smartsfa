import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentConditionRule {
  const PaymentConditionRule({
    required this.description,
    required this.minimumValue,
  });

  final String description;
  final double minimumValue;

  Map<String, Object> toMap() {
    return <String, Object>{
      'description': description,
      'minimumValue': minimumValue,
    };
  }
}

class CommercialAdjustmentRule {
  const CommercialAdjustmentRule({
    required this.name,
    required this.adjustmentType,
    required this.valueType,
    required this.value,
    required this.scope,
    required this.scopeTarget,
  });

  final String name;
  final String adjustmentType;
  final String valueType;
  final double value;
  final String scope;
  final String scopeTarget;

  Map<String, Object> toMap() {
    return <String, Object>{
      'name': name,
      'adjustmentType': adjustmentType,
      'valueType': valueType,
      'value': value,
      'scope': scope,
      'scopeTarget': scopeTarget,
    };
  }
}

class WorkspaceProfileService {
  WorkspaceProfileService(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _representedCompaniesCollection =>
      _firestore.collection('tenant_represented_companies');

  static const String _defaultPriceRegionId = 'default';

  Stream<Map<String, dynamic>?> watchWorkspace(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(null);
    }

    return _firestore.collection('tenants').doc(normalizedTenantId).snapshots().map(
      (doc) => doc.data(),
    );
  }

  Stream<List<String>> watchTextRuleList({
    required String tenantId,
    required String fieldName,
  }) {
    final normalizedTenantId = tenantId.trim();
    final normalizedFieldName = fieldName.trim();
    if (normalizedTenantId.isEmpty || normalizedFieldName.isEmpty) {
      return Stream.value(const <String>[]);
    }

    return _firestore.collection('tenants').doc(normalizedTenantId).snapshots().map((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      final raw = data[normalizedFieldName];
      if (raw is! List) {
        return const <String>[];
      }

      final result = <String>[];
      for (final item in raw) {
        final value = item?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          result.add(value);
        }
      }
      return result;
    });
  }

  Stream<List<PaymentConditionRule>> watchPaymentConditionRules({
    required String tenantId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <PaymentConditionRule>[]);
    }

    return _firestore.collection('tenants').doc(normalizedTenantId).snapshots().map((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      final raw = data['paymentConditionRules'];
      if (raw is! List) {
        return const <PaymentConditionRule>[];
      }

      final result = <PaymentConditionRule>[];
      for (final item in raw) {
        if (item is String) {
          final description = item.trim();
          if (description.isEmpty) {
            continue;
          }
          result.add(PaymentConditionRule(description: description, minimumValue: 0));
          continue;
        }

        if (item is Map) {
          final map = item.cast<Object?, Object?>();
          final description = (map['description'] ?? map['descricao'] ?? '').toString().trim();
          if (description.isEmpty) {
            continue;
          }

          result.add(
            PaymentConditionRule(
              description: description,
              minimumValue: _toDouble(map['minimumValue'] ?? map['valorMinimo']),
            ),
          );
        }
      }

      return result;
    });
  }

  Stream<List<Map<String, Object?>>> watchRepresentedCompanies(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <Map<String, Object?>>[]);
    }

    return _representedCompaniesCollection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map((snapshot) {
          final companies = snapshot.docs
              .map((doc) => doc.data().map((key, value) => MapEntry(key, value as Object?)))
              .toList(growable: false);
          companies.sort((a, b) {
            final aName = (a['nomeFantasia'] ?? '').toString().toLowerCase();
            final bName = (b['nomeFantasia'] ?? '').toString().toLowerCase();
            return aName.compareTo(bName);
          });
          return companies;
        });
  }

  Stream<List<String>> watchRepresentedProductCategories({
    required String tenantId,
    required String? representedCompanyId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <String>[]);
    }

    final scopeKey = _scopeKey(representedCompanyId);
    return _firestore.collection('tenants').doc(normalizedTenantId).snapshots().map((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      final root = data['representedProductCategories'];
      if (root is! Map) {
        return const <String>[];
      }
      final scoped = root[scopeKey] ?? root['__tenant__'];
      if (scoped is! List) {
        return const <String>[];
      }

      final categories = <String>[];
      for (final item in scoped) {
        final value = item?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          categories.add(value);
        }
      }
      categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return categories;
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
    return _firestore.collection('tenants').doc(normalizedTenantId).snapshots().map((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
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
        rules.add(
          CommercialAdjustmentRule(
            name: name,
            adjustmentType: (map['adjustmentType'] ?? 'discount').toString(),
            valueType: (map['valueType'] ?? 'percent').toString(),
            value: _toDouble(map['value']),
            scope: (map['scope'] ?? 'geral').toString(),
            scopeTarget: (map['scopeTarget'] ?? '').toString(),
          ),
        );
      }
      return rules;
    });
  }

  Future<void> updateTextRuleList({
    required String tenantId,
    required String fieldName,
    required List<String> values,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedFieldName = fieldName.trim();
    if (normalizedTenantId.isEmpty || normalizedFieldName.isEmpty) {
      throw StateError('Dados invalidos para salvar regras textuais.');
    }

    final normalizedValues = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        normalizedFieldName: normalizedValues,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> updatePaymentConditionRules({
    required String tenantId,
    required List<PaymentConditionRule> values,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Dados invalidos para salvar condicoes de pagamento.');
    }

    final normalizedValues = values
        .map(
          (rule) => PaymentConditionRule(
            description: rule.description.trim(),
            minimumValue: rule.minimumValue,
          ),
        )
        .where((rule) => rule.description.isNotEmpty)
        .map((rule) => rule.toMap())
        .toList(growable: false);

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        'paymentConditionRules': normalizedValues,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> updateRepresentedProductCategories({
    required String tenantId,
    required String? representedCompanyId,
    required List<String> categories,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Dados invalidos para salvar categorias.');
    }

    final normalizedCategories = categories
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final scopeKey = _scopeKey(representedCompanyId);

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        'representedProductCategories': {
          scopeKey: normalizedCategories,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> updateCommercialAdjustmentRules({
    required String tenantId,
    required String? representedCompanyId,
    required List<CommercialAdjustmentRule> rules,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Dados invalidos para salvar regras de acrescimos e descontos.');
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
            scopeTarget: rule.scopeTarget.trim(),
          ),
        )
        .map((rule) => rule.toMap())
        .toList(growable: false);
    final scopeKey = _scopeKey(representedCompanyId);

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        'representedCommercialAdjustments': {
          scopeKey: normalizedRules,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  List<PaymentConditionRule> filterPaymentConditionsByOrderValue({
    required List<PaymentConditionRule> rules,
    required double orderTotal,
  }) {
    final normalizedTotal = orderTotal < 0 ? 0 : orderTotal;
    return rules.where((rule) => normalizedTotal >= rule.minimumValue).toList(growable: false);
  }

  Future<void> updateWorkspaceProfile({
    required String tenantId,
    required String workspaceType,
    required Map<String, Object?> values,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedWorkspaceType = workspaceType.trim();
    if (normalizedTenantId.isEmpty || normalizedWorkspaceType.isEmpty) {
      throw StateError('Workspace invalido para atualizacao.');
    }

    final payload = <String, Object?>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    void writeIfPresent(String key, Object? value) {
      if (value == null) {
        return;
      }
      payload[key] = value;
    }

    writeIfPresent('nomeFantasia', _normalize(values['nomeFantasia']));
    writeIfPresent('contatoResponsavel', _normalize(values['contatoResponsavel']));
    writeIfPresent('telefoneComercial', _normalize(values['telefoneComercial']));
    writeIfPresent('emailComercial', _normalize(values['emailComercial']));
    writeIfPresent('website', _normalize(values['website']));
    writeIfPresent('segmento', _normalize(values['segmento']));
    writeIfPresent('regiaoAtuacao', _normalize(values['regiaoAtuacao']));
    writeIfPresent('marcasRepresentadas', _normalize(values['marcasRepresentadas']));
    writeIfPresent('logradouro', _normalize(values['logradouro']));
    writeIfPresent('numero', _normalize(values['numero']));
    writeIfPresent('complemento', _normalize(values['complemento']));
    writeIfPresent('bairro', _normalize(values['bairro']));
    writeIfPresent('cep', _normalize(values['cep']));
    writeIfPresent('cidade', _normalize(values['cidade']));
    writeIfPresent('uf', _normalize(values['uf']));

    if (normalizedWorkspaceType == 'seller_solo_workspace') {
      payload.remove('regiaoAtuacao');
      payload.remove('marcasRepresentadas');
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
          payload,
          SetOptions(merge: true),
        );
  }

  Future<void> setProductSyncFromErpEnabled({
    required String tenantId,
    required bool enabled,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para configurar sincronizacao de produtos.');
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        'productSyncFromErpEnabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setAdvancedPricingEnabled({
    required String tenantId,
    required bool enabled,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para configurar precificacao avancada.');
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        'advancedPricingEnabled': enabled,
        'featureFlags.advancedPricingEnabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> updateWorkspaceFeatureFlags({
    required String tenantId,
    required Map<String, bool> flags,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para atualizar feature flags.');
    }

    final payload = <String, Object?>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    for (final entry in flags.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      payload['featureFlags.$key'] = entry.value;
    }

    if (payload.length == 1) {
      return;
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      payload,
      SetOptions(merge: true),
    );
  }

  Future<void> setWorkspacePlanTier({
    required String tenantId,
    required String tier,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedTier = tier.trim().toLowerCase();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para atualizar nivel de plano.');
    }
    if (normalizedTier != 'base' && normalizedTier != 'upgrade') {
      throw StateError('Nivel de plano invalido. Use base ou upgrade.');
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        'planTier': normalizedTier,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> upsertRepresentedCompany({
    required String tenantId,
    required Map<String, Object?> values,
    String? companyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Tenant invalido para cadastro de representada.');
    }

    final normalizedId = (companyId ?? '').trim().isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : companyId!.trim();
    final docId = '${normalizedTenantId}_$normalizedId';
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await _representedCompaniesCollection.doc(docId).set({
      'tenantId': normalizedTenantId,
      'companyId': normalizedId,
      'nomeFantasia': _normalize(values['nomeFantasia']),
      'razaoSocial': _normalize(values['razaoSocial']),
      'cnpj': _normalize(values['cnpj']),
      'cep': _normalize(values['cep']),
      'logradouro': _normalize(values['logradouro']),
      'numero': _normalize(values['numero']),
      'logoUrl': _normalize(values['logoUrl']),
      'contato': _normalize(values['contato']),
      'telefone': _normalize(values['telefone']),
      'email': _normalize(values['email']),
      'cidade': _normalize(values['cidade']),
      'uf': _normalize(values['uf']).toUpperCase(),
      'segmento': _normalize(values['segmento']),
      'ativo': values['ativo'] != false,
      'updatedAt': nowIso,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _ensureDefaultCatalogAndPricingScope(
      tenantId: normalizedTenantId,
      representedCompanyId: normalizedId,
      representedCompanyName: _normalize(values['nomeFantasia']),
    );
  }

  Future<void> _ensureDefaultCatalogAndPricingScope({
    required String tenantId,
    required String representedCompanyId,
    required String representedCompanyName,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedRepresentedId = representedCompanyId.trim();
    if (normalizedTenantId.isEmpty || normalizedRepresentedId.isEmpty) {
      return;
    }

    final scopeKey = _normalizeDefaultPricingScopeKey(normalizedRepresentedId);
    final legacyScopeKey = normalizedRepresentedId.replaceAll('/', '_');
    final defaultPriceTableId = 'pt_default_${normalizedTenantId}_$scopeKey';
    final defaultCatalogId = 'products_default_${normalizedTenantId}_$scopeKey';
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await _firestore.collection('tabelas_preco').doc(defaultPriceTableId).set(
      {
        'id': defaultPriceTableId,
        'tenantId': normalizedTenantId,
        'nome': 'Tabela padrao',
        'scopeType': 'represented_company',
        'scopeLabel': representedCompanyName.isEmpty
            ? 'Tabela padrao da representada'
            : 'Tabela padrao - $representedCompanyName',
        'scopeIndex': <String>['default', scopeKey],
        'origem': 'system',
        'status': 'ativo',
        'linkedEntityId': normalizedRepresentedId,
        'rowCount': 0,
        'createdAt': nowIso,
        'updatedAt': nowIso,
      },
      SetOptions(merge: true),
    );

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        'defaultPriceTableIds': {scopeKey: defaultPriceTableId},
        'defaultPriceRegionIds': {scopeKey: _defaultPriceRegionId},
        'defaultProductCatalogIds': {scopeKey: defaultCatalogId},
        'defaultPriceTableId': defaultPriceTableId,
        'defaultPriceRegionId': _defaultPriceRegionId,
        'defaultProductCatalogId': defaultCatalogId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (legacyScopeKey != scopeKey) {
      final legacyDefaultPriceTableId = 'pt_default_${normalizedTenantId}_$legacyScopeKey';
      final legacyDoc = await _firestore
          .collection('tabelas_preco')
          .doc(legacyDefaultPriceTableId)
          .get();
      final legacyData = legacyDoc.data() ?? <String, dynamic>{};
      final isLegacySystemDefault =
          (legacyData['origem'] ?? '').toString().trim().toLowerCase() ==
              'system' &&
          (legacyData['nome'] ?? '').toString().trim().toLowerCase() ==
              'tabela padrao';
      if (legacyDoc.exists && isLegacySystemDefault) {
        await legacyDoc.reference.delete();
      }

      await _firestore.collection('tenants').doc(normalizedTenantId).set(
        {
          'defaultPriceTableIds': {legacyScopeKey: FieldValue.delete()},
          'defaultPriceRegionIds': {legacyScopeKey: FieldValue.delete()},
          'defaultProductCatalogIds': {legacyScopeKey: FieldValue.delete()},
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    final tenantDoc = await _firestore.collection('tenants').doc(normalizedTenantId).get();
    final workspaceType =
        (tenantDoc.data()?['workspaceType'] ?? '').toString().trim().toLowerCase();
    if (workspaceType == 'rep_workspace') {
      final tenantDefaultPriceTableId = 'pt_default_$normalizedTenantId';
      await _firestore.collection('tabelas_preco').doc(tenantDefaultPriceTableId).delete();
      await _firestore.collection('tenants').doc(normalizedTenantId).set(
        {
          'defaultPriceTableIds': {'tenant_default': FieldValue.delete()},
          'defaultPriceRegionIds': {'tenant_default': FieldValue.delete()},
          'defaultProductCatalogIds': {'tenant_default': FieldValue.delete()},
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  Future<void> deleteRepresentedCompany({
    required String tenantId,
    required String companyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedCompanyId = companyId.trim();
    if (normalizedTenantId.isEmpty || normalizedCompanyId.isEmpty) {
      throw StateError('Dados invalidos para exclusao da representada.');
    }

    final tenantRef = _firestore.collection('tenants').doc(normalizedTenantId);
    final representedRef =
        _representedCompaniesCollection.doc('${normalizedTenantId}_$normalizedCompanyId');
    final scopeKey = _normalizeDefaultPricingScopeKey(normalizedCompanyId);
    final legacyScopeKey = normalizedCompanyId.replaceAll('/', '_');
    final defaultPriceTableId = 'pt_default_${normalizedTenantId}_$scopeKey';
    final legacyDefaultPriceTableId = 'pt_default_${normalizedTenantId}_$legacyScopeKey';
    final defaultPriceTableRef =
        _firestore.collection('tabelas_preco').doc(defaultPriceTableId);
    final legacyDefaultPriceTableRef =
        _firestore.collection('tabelas_preco').doc(legacyDefaultPriceTableId);

    await _firestore.runTransaction((transaction) async {
      final tenantSnapshot = await transaction.get(tenantRef);
      final favoriteId =
          (tenantSnapshot.data()?['favoriteRepresentedCompanyId'] ?? '').toString().trim();

      transaction.delete(representedRef);
      transaction.delete(defaultPriceTableRef);
      if (legacyDefaultPriceTableId != defaultPriceTableId) {
        transaction.delete(legacyDefaultPriceTableRef);
      }

      final defaultPriceTableIdsPatch = <String, Object?>{scopeKey: FieldValue.delete()};
      final defaultPriceRegionIdsPatch = <String, Object?>{scopeKey: FieldValue.delete()};
      final defaultProductCatalogIdsPatch = <String, Object?>{scopeKey: FieldValue.delete()};
      if (legacyScopeKey != scopeKey) {
        defaultPriceTableIdsPatch[legacyScopeKey] = FieldValue.delete();
        defaultPriceRegionIdsPatch[legacyScopeKey] = FieldValue.delete();
        defaultProductCatalogIdsPatch[legacyScopeKey] = FieldValue.delete();
      }

      transaction.set(
        tenantRef,
        {
          'defaultPriceTableIds': defaultPriceTableIdsPatch,
          'defaultPriceRegionIds': defaultPriceRegionIdsPatch,
          'defaultProductCatalogIds': defaultProductCatalogIdsPatch,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (favoriteId == normalizedCompanyId) {
        transaction.set(
          tenantRef,
          {
            'favoriteRepresentedCompanyId': '',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<void> setFavoriteRepresentedCompany({
    required String tenantId,
    required String companyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedCompanyId = companyId.trim();
    if (normalizedTenantId.isEmpty || normalizedCompanyId.isEmpty) {
      throw StateError('Dados invalidos para favoritar representada.');
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        'favoriteRepresentedCompanyId': normalizedCompanyId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
  String _normalize(Object? value) {
    return value?.toString().trim() ?? '';
  }

  double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty) {
        return 0;
      }

      final withDotDecimal = normalized.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(withDotDecimal) ?? double.tryParse(normalized.replaceAll(',', '.')) ?? 0;
    }

    return 0;
  }

  String _scopeKey(String? representedCompanyId) {
    final normalized = (representedCompanyId ?? '').trim();
    if (normalized.isEmpty) {
      return 'tenant_default';
    }
    return normalized.replaceAll('.', '_');
  }

  String _normalizeDefaultPricingScopeKey(String? representedCompanyId) {
    final normalized = (representedCompanyId ?? '').trim();
    if (normalized.isEmpty) {
      return 'tenant_default';
    }
    return normalized.replaceAll('.', '_').replaceAll('/', '_');
  }
}
