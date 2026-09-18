import '../../../../core/models/produto.dart';

class ProductCatalogVisibilityFilterResult {
  const ProductCatalogVisibilityFilterResult({
    required this.effectiveBrandFilter,
    required this.visibleProducts,
  });

  final String effectiveBrandFilter;
  final List<Produto> visibleProducts;
}

class ProductCatalogVisibilityFilterCoordinator {
  const ProductCatalogVisibilityFilterCoordinator();

  ProductCatalogVisibilityFilterResult resolve({
    required List<Produto> produtos,
    required List<String> availableBrands,
    required String selectedBrandFilter,
  }) {
    final effectiveBrandFilter =
        (selectedBrandFilter == 'todas' || availableBrands.contains(selectedBrandFilter))
        ? selectedBrandFilter
        : 'todas';

    final filteredProducts = effectiveBrandFilter == 'todas'
        ? produtos
        : produtos
            .where(
              (produto) =>
                  (produto.marca ?? '').trim().toLowerCase() ==
                  effectiveBrandFilter.toLowerCase(),
            )
            .toList(growable: false);

    final visibleProducts = filteredProducts.where((produto) {
      final hasCode = (produto.codigoFabricante ?? '').trim().isNotEmpty;
      final hasDescription = produto.descricao.trim().isNotEmpty;
      final hasPrice = produto.valorBruto != null;
      final hasImage = (produto.fotoUrl ?? '').trim().isNotEmpty;
      return hasCode || hasDescription || hasPrice || hasImage;
    }).toList(growable: false);

    return ProductCatalogVisibilityFilterResult(
      effectiveBrandFilter: effectiveBrandFilter,
      visibleProducts: visibleProducts,
    );
  }
}
