part of 'workspace_profile_service.dart';

mixin _WorkspaceProfileProductTaxonomyMixin {
  FirebaseFirestore get _firestore;

  Future<int> syncRepresentedProductTaxonomyFromProducts({
    required String tenantId,
    required String? representedCompanyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Dados invalidos para sincronizar categorias do ERP.');
    }

    final normalizedRepresentedCompanyId = _effectiveRepresentedCompanyId(
      normalizedTenantId,
      representedCompanyId,
    );
    final scopeKey = _scopeKey(normalizedRepresentedCompanyId);

    final tenantDoc = await _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .get();
    final tenantData = tenantDoc.data() ?? const <String, dynamic>{};
    final currentTaxonomy = _readTaxonomyForScope(
      data: tenantData,
      scopeKey: scopeKey,
    );

    final existingCategoriesByKey = <String, ProductCategoryTaxonomyItem>{};
    for (final item in currentTaxonomy) {
      final name = item.name.trim();
      if (name.isEmpty) {
        continue;
      }
      existingCategoriesByKey.putIfAbsent(name.toLowerCase(), () => item);
    }

    final productsSnapshot = await _firestore
        .collection('produtos')
        .where('tenantId', isEqualTo: normalizedTenantId)
        .get();

    final categoriesFromProducts = <String, String>{};
    for (final doc in productsSnapshot.docs) {
      final data = doc.data();
      final origin = (data['origemCadastro'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (origin != 'erp') {
        continue;
      }

      if (!_productBelongsToRepresentedScope(
        data: data,
        representedCompanyId: normalizedRepresentedCompanyId,
      )) {
        continue;
      }

      final rawCategory = (data['categoria'] ?? data['nomeGrupoProduto'] ?? '')
          .toString()
          .trim();
      if (rawCategory.isEmpty) {
        continue;
      }

      categoriesFromProducts.putIfAbsent(
        rawCategory.toLowerCase(),
        () => rawCategory,
      );
    }

    if (categoriesFromProducts.isEmpty) {
      return 0;
    }

    final nextTaxonomy = currentTaxonomy
        .map(
          (item) => ProductCategoryTaxonomyItem(
            name: item.name,
            subcategories: [...item.subcategories],
          ),
        )
        .toList(growable: true);

    var addedCount = 0;
    final sortedCategoryKeys = categoriesFromProducts.keys.toList()..sort();
    for (final categoryKey in sortedCategoryKeys) {
      if (existingCategoriesByKey.containsKey(categoryKey)) {
        continue;
      }

      final categoryName = categoriesFromProducts[categoryKey] ?? '';
      if (categoryName.trim().isEmpty) {
        continue;
      }

      nextTaxonomy.add(
        ProductCategoryTaxonomyItem(
          name: categoryName,
          subcategories: const <String>[],
        ),
      );
      existingCategoriesByKey[categoryKey] = ProductCategoryTaxonomyItem(
        name: categoryName,
        subcategories: const <String>[],
      );
      addedCount += 1;
    }

    if (addedCount == 0) {
      return 0;
    }

    await updateRepresentedProductTaxonomy(
      tenantId: normalizedTenantId,
      representedCompanyId: normalizedRepresentedCompanyId,
      taxonomy: nextTaxonomy,
    );

    return addedCount;
  }

  Stream<List<String>> watchRepresentedProductCategories({
    required String tenantId,
    required String? representedCompanyId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <String>[]);
    }

    final scopeKey = _scopeKey(
      _effectiveRepresentedCompanyId(normalizedTenantId, representedCompanyId),
    );
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

    final scopeKey = _scopeKey(
      _effectiveRepresentedCompanyId(normalizedTenantId, representedCompanyId),
    );
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
    final scopeKey = _scopeKey(
      _effectiveRepresentedCompanyId(normalizedTenantId, representedCompanyId),
    );

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

    final scopeKey = _scopeKey(
      _effectiveRepresentedCompanyId(normalizedTenantId, representedCompanyId),
    );
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
}
