import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import 'product_catalog_source_filter.dart';

class ProductCatalogVisibilityFilterResult {
  const ProductCatalogVisibilityFilterResult({
    required this.effectiveBrandFilter,
    required this.promotionVisibleCount,
    required this.highlightVisibleCount,
    required this.visibleProducts,
  });

  final String effectiveBrandFilter;
  final int promotionVisibleCount;
  final int highlightVisibleCount;
  final List<Produto> visibleProducts;
}

class ProductCatalogVisibilityFilterCoordinator {
  const ProductCatalogVisibilityFilterCoordinator();

  ProductCatalogVisibilityFilterResult resolve({
    required List<Produto> produtos,
    required List<String> availableBrands,
    required String selectedBrandFilter,
    required ProductCatalogSourceFilter selectedSourceFilter,
    required Set<String> promotionProductIds,
    required Set<String> highlightProductIds,
  }) {
    final normalizedSelectedBrand = selectedBrandFilter.trim();
    final effectiveBrandFilter =
      normalizedSelectedBrand.isEmpty || normalizedSelectedBrand == 'todas'
      ? 'todas'
      : normalizedSelectedBrand;

    final filteredProducts = effectiveBrandFilter == 'todas'
        ? produtos
        : produtos
            .where(
              (produto) =>
                  (produto.marca ?? '').trim().toLowerCase() ==
                  effectiveBrandFilter.toLowerCase(),
            )
            .toList(growable: false);

    final visibleByBrand = filteredProducts.where((produto) {
      final hasCode =
          produto.codigoInterno.trim().isNotEmpty ||
          (produto.erpProductId ?? '').trim().isNotEmpty ||
          (produto.codigoFabricante ?? '').trim().isNotEmpty;
      final hasDescription = produto.descricao.trim().isNotEmpty;
      final hasPrice = produto.valorBruto != null;
      final hasImage = (produto.fotoUrl ?? '').trim().isNotEmpty;
      return hasCode || hasDescription || hasPrice || hasImage;
    }).toList(growable: false);

    final promotionVisibleByBrand = visibleByBrand
        .where((produto) =>
            produto.status == ProductStatus.active &&
            promotionProductIds.contains(produto.id))
        .toList(growable: false);
    final highlightVisibleByBrand = visibleByBrand
        .where((produto) =>
            produto.status == ProductStatus.active &&
            highlightProductIds.contains(produto.id))
        .toList(growable: false);

    final visibleProducts = switch (selectedSourceFilter) {
      ProductCatalogSourceFilter.catalogo => visibleByBrand,
      ProductCatalogSourceFilter.promocoes => promotionVisibleByBrand,
      ProductCatalogSourceFilter.destaques => highlightVisibleByBrand,
    };

    return ProductCatalogVisibilityFilterResult(
      effectiveBrandFilter: effectiveBrandFilter,
      promotionVisibleCount: promotionVisibleByBrand.length,
      highlightVisibleCount: highlightVisibleByBrand.length,
      visibleProducts: visibleProducts,
    );
  }
}
