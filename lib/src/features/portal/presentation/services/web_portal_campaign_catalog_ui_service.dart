import '../../../../core/models/produto.dart';

class WebPortalCampaignCatalogUiService {
  const WebPortalCampaignCatalogUiService._();

  static String normalizeFilterValue(String raw) {
    return raw.trim().toLowerCase();
  }

  static bool matchesSearch(Produto product, String normalizedTerm) {
    if (normalizedTerm.isEmpty) {
      return true;
    }

    final haystack = <String>[
      product.codigoInterno,
      product.descricao,
      product.marca ?? '',
      product.ncm ?? '',
      product.categoria ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(normalizedTerm);
  }

  static bool matchesScope(
    Produto product, {
    required String? selectedRepresentedCompanyId,
  }) {
    final selectedRepresentedId = (selectedRepresentedCompanyId ?? '').trim();
    if (selectedRepresentedId.isEmpty) {
      return true;
    }

    final productRepresentedId = (product.representedCompanyId ?? '').trim();
    if (productRepresentedId.isEmpty) {
      return true;
    }
    return productRepresentedId == selectedRepresentedId;
  }

  static bool matchesBrandAndCategory(
    Produto product, {
    required String selectedBrand,
    required String selectedCategory,
    required String allBrandsFilterValue,
    required String allCategoriesFilterValue,
  }) {
    final productBrand = (product.marca ?? '').trim().toLowerCase();
    final productCategory = (product.categoria ?? '').trim().toLowerCase();

    final matchesBrand =
        selectedBrand == allBrandsFilterValue || productBrand == selectedBrand;
    final matchesCategory =
        selectedCategory == allCategoriesFilterValue ||
        productCategory == selectedCategory;

    return matchesBrand && matchesCategory;
  }

  static List<String> availableBrands(List<Produto> products) {
    final byKey = <String, String>{};
    for (final item in products) {
      final brand = (item.marca ?? '').trim();
      if (brand.isEmpty) {
        continue;
      }
      byKey.putIfAbsent(brand.toLowerCase(), () => brand);
    }
    final values = byKey.values.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  static List<String> availableCategories(List<Produto> products) {
    final byKey = <String, String>{};
    for (final item in products) {
      final category = (item.categoria ?? '').trim();
      if (category.isEmpty) {
        continue;
      }
      byKey.putIfAbsent(category.toLowerCase(), () => category);
    }
    final values = byKey.values.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  static String formatDateShort(String? isoValue) {
    final normalized = (isoValue ?? '').trim();
    if (normalized.isEmpty) {
      return '--/--/----';
    }
    final parsed = DateTime.tryParse(normalized)?.toLocal();
    if (parsed == null) {
      return '--/--/----';
    }
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final year = parsed.year.toString();
    return '$day/$month/$year';
  }

  static String buildListedProductSubtitle({
    required Produto product,
    required bool isPromotion,
    required String Function(double value) formatMoneyBr,
    required double? promotionPrice,
  }) {
    final code = _productCodeOrDash(product);
    final brand = _productBrandOrDash(product);
    final ncm = _productNcmOrDash(product);
    final basePrice = formatMoneyBr(product.valorBruto ?? 0);

    if (isPromotion) {
      final promotionPriceLabel = promotionPrice == null
          ? '-'
          : formatMoneyBr(promotionPrice);
      return '$code · $brand · R\$ base $basePrice · R\$ promocao $promotionPriceLabel';
    }

    return '$code · $brand · NCM $ncm · R\$ $basePrice';
  }

  static String buildAvailableProductSubtitle({
    required Produto product,
    required String Function(double value) formatMoneyBr,
  }) {
    final code = _productCodeOrDash(product);
    final brand = _productBrandOrDash(product);
    final ncm = _productNcmOrDash(product);
    final basePrice = formatMoneyBr(product.valorBruto ?? 0);
    return '$code · $brand · NCM $ncm · R\$ $basePrice';
  }

  static String _productCodeOrDash(Produto product) {
    final normalized = product.codigoInterno.trim();
    return normalized.isEmpty ? '-' : normalized;
  }

  static String _productBrandOrDash(Produto product) {
    final normalized = (product.marca ?? '').trim();
    return normalized.isEmpty ? '-' : normalized;
  }

  static String _productNcmOrDash(Produto product) {
    final normalized = (product.ncm ?? '').trim();
    return normalized.isEmpty ? '-' : normalized;
  }
}
