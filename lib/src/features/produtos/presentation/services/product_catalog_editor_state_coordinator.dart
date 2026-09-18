import '../../../../core/models/produto.dart';

class ProductCatalogEditorState {
  const ProductCatalogEditorState({
    required this.editingProduto,
    required this.editorOpen,
    required this.brandFilter,
  });

  final Produto? editingProduto;
  final bool editorOpen;
  final String brandFilter;
}

class ProductCatalogEditorStateCoordinator {
  const ProductCatalogEditorStateCoordinator();

  ProductCatalogEditorState openEditor({
    required Produto? produto,
    required String currentBrandFilter,
  }) {
    return ProductCatalogEditorState(
      editingProduto: produto,
      editorOpen: true,
      brandFilter: currentBrandFilter,
    );
  }

  ProductCatalogEditorState closeEditor({
    required String currentBrandFilter,
  }) {
    return ProductCatalogEditorState(
      editingProduto: null,
      editorOpen: false,
      brandFilter: currentBrandFilter,
    );
  }

  ProductCatalogEditorState afterSave() {
    return const ProductCatalogEditorState(
      editingProduto: null,
      editorOpen: false,
      brandFilter: 'todas',
    );
  }

  ProductCatalogEditorState afterDelete({
    required String currentBrandFilter,
  }) {
    return ProductCatalogEditorState(
      editingProduto: null,
      editorOpen: false,
      brandFilter: currentBrandFilter,
    );
  }
}
