import '../../../../core/models/produto.dart';

class ProductCatalogPageViewState {
  const ProductCatalogPageViewState({
    required this.updatingErpSync,
    required this.updatingStatusProductIds,
    required this.brandFilter,
    required this.editingProduto,
    required this.editorOpen,
  });

  factory ProductCatalogPageViewState.initial({String brandFilter = 'todas'}) {
    return ProductCatalogPageViewState(
      updatingErpSync: false,
      updatingStatusProductIds: <String>{},
      brandFilter: brandFilter,
      editingProduto: null,
      editorOpen: false,
    );
  }

  final bool updatingErpSync;
  final Set<String> updatingStatusProductIds;
  final String brandFilter;
  final Produto? editingProduto;
  final bool editorOpen;

  static const Object _noValue = Object();

  ProductCatalogPageViewState copyWith({
    bool? updatingErpSync,
    Set<String>? updatingStatusProductIds,
    String? brandFilter,
    Object? editingProduto = _noValue,
    bool? editorOpen,
  }) {
    return ProductCatalogPageViewState(
      updatingErpSync: updatingErpSync ?? this.updatingErpSync,
      updatingStatusProductIds:
          updatingStatusProductIds ?? this.updatingStatusProductIds,
      brandFilter: brandFilter ?? this.brandFilter,
      editingProduto: identical(editingProduto, _noValue)
          ? this.editingProduto
          : editingProduto as Produto?,
      editorOpen: editorOpen ?? this.editorOpen,
    );
  }

  ProductCatalogPageViewState withEditorState({
    required Produto? editingProduto,
    required bool editorOpen,
    required String brandFilter,
  }) {
    return copyWith(
      editingProduto: editingProduto,
      editorOpen: editorOpen,
      brandFilter: brandFilter,
    );
  }

  ProductCatalogPageViewState withBrandFilter(String value) {
    return copyWith(brandFilter: value);
  }

  ProductCatalogPageViewState withUpdatingErpSync(bool value) {
    return copyWith(updatingErpSync: value);
  }

  ProductCatalogPageViewState withAddedUpdatingStatusProductId(
    String productId,
  ) {
    return copyWith(
      updatingStatusProductIds: <String>{
        ...updatingStatusProductIds,
        productId,
      },
    );
  }

  ProductCatalogPageViewState withRemovedUpdatingStatusProductId(
    String productId,
  ) {
    final ids = <String>{...updatingStatusProductIds};
    ids.remove(productId);
    return copyWith(updatingStatusProductIds: ids);
  }
}
