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
    this.scopeTargets = const <String>[],
  });

  final String name;
  final String adjustmentType;
  final String valueType;
  final double value;
  final String scope;
  final String scopeTarget;
  final List<String> scopeTargets;

  Map<String, Object> toMap() {
    final normalizedScopeTargets = <String>[];
    final seen = <String>{};
    for (final value in scopeTargets) {
      final clean = value.trim();
      if (clean.isEmpty) {
        continue;
      }
      final key = clean.toLowerCase();
      if (!seen.add(key)) {
        continue;
      }
      normalizedScopeTargets.add(clean);
    }
    final normalizedScopeTarget = scopeTarget.trim();
    final effectiveScopeTarget = normalizedScopeTarget.isNotEmpty
        ? normalizedScopeTarget
        : normalizedScopeTargets.join(' | ');

    final map = <String, Object>{
      'name': name,
      'adjustmentType': adjustmentType,
      'valueType': valueType,
      'value': value,
      'scope': scope,
      'scopeTarget': effectiveScopeTarget,
    };

    if (normalizedScopeTargets.isNotEmpty) {
      map['scopeTargets'] = normalizedScopeTargets;
    }

    return map;
  }
}

class CommercialAdjustmentTargetCatalog {
  const CommercialAdjustmentTargetCatalog({
    this.brands = const <String>[],
    this.products = const <String>[],
  });

  final List<String> brands;
  final List<String> products;
}

class OrderDiscountFieldRule {
  const OrderDiscountFieldRule({
    required this.label,
    required this.minPercent,
    required this.maxPercent,
  });

  final String label;
  final double minPercent;
  final double maxPercent;

  Map<String, Object> toMap() {
    return <String, Object>{
      'label': label,
      'minPercent': minPercent,
      'maxPercent': maxPercent,
    };
  }
}

class OrderDiscountPolicy {
  const OrderDiscountPolicy({this.fields = const <OrderDiscountFieldRule>[]});

  final List<OrderDiscountFieldRule> fields;
}

class ProductCategoryTaxonomyItem {
  const ProductCategoryTaxonomyItem({
    required this.name,
    required this.subcategories,
  });

  final String name;
  final List<String> subcategories;

  Map<String, Object> toMap() {
    return <String, Object>{'name': name, 'subcategories': subcategories};
  }
}

class WorkspaceProfileService {
  WorkspaceProfileService(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>>
  get _representedCompaniesCollection =>
      _firestore.collection('tenant_represented_companies');

  static const String _defaultPriceRegionId = 'default';
  static const Set<String> _validTaxRegimes = <String>{
    'simples_nacional',
    'lucro_presumido',
    'lucro_real',
  };

  Stream<Map<String, dynamic>?> watchWorkspace(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(null);
    }

    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .snapshots()
        .map((doc) => doc.data());
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

    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .snapshots()
        .map((doc) {
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
    String? representedCompanyId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <PaymentConditionRule>[]);
    }

    final normalizedRepresentedCompanyId = (representedCompanyId ?? '').trim();
    if (normalizedRepresentedCompanyId.isNotEmpty) {
      final representedRef = _representedCompaniesCollection.doc(
        _representedCompanyDocId(
          normalizedTenantId,
          normalizedRepresentedCompanyId,
        ),
      );
      return representedRef.snapshots().map((doc) {
        final data = doc.data() ?? const <String, dynamic>{};
        return _parsePaymentConditionRulesList(data['paymentConditionRules']);
      });
    }

    final scopeKey = _scopeKey(representedCompanyId);

    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .snapshots()
        .map((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          return _readPaymentConditionRulesForScope(
            data: data,
            scopeKey: scopeKey,
          );
        });
  }

