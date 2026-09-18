import '../../../../core/models/produto.dart';

class ProductCatalogEditorViewState {
  const ProductCatalogEditorViewState({
    required this.editorOpen,
    required this.editingProduct,
    required this.creatingNewProduct,
  });

  final bool editorOpen;
  final Produto? editingProduct;
  final bool creatingNewProduct;

  bool get savingCreatesNewProduct => editingProduct == null;
}

class ProductCatalogEditorViewStateCoordinator {
  const ProductCatalogEditorViewStateCoordinator();

  ProductCatalogEditorViewState resolve({
    required bool editorOpen,
    required Produto? editingProduct,
  }) {
    return ProductCatalogEditorViewState(
      editorOpen: editorOpen,
      editingProduct: editingProduct,
      creatingNewProduct: editorOpen && editingProduct == null,
    );
  }
}
