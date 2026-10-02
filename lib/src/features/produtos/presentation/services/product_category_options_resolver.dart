class ProductCategoryTaxonomySelectionData {
  const ProductCategoryTaxonomySelectionData({
    required this.categories,
    required this.subcategoriesByCategory,
    required this.effectiveCategory,
    required this.subcategoryOptions,
    required this.effectiveSubcategory,
  });

  final List<String> categories;
  final Map<String, List<String>> subcategoriesByCategory;
  final String? effectiveCategory;
  final List<String> subcategoryOptions;
  final String? effectiveSubcategory;
}

class ProductCategoryOptionsResolver {
  static ProductCategoryTaxonomySelectionData resolve({
    required Map<String, dynamic> workspaceData,
    required String? representedCompanyId,
    required String currentCategory,
    required String currentSubcategory,
  }) {
    final categoriesByLowerName = <String, String>{};
    final subcategoriesByCategoryLowerName = <String, Map<String, String>>{};
    final normalizedScopeKey = _scopeKey(representedCompanyId);
    final scopedKeys = <String>[
      normalizedScopeKey,
      'tenant_default',
      '__tenant__',
    ];

    final root = workspaceData['representedProductTaxonomy'];
    if (root is Map) {
      final parsedRoot = root.cast<Object?, Object?>();

      for (final key in scopedKeys) {
        final scoped = parsedRoot[key];
        if (scoped is! Map) {
          continue;
        }

        final scopedMap = scoped.cast<Object?, Object?>();
        final rawCategories = scopedMap['categories'];
        if (rawCategories is! List) {
          continue;
        }

        for (final categoryItem in rawCategories) {
          if (categoryItem is! Map) {
            continue;
          }

          final categoryMap = categoryItem.cast<Object?, Object?>();
          final categoryName = (categoryMap['name'] ?? '').toString().trim();
          if (categoryName.isEmpty) {
            continue;
          }

          final categoryLower = categoryName.toLowerCase();
          categoriesByLowerName.putIfAbsent(categoryLower, () => categoryName);

          final subcategorySet = subcategoriesByCategoryLowerName.putIfAbsent(
            categoryLower,
            () => <String, String>{},
          );
          final rawSubcategories = categoryMap['subcategories'];
          if (rawSubcategories is! List) {
            continue;
          }

          for (final subcategoryItem in rawSubcategories) {
            final subcategoryName = subcategoryItem?.toString().trim() ?? '';
            if (subcategoryName.isEmpty) {
              continue;
            }
            subcategorySet.putIfAbsent(
              subcategoryName.toLowerCase(),
              () => subcategoryName,
            );
          }
        }
      }
    }

    if (categoriesByLowerName.isEmpty) {
      final legacyRoot = workspaceData['representedProductCategories'];
      if (legacyRoot is Map) {
        final parsedLegacyRoot = legacyRoot.cast<Object?, Object?>();
        for (final key in scopedKeys) {
          final scoped = parsedLegacyRoot[key];
          if (scoped is! List) {
            continue;
          }
          for (final item in scoped) {
            final categoryName = item?.toString().trim() ?? '';
            if (categoryName.isEmpty) {
              continue;
            }
            categoriesByLowerName.putIfAbsent(
              categoryName.toLowerCase(),
              () => categoryName,
            );
          }
        }
      }
    }

    final categories = categoriesByLowerName.values.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final subcategoriesByCategory = <String, List<String>>{};
    for (final category in categories) {
      final key = category.toLowerCase();
      final values =
          subcategoriesByCategoryLowerName[key]?.values.toList(
            growable: false,
          ) ??
          const <String>[];
      final sortedValues = [...values]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      subcategoriesByCategory[category] = sortedValues;
    }

    final categoriesByLower = <String, String>{
      for (final category in categories) category.toLowerCase(): category,
    };

    final normalizedCurrentCategory = currentCategory.trim();
    final effectiveCategory =
        categoriesByLower[normalizedCurrentCategory.toLowerCase()] ??
        (categories.isNotEmpty ? categories.first : null);

    final subcategoryOptions = effectiveCategory == null
        ? const <String>[]
        : (subcategoriesByCategory[effectiveCategory] ?? const <String>[]);

    final normalizedCurrentSubcategory = currentSubcategory.trim();
    final subcategoryByLower = <String, String>{
      for (final subcategory in subcategoryOptions)
        subcategory.toLowerCase(): subcategory,
    };
    final effectiveSubcategory =
        subcategoryByLower[normalizedCurrentSubcategory.toLowerCase()] ??
        (subcategoryOptions.isNotEmpty ? subcategoryOptions.first : null);

    return ProductCategoryTaxonomySelectionData(
      categories: categories,
      subcategoriesByCategory: subcategoriesByCategory,
      effectiveCategory: effectiveCategory,
      subcategoryOptions: subcategoryOptions,
      effectiveSubcategory: effectiveSubcategory,
    );
  }

  static String _scopeKey(String? representedCompanyId) {
    final normalized = (representedCompanyId ?? '').trim();
    if (normalized.isEmpty) {
      return 'tenant_default';
    }
    return normalized.replaceAll('.', '_');
  }
}