  Stream<List<Map<String, Object?>>> watchRepresentedCompanies(
    String tenantId,
  ) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <Map<String, Object?>>[]);
    }

    return _representedCompaniesCollection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map((snapshot) {
          final companies = snapshot.docs
              .map(
                (doc) => doc.data().map(
                  (key, value) => MapEntry(key, value as Object?),
                ),
              )
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
    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .snapshots()
        .map((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          final taxonomy = _readTaxonomyForScope(
            data: data,
            scopeKey: scopeKey,
          );
          final categories = taxonomy
              .map((item) => item.name.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false);
          categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return categories;
        });
  }

  Stream<List<ProductCategoryTaxonomyItem>> watchRepresentedProductTaxonomy({
    required String tenantId,
    required String? representedCompanyId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <ProductCategoryTaxonomyItem>[]);
    }

    final scopeKey = _scopeKey(representedCompanyId);
    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .snapshots()
        .map((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          final taxonomy = _readTaxonomyForScope(
            data: data,
            scopeKey: scopeKey,
          );
          taxonomy.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
          return taxonomy;
        });
  }

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
                adjustmentType: (map['adjustmentType'] ?? 'discount')
                    .toString(),
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
        });
  }

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

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      normalizedFieldName: normalizedValues,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updatePaymentConditionRules({
    required String tenantId,
    required List<PaymentConditionRule> values,
    String? representedCompanyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Dados invalidos para salvar condicoes de pagamento.');
    }

    final scopeKey = _scopeKey(representedCompanyId);

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

    final normalizedRepresentedCompanyId = (representedCompanyId ?? '').trim();
    if (normalizedRepresentedCompanyId.isNotEmpty) {
      final representedRef = _representedCompaniesCollection.doc(
        _representedCompanyDocId(
          normalizedTenantId,
          normalizedRepresentedCompanyId,
        ),
      );
      final representedSnapshot = await representedRef.get();
      if (!representedSnapshot.exists) {
        throw StateError(
          'Representada ativa não encontrada para salvar condições de pagamento.',
        );
      }

      await representedRef.set({
        'paymentConditionRules': normalizedValues,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
      return;
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'representedPaymentConditionRules': {scopeKey: normalizedValues},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'representedProductCategories': {scopeKey: normalizedCategories},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateRepresentedProductTaxonomy({
    required String tenantId,
    required String? representedCompanyId,
    required List<ProductCategoryTaxonomyItem> taxonomy,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Dados invalidos para salvar taxonomia de categorias.');
    }

    final scopeKey = _scopeKey(representedCompanyId);
    final normalizedTaxonomy =
        taxonomy
            .map(
              (item) => ProductCategoryTaxonomyItem(
                name: item.name.trim(),
                subcategories:
                    item.subcategories
                        .map((sub) => sub.trim())
                        .where((sub) => sub.isNotEmpty)
                        .toSet()
                        .toList(growable: false)
                      ..sort(
                        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                      ),
              ),
            )
            .where((item) => item.name.isNotEmpty)
            .toList(growable: false)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'representedProductTaxonomy': {
        scopeKey: {
          'categories': normalizedTaxonomy
              .map((item) => item.toMap())
              .toList(growable: false),
        },
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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

  List<PaymentConditionRule> filterPaymentConditionsByOrderValue({
    required List<PaymentConditionRule> rules,
    required double orderTotal,
  }) {
    final normalizedTotal = orderTotal < 0 ? 0 : orderTotal;
    return rules
        .where((rule) => normalizedTotal >= rule.minimumValue)
        .toList(growable: false);
  }

  List<PaymentConditionRule> _parsePaymentConditionRulesList(Object? raw) {
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
        result.add(
          PaymentConditionRule(description: description, minimumValue: 0),
        );
        continue;
      }

      if (item is Map) {
        final map = item.cast<Object?, Object?>();
        final description = (map['description'] ?? map['descricao'] ?? '')
            .toString()
            .trim();
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
  }

  List<PaymentConditionRule> _readPaymentConditionRulesForScope({
    required Map<String, dynamic> data,
    required String scopeKey,
  }) {
    final scopedRoot = data['representedPaymentConditionRules'];
    if (scopedRoot is Map) {
      final scopedRaw = scopedRoot[scopeKey] ?? scopedRoot['__tenant__'];
      final scopedParsed = _parsePaymentConditionRulesList(scopedRaw);
      if (scopedParsed.isNotEmpty) {
        return scopedParsed;
      }
    }

    // Legacy fallback for old tenant-wide payloads.
    return _parsePaymentConditionRulesList(data['paymentConditionRules']);
  }

  String _representedCompanyDocId(
    String tenantId,
    String representedCompanyId,
  ) {
    return '${tenantId}_$representedCompanyId';
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

    if (!values.containsKey('taxRegime')) {
      throw StateError('Regime tributário é obrigatório.');
    }

    void writeIfPresent(String key, Object? value) {
      if (value == null) {
        return;
      }
      payload[key] = value;
    }

    writeIfPresent('nomeFantasia', _normalize(values['nomeFantasia']));
    writeIfPresent(
      'contatoResponsavel',
      _normalize(values['contatoResponsavel']),
    );
    writeIfPresent(
      'telefoneComercial',
      _normalize(values['telefoneComercial']),
    );
    writeIfPresent('emailComercial', _normalize(values['emailComercial']));
    writeIfPresent('website', _normalize(values['website']));
    writeIfPresent('segmento', _normalize(values['segmento']));
    writeIfPresent('regiaoAtuacao', _normalize(values['regiaoAtuacao']));
    writeIfPresent(
      'marcasRepresentadas',
      _normalize(values['marcasRepresentadas']),
    );
    writeIfPresent('logradouro', _normalize(values['logradouro']));
    writeIfPresent('numero', _normalize(values['numero']));
    writeIfPresent('complemento', _normalize(values['complemento']));
    writeIfPresent('bairro', _normalize(values['bairro']));
    writeIfPresent('cep', _normalize(values['cep']));
    writeIfPresent('cidade', _normalize(values['cidade']));
    writeIfPresent('uf', _normalize(values['uf']));
    writeIfPresent('taxRegime', _normalizeTaxRegime(values['taxRegime']));

    if (normalizedWorkspaceType == 'seller_solo_workspace') {
      payload.remove('regiaoAtuacao');
      payload.remove('marcasRepresentadas');
    }

    await _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .set(payload, SetOptions(merge: true));
  }

  Future<void> setProductSyncFromErpEnabled({
    required String tenantId,
    required bool enabled,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError(
        'Workspace invalido para configurar sincronizacao de produtos.',
      );
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'productSyncFromErpEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setTenantErpSelectedCompany({
    required String tenantId,
    required String provider,
    required String companyId,
    required String companyName,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedProvider = provider.trim().toLowerCase();
    final normalizedCompanyId = companyId.trim();
    final normalizedCompanyName = companyName.trim();

    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para configurar ERP.');
    }
    if (normalizedProvider.isEmpty ||
        (normalizedProvider != 'sankhya' && normalizedProvider != 'custom')) {
      throw StateError('Provider ERP invalido para configuracao.');
    }
    if (normalizedCompanyId.isEmpty || normalizedCompanyName.isEmpty) {
      throw StateError('Selecione uma empresa ERP valida para continuar.');
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'erpProvider': normalizedProvider,
      'operationMode': normalizedProvider == 'sankhya' ? 'sankhya' : 'custom',
      'erpIntegration': {
        'provider': normalizedProvider,
        'selectedCompany': {
          'id': normalizedCompanyId,
          'name': normalizedCompanyName,
        },
        'selectionLocked': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setTenantErpCredentials({
    required String tenantId,
    required String provider,
    required String environment,
    required String apiBaseUrl,
    required String username,
    required String password,
    required String accessToken,
    required List<String> priceTableCodes,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedProvider = provider.trim().toLowerCase();
    final normalizedEnvironment = environment.trim().toLowerCase();
    final normalizedBaseUrl = _normalize(apiBaseUrl)
        .replaceAll(RegExp(r'/+$'), '');
    final normalizedUsername = _normalize(username);
    final normalizedPassword = _normalize(password);
    final normalizedToken = _normalize(accessToken);
    final normalizedPriceTableCodes = _normalizePriceTableCodes(
      priceTableCodes,
    );

    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para salvar credenciais ERP.');
    }
    if (normalizedProvider.isEmpty ||
        (normalizedProvider != 'sankhya' && normalizedProvider != 'custom')) {
      throw StateError('Provider ERP invalido para salvar credenciais.');
    }
    if (normalizedEnvironment != 'homolog' && normalizedEnvironment != 'prod') {
      throw StateError('Ambiente invalido. Use homolog ou prod.');
    }
    if (normalizedBaseUrl.isEmpty) {
      throw StateError('Informe a URL base da API para continuar.');
    }

    final hasToken = normalizedToken.isNotEmpty;
    final hasUserAndPass =
        normalizedUsername.isNotEmpty && normalizedPassword.isNotEmpty;
    if (!hasToken && !hasUserAndPass) {
      throw StateError(
        'Informe token de acesso ou usuario e senha para autenticar no ERP.',
      );
    }

    final tenantRef = _firestore.collection('tenants').doc(normalizedTenantId);
    final currentSnapshot = await tenantRef.get();
    final currentData = currentSnapshot.data() ?? const <String, dynamic>{};
    final currentIntegration = currentData['erpIntegration'];

    String selectedCompanyId = '';
    String selectedCompanyName = '';
    bool selectionLocked = true;

    if (currentIntegration is Map) {
      final selectedCompany = currentIntegration['selectedCompany'];
      if (selectedCompany is Map) {
        selectedCompanyId = (selectedCompany['id'] ?? '').toString().trim();
        selectedCompanyName = (selectedCompany['name'] ?? '').toString().trim();
      }

      final rawSelectionLocked = currentIntegration['selectionLocked'];
      if (rawSelectionLocked is bool) {
        selectionLocked = rawSelectionLocked;
      }
    }

    await tenantRef.set({
      'erpProvider': normalizedProvider,
      'operationMode': normalizedProvider == 'sankhya' ? 'sankhya' : 'custom',
      'erpIntegration': {
        'provider': normalizedProvider,
        'selectedCompany': {
          'id': selectedCompanyId,
          'name': selectedCompanyName,
        },
        'selectionLocked': selectionLocked,
        'environment': normalizedEnvironment,
        'credentials': {
          'apiBaseUrl': normalizedBaseUrl,
          'username': normalizedUsername,
          'password': normalizedPassword,
          'accessToken': normalizedToken,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'priceTableCodes': normalizedPriceTableCodes,
        'status': 'credentials_ready',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setTenantErpPriceTableCodes({
    required String tenantId,
    required List<String> priceTableCodes,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para salvar codigos de tabela.');
    }

    final normalizedCodes = _normalizePriceTableCodes(priceTableCodes);
    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'erpIntegration': {
        'priceTableCodes': normalizedCodes,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setTenantErpOrderTopCodes({
    required String tenantId,
    required String revendaSameUf,
    required String revendaInterstate,
    required String usoConsumoContribuinteSameUf,
    required String usoConsumoContribuinteInterstate,
    required String usoConsumoNaoContribuinteSameUf,
    required String usoConsumoNaoContribuinteInterstate,
    required String industrializacaoSameUf,
    required String industrializacaoInterstate,
    required String zfmIndustrializacao,
    required String zfmComercializacaoRevenda,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para salvar TOPs de pedido.');
    }

    final orderTopCodes = <String, String>{
      'revenda_same_uf': _normalizeTopCode(revendaSameUf),
      'revenda_interstate': _normalizeTopCode(revendaInterstate),
      'uso_consumo_contribuinte_same_uf': _normalizeTopCode(
        usoConsumoContribuinteSameUf,
      ),
      'uso_consumo_contribuinte_interstate': _normalizeTopCode(
        usoConsumoContribuinteInterstate,
      ),
      'uso_consumo_nao_contribuinte_same_uf': _normalizeTopCode(
        usoConsumoNaoContribuinteSameUf,
      ),
      'uso_consumo_nao_contribuinte_interstate': _normalizeTopCode(
        usoConsumoNaoContribuinteInterstate,
      ),
      'industrializacao_same_uf': _normalizeTopCode(industrializacaoSameUf),
      'industrializacao_interstate': _normalizeTopCode(
        industrializacaoInterstate,
      ),
      'zfm_industrializacao': _normalizeTopCode(zfmIndustrializacao),
      'zfm_comercializacao_revenda': _normalizeTopCode(
        zfmComercializacaoRevenda,
      ),
    };

    final emptyFields = orderTopCodes.entries
        .where((entry) => entry.value.isEmpty)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (emptyFields.isNotEmpty) {
      throw StateError(
        'Preencha as 10 TOPs de pedido antes de salvar. Faltando: ${emptyFields.join(', ')}.',
      );
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'erpIntegration': {
        'orderTopCodes': orderTopCodes,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setAdvancedPricingEnabled({
    required String tenantId,
    required bool enabled,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError(
        'Workspace invalido para configurar precificacao avancada.',
      );
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'advancedPricingEnabled': enabled,
      'featureFlags.advancedPricingEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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

    await _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .set(payload, SetOptions(merge: true));
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

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'planTier': normalizedTier,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    final nomeFantasia = _normalize(values['nomeFantasia']);
    if (nomeFantasia.isEmpty) {
      throw StateError('Nome fantasia é obrigatório.');
    }

    final cnpjDigits = _digitsOnly(values['cnpj']);
    if (!_isValidCnpjDigits(cnpjDigits)) {
      throw StateError('CNPJ inválido. Informe um CNPJ válido com 14 dígitos.');
    }
    final formattedCnpj = _formatCnpj(cnpjDigits);
    final cnpjRoot = cnpjDigits.substring(0, 8);

    final cepDigits = _digitsOnly(values['cep']);
    if (cepDigits.isNotEmpty && cepDigits.length != 8) {
      throw StateError('CEP inválido. Informe um CEP com 8 dígitos.');
    }

    final telefoneDigits = _digitsOnly(values['telefone']);
    if (telefoneDigits.isNotEmpty &&
        (telefoneDigits.length < 10 || telefoneDigits.length > 11)) {
      throw StateError('Telefone inválido. Informe 10 ou 11 dígitos.');
    }

    final normalizedEmail = _normalize(values['email']).toLowerCase();
    if (normalizedEmail.isNotEmpty && !_isValidEmailAddress(normalizedEmail)) {
      throw StateError('E-mail inválido.');
    }

    final normalizedUf = _normalize(values['uf']).toUpperCase();
    if (!_validBrazilStates.contains(normalizedUf)) {
      throw StateError('UF inválida.');
    }

    final parentCompanyId = _normalize(values['parentCompanyId']);
    if (parentCompanyId == normalizedId) {
      throw StateError('Uma empresa não pode ser matriz dela mesma.');
    }

    QuerySnapshot<Map<String, dynamic>>? linkedChildrenSnapshot;
    try {
      linkedChildrenSnapshot = await _representedCompaniesCollection
          .where('tenantId', isEqualTo: normalizedTenantId)
          .where('parentCompanyId', isEqualTo: normalizedId)
          .limit(1)
          .get();
    } on FirebaseException catch (error) {
      if (!_isConnectivityLimitedError(error)) {
        rethrow;
      }
    }
    if (parentCompanyId.isNotEmpty &&
        linkedChildrenSnapshot != null &&
        linkedChildrenSnapshot.docs.isNotEmpty) {
      throw StateError(
        'Esta empresa já possui filiais vinculadas e não pode ser marcada como filial.',
      );
    }

    if (parentCompanyId.isNotEmpty) {
      DocumentSnapshot<Map<String, dynamic>>? parentDoc;
      try {
        parentDoc = await _representedCompaniesCollection
            .doc('${normalizedTenantId}_$parentCompanyId')
            .get();
      } on FirebaseException catch (error) {
        if (!_isConnectivityLimitedError(error)) {
          rethrow;
        }
      }

      final parentData = parentDoc?.data();
      if (parentData != null) {
        final parentParentCompanyId = _normalize(parentData['parentCompanyId']);
        if (parentParentCompanyId.isNotEmpty) {
          throw StateError('A matriz selecionada já é uma filial.');
        }

        final parentCnpjDigits = _digitsOnly(parentData['cnpj']);
        if (parentCnpjDigits.length == 14 &&
            parentCnpjDigits.substring(0, 8) != cnpjRoot) {
          throw StateError(
            'Filial e matriz devem compartilhar a mesma raiz de CNPJ (8 primeiros dígitos).',
          );
        }
      }
    }

    QuerySnapshot<Map<String, dynamic>>? duplicatedCnpjSnapshot;
    try {
      duplicatedCnpjSnapshot = await _representedCompaniesCollection
          .where('tenantId', isEqualTo: normalizedTenantId)
          .where('cnpj', isEqualTo: formattedCnpj)
          .limit(2)
          .get();
    } on FirebaseException catch (error) {
      if (!_isConnectivityLimitedError(error)) {
        rethrow;
      }
    }
    if (duplicatedCnpjSnapshot != null) {
      for (final doc in duplicatedCnpjSnapshot.docs) {
        final existingCompanyId = _normalize(doc.data()['companyId']);
        if (existingCompanyId != normalizedId) {
          throw StateError('Já existe uma representada com esse CNPJ.');
        }
      }
    }

    await _representedCompaniesCollection.doc(docId).set({
      'tenantId': normalizedTenantId,
      'companyId': normalizedId,
      'parentCompanyId': parentCompanyId,
      'nomeFantasia': nomeFantasia,
      'razaoSocial': _normalize(values['razaoSocial']),
      'cnpj': formattedCnpj,
      'cep': _formatCep(cepDigits),
      'logradouro': _normalize(values['logradouro']),
      'numero': _normalize(values['numero']),
      'logoUrl': _normalize(values['logoUrl']),
      'contato': _normalize(values['contato']),
      'telefone': _formatPhone(telefoneDigits),
      'email': normalizedEmail,
      'cidade': _normalize(values['cidade']),
      'uf': normalizedUf,
      'segmento': _normalize(values['segmento']),
      'taxRegime': _normalizeTaxRegime(values['taxRegime']),
      'ativo': values['ativo'] != false,
      'companyUnits': FieldValue.delete(),
      'defaultOrderOriginUnitId': FieldValue.delete(),
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

    await _firestore.collection('tabelas_preco').doc(defaultPriceTableId).set({
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
    }, SetOptions(merge: true));

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'defaultPriceTableIds': {scopeKey: defaultPriceTableId},
      'defaultPriceRegionIds': {scopeKey: _defaultPriceRegionId},
      'defaultProductCatalogIds': {scopeKey: defaultCatalogId},
      'defaultPriceTableId': defaultPriceTableId,
      'defaultPriceRegionId': _defaultPriceRegionId,
      'defaultProductCatalogId': defaultCatalogId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (legacyScopeKey != scopeKey) {
      final legacyDefaultPriceTableId =
          'pt_default_${normalizedTenantId}_$legacyScopeKey';
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

      await _firestore.collection('tenants').doc(normalizedTenantId).set({
        'defaultPriceTableIds': {legacyScopeKey: FieldValue.delete()},
        'defaultPriceRegionIds': {legacyScopeKey: FieldValue.delete()},
        'defaultProductCatalogIds': {legacyScopeKey: FieldValue.delete()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    final tenantDoc = await _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .get();
    final workspaceType = (tenantDoc.data()?['workspaceType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (workspaceType == 'rep_workspace') {
      final tenantDefaultPriceTableId = 'pt_default_$normalizedTenantId';
      await _firestore
          .collection('tabelas_preco')
          .doc(tenantDefaultPriceTableId)
          .delete();
      await _firestore.collection('tenants').doc(normalizedTenantId).set({
        'defaultPriceTableIds': {'tenant_default': FieldValue.delete()},
        'defaultPriceRegionIds': {'tenant_default': FieldValue.delete()},
        'defaultProductCatalogIds': {'tenant_default': FieldValue.delete()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
    final representedRef = _representedCompaniesCollection.doc(
      '${normalizedTenantId}_$normalizedCompanyId',
    );
    final scopeKey = _normalizeDefaultPricingScopeKey(normalizedCompanyId);
    final legacyScopeKey = normalizedCompanyId.replaceAll('/', '_');
    final defaultPriceTableId = 'pt_default_${normalizedTenantId}_$scopeKey';
    final legacyDefaultPriceTableId =
        'pt_default_${normalizedTenantId}_$legacyScopeKey';
    final defaultPriceTableRef = _firestore
        .collection('tabelas_preco')
        .doc(defaultPriceTableId);
    final legacyDefaultPriceTableRef = _firestore
        .collection('tabelas_preco')
        .doc(legacyDefaultPriceTableId);

    await _firestore.runTransaction((transaction) async {
      final tenantSnapshot = await transaction.get(tenantRef);
      final favoriteId =
          (tenantSnapshot.data()?['favoriteRepresentedCompanyId'] ?? '')
              .toString()
              .trim();

      transaction.delete(representedRef);
      transaction.delete(defaultPriceTableRef);
      if (legacyDefaultPriceTableId != defaultPriceTableId) {
        transaction.delete(legacyDefaultPriceTableRef);
      }

      final defaultPriceTableIdsPatch = <String, Object?>{
        scopeKey: FieldValue.delete(),
      };
      final defaultPriceRegionIdsPatch = <String, Object?>{
        scopeKey: FieldValue.delete(),
      };
      final defaultProductCatalogIdsPatch = <String, Object?>{
        scopeKey: FieldValue.delete(),
      };
      if (legacyScopeKey != scopeKey) {
        defaultPriceTableIdsPatch[legacyScopeKey] = FieldValue.delete();
        defaultPriceRegionIdsPatch[legacyScopeKey] = FieldValue.delete();
        defaultProductCatalogIdsPatch[legacyScopeKey] = FieldValue.delete();
      }

      transaction.set(tenantRef, {
        'defaultPriceTableIds': defaultPriceTableIdsPatch,
        'defaultPriceRegionIds': defaultPriceRegionIdsPatch,
        'defaultProductCatalogIds': defaultProductCatalogIdsPatch,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (favoriteId == normalizedCompanyId) {
        transaction.set(tenantRef, {
          'favoriteRepresentedCompanyId': '',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
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

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'favoriteRepresentedCompanyId': normalizedCompanyId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _normalize(Object? value) {
    return value?.toString().trim() ?? '';
  }

  String _digitsOnly(Object? value) {
    return _normalize(value).replaceAll(RegExp(r'\D'), '');
  }

  String _normalizeTaxRegime(Object? value) {
    final normalized = _normalize(value).toLowerCase();
    if (_validTaxRegimes.contains(normalized)) {
      return normalized;
    }
    throw StateError('Regime tributário inválido.');
  }

  bool _isConnectivityLimitedError(FirebaseException error) {
    final code = error.code.trim().toLowerCase();
    return code == 'unavailable' ||
        code == 'network-request-failed' ||
        code == 'deadline-exceeded';
  }

  bool _isValidEmailAddress(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return true;
    }

    return RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
        .hasMatch(normalized);
  }

  bool _isValidCnpjDigits(String value) {
    if (value.length != 14) {
      return false;
    }

    if (RegExp(r'^(\d)\1{13}$').hasMatch(value)) {
      return false;
    }

    int calcDigit(String source, List<int> weights) {
      var sum = 0;
      for (var i = 0; i < weights.length; i++) {
        sum += int.parse(source[i]) * weights[i];
      }
      final remainder = sum % 11;
      return remainder < 2 ? 0 : 11 - remainder;
    }

    final firstDigit = calcDigit(value.substring(0, 12), <int>[
      5,
      4,
      3,
      2,
      9,
      8,
      7,
      6,
      5,
      4,
      3,
      2,
    ]);
    final secondDigit = calcDigit(
      value.substring(0, 12) + firstDigit.toString(),
      <int>[6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
    );

    return value.endsWith('$firstDigit$secondDigit');
  }

  String _formatCnpj(String digits) {
    if (digits.isEmpty) {
      return '';
    }
    final safe = digits.length > 14 ? digits.substring(0, 14) : digits;
    return '${safe.substring(0, 2)}.${safe.substring(2, 5)}.${safe.substring(5, 8)}/${safe.substring(8, 12)}-${safe.substring(12, 14)}';
  }

  String _formatCep(String digits) {
    if (digits.isEmpty) {
      return '';
    }
    final safe = digits.length > 8 ? digits.substring(0, 8) : digits;
    if (safe.length < 8) {
      return safe;
    }
    return '${safe.substring(0, 5)}-${safe.substring(5, 8)}';
  }

  String _formatPhone(String digits) {
    if (digits.isEmpty) {
      return '';
    }
    final safe = digits.length > 11 ? digits.substring(0, 11) : digits;
    if (safe.length == 10) {
      return '(${safe.substring(0, 2)}) ${safe.substring(2, 6)}-${safe.substring(6, 10)}';
    }
    if (safe.length == 11) {
      return '(${safe.substring(0, 2)}) ${safe.substring(2, 7)}-${safe.substring(7, 11)}';
    }
    return safe;
  }

  static const Set<String> _validBrazilStates = <String>{
    'AC',
    'AL',
    'AP',
    'AM',
    'BA',
    'CE',
    'DF',
    'ES',
    'GO',
    'MA',
    'MT',
    'MS',
    'MG',
    'PA',
    'PB',
    'PR',
    'PE',
    'PI',
    'RJ',
    'RN',
    'RS',
    'RO',
    'RR',
    'SC',
    'SP',
    'SE',
    'TO',
  };

  double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty) {
        return 0;
      }

      final withDotDecimal = normalized
          .replaceAll('.', '')
          .replaceAll(',', '.');
      return double.tryParse(withDotDecimal) ??
          double.tryParse(normalized.replaceAll(',', '.')) ??
          0;
    }

    return 0;
  }

  List<String> _readScopeTargets({
    required Object? raw,
    required String fallbackScopeTarget,
  }) {
    if (raw is List) {
      return _normalizeScopeTargets(
        raw.map((value) => value?.toString() ?? ''),
      );
    }
    return _splitScopeTargets(fallbackScopeTarget);
  }

  List<String> _splitScopeTargets(String raw) {
    return _normalizeScopeTargets(raw.split(RegExp(r'[,;|\n]+')));
  }

  bool _productBelongsToRepresentedScope({
    required Map<String, dynamic> data,
    required String? representedCompanyId,
  }) {
    final selectedScope = _normalizeScopeValue(representedCompanyId);
    if (selectedScope.isEmpty) {
      return true;
    }

    final mappedScope = _normalizeScopeValue(
      data['representedCompanyId'] ??
          data['representadaId'] ??
          data['companyId'],
    );

    if (mappedScope.isEmpty) {
      return true;
    }

    return mappedScope == selectedScope;
  }

  String _normalizeScopeValue(Object? value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  String _resolveProductTargetLabel({
    required Map<String, dynamic> data,
    required String fallbackId,
  }) {
    final description = (data['descricao'] ?? data['nome'] ?? '')
        .toString()
        .trim();
    final code = (data['codigoInterno'] ?? data['codigo'] ?? '')
        .toString()
        .trim();

    if (description.isNotEmpty && code.isNotEmpty) {
      return '$code - $description';
    }
    if (description.isNotEmpty) {
      return description;
    }
    if (code.isNotEmpty) {
      return code;
    }

    return fallbackId.trim();
  }

  List<String> _normalizeScopeTargets(Iterable<String> values) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final clean = value.trim();
      if (clean.isEmpty) {
        continue;
      }
      final key = clean.toLowerCase();
      if (!seen.add(key)) {
        continue;
      }
      normalized.add(clean);
    }
    return normalized;
  }

  List<String> _normalizePriceTableCodes(Iterable<String> values) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final clean = value.trim();
      if (clean.isEmpty) {
        continue;
      }
      if (!RegExp(r'^\d+$').hasMatch(clean)) {
        continue;
      }
      if (!seen.add(clean)) {
        continue;
      }
      normalized.add(clean);
    }
    return normalized;
  }

  String _normalizeTopCode(String value) {
    final clean = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(clean)) {
      return '';
    }
    return clean;
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
        ),
      );
    }

    return OrderDiscountPolicy(fields: fields);
  }

  String _scopeKey(String? representedCompanyId) {
    final normalized = (representedCompanyId ?? '').trim();
    if (normalized.isEmpty) {
      return 'tenant_default';
    }
    return normalized.replaceAll('.', '_');
  }

  List<ProductCategoryTaxonomyItem> _readTaxonomyForScope({
    required Map<String, dynamic> data,
    required String scopeKey,
  }) {
    final root = data['representedProductTaxonomy'];
    if (root is Map) {
      final taxonomy = _readTaxonomyScopedNode(root: root, scopeKey: scopeKey);
      if (taxonomy.isNotEmpty) {
        return taxonomy;
      }
    }

    final legacyRoot = data['representedProductCategories'];
    if (legacyRoot is Map) {
      final scoped = legacyRoot[scopeKey] ?? legacyRoot['__tenant__'];
      if (scoped is List) {
        final categories = <String>[];
        for (final item in scoped) {
          final value = item?.toString().trim() ?? '';
          if (value.isNotEmpty) {
            categories.add(value);
          }
        }

        return categories
            .toSet()
            .map(
              (category) => ProductCategoryTaxonomyItem(
                name: category,
                subcategories: const <String>[],
              ),
            )
            .toList(growable: false);
      }
    }

    return const <ProductCategoryTaxonomyItem>[];
  }

  List<ProductCategoryTaxonomyItem> _readTaxonomyScopedNode({
    required Map root,
    required String scopeKey,
  }) {
    final scoped = root[scopeKey] ?? root['__tenant__'];
    if (scoped is! Map) {
      return const <ProductCategoryTaxonomyItem>[];
    }

    final rawCategories = scoped['categories'];
    if (rawCategories is! List) {
      return const <ProductCategoryTaxonomyItem>[];
    }

    final result = <ProductCategoryTaxonomyItem>[];
    for (final item in rawCategories) {
      if (item is! Map) {
        continue;
      }

      final name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        continue;
      }

      final subcategories = <String>[];
      final rawSubcategories = item['subcategories'];
      if (rawSubcategories is List) {
        for (final sub in rawSubcategories) {
          final value = sub?.toString().trim() ?? '';
          if (value.isNotEmpty) {
            subcategories.add(value);
          }
        }
      }

      result.add(
        ProductCategoryTaxonomyItem(name: name, subcategories: subcategories),
      );
    }

    return result;
  }

  String _normalizeDefaultPricingScopeKey(String? representedCompanyId) {
    final normalized = (representedCompanyId ?? '').trim();
    if (normalized.isEmpty) {
      return 'tenant_default';
    }
    return normalized.replaceAll('.', '_').replaceAll('/', '_');
  }
}
