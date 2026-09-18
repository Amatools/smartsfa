class ProductCategorySelectionData {
  const ProductCategorySelectionData({
    required this.options,
    required this.effectiveValue,
  });

  final List<String> options;
  final String? effectiveValue;
}

class ProductCategoryOptionsResolver {
  static ProductCategorySelectionData resolve({
    required Map<String, dynamic> workspaceData,
    required String? representedCompanyId,
    required String currentCategory,
  }) {
    final root = workspaceData['representedProductCategories'];
    final normalized = <String, String>{};

    if (root is Map) {
      final parsedRoot = root.cast<Object?, Object?>();
      final scopeKey = (representedCompanyId ?? '').trim();
      final scopedKeys = <String>[
        if (scopeKey.isNotEmpty) scopeKey,
        'tenant_default',
        '__tenant__',
        ...parsedRoot.keys.map((key) => key?.toString() ?? ''),
      ];

      for (final key in scopedKeys) {
        final scoped = parsedRoot[key];
        if (scoped is! List) {
          continue;
        }
        for (final item in scoped) {
          final value = item?.toString().trim() ?? '';
          if (value.isEmpty) {
            continue;
          }
          normalized.putIfAbsent(value.toLowerCase(), () => value);
        }
      }
    }

    final categories = normalized.values.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final current = currentCategory.trim();
    final hasCurrent = current.isNotEmpty;
    final hasCurrentInList = hasCurrent && categories.contains(current);
    final options = <String>[
      ...categories,
      if (hasCurrent && !hasCurrentInList) current,
    ];

    final effectiveValue = hasCurrent
        ? current
        : (options.isNotEmpty ? options.first : null);

    return ProductCategorySelectionData(
      options: options,
      effectiveValue: effectiveValue,
    );
  }
}