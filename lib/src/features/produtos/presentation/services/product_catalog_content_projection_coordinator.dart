import '../../../../core/models/produto.dart';
import 'product_catalog_brand_options_resolver.dart';
import 'product_catalog_editor_view_state_coordinator.dart';
import 'product_catalog_visibility_filter_coordinator.dart';

class ProductCatalogContentProjection {
  const ProductCatalogContentProjection({
    required this.availableBrands,
    required this.effectiveBrandFilter,
    required this.visibleProducts,
    required this.editorViewState,
  });

  final List<String> availableBrands;
  final String effectiveBrandFilter;
  final List<Produto> visibleProducts;
  final ProductCatalogEditorViewState editorViewState;

  bool get creatingNewProduct => editorViewState.creatingNewProduct;
}

class ProductCatalogContentProjectionCoordinator {
  const ProductCatalogContentProjectionCoordinator({
    this.brandOptionsResolver = const ProductCatalogBrandOptionsResolver(),
    this.visibilityFilterCoordinator =
        const ProductCatalogVisibilityFilterCoordinator(),
    this.editorViewStateCoordinator =
        const ProductCatalogEditorViewStateCoordinator(),
  });

  final ProductCatalogBrandOptionsResolver brandOptionsResolver;
  final ProductCatalogVisibilityFilterCoordinator visibilityFilterCoordinator;
  final ProductCatalogEditorViewStateCoordinator editorViewStateCoordinator;

  ProductCatalogContentProjection resolve({
    required List<Produto> produtos,
    required String selectedBrandFilter,
    required bool editorOpen,
    required Produto? editingProduct,
  }) {
    final availableBrands = brandOptionsResolver.resolve(produtos);
    final filterResult = visibilityFilterCoordinator.resolve(
      produtos: produtos,
      availableBrands: availableBrands,
      selectedBrandFilter: selectedBrandFilter,
    );
    final editorViewState = editorViewStateCoordinator.resolve(
      editorOpen: editorOpen,
      editingProduct: editingProduct,
    );

    return ProductCatalogContentProjection(
      availableBrands: availableBrands,
      effectiveBrandFilter: filterResult.effectiveBrandFilter,
      visibleProducts: filterResult.visibleProducts,
      editorViewState: editorViewState,
    );
  }
}
