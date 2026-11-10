import 'product_catalog_editor_state_coordinator.dart';
import 'product_catalog_page_view_state.dart';
import 'product_catalog_source_filter.dart';

class ProductCatalogPageStateCoordinator {
  const ProductCatalogPageStateCoordinator();

  ProductCatalogPageViewState applyEditorState({
    required ProductCatalogPageViewState currentState,
    required ProductCatalogEditorState editorState,
  }) {
    return currentState.withEditorState(
      editingProduto: editorState.editingProduto,
      editorOpen: editorState.editorOpen,
      brandFilter: editorState.brandFilter,
    );
  }

  ProductCatalogPageViewState applyBrandFilter({
    required ProductCatalogPageViewState currentState,
    required String brandFilter,
  }) {
    return currentState.withBrandFilter(brandFilter);
  }

  ProductCatalogPageViewState applySourceFilter({
    required ProductCatalogPageViewState currentState,
    required ProductCatalogSourceFilter sourceFilter,
  }) {
    return currentState.withSourceFilter(sourceFilter);
  }

  ProductCatalogPageViewState addUpdatingStatusProductId({
    required ProductCatalogPageViewState currentState,
    required String productId,
  }) {
    return currentState.withAddedUpdatingStatusProductId(productId);
  }

  ProductCatalogPageViewState removeUpdatingStatusProductId({
    required ProductCatalogPageViewState currentState,
    required String productId,
  }) {
    return currentState.withRemovedUpdatingStatusProductId(productId);
  }
}
