import '../../../../core/models/produto.dart';
import 'product_catalog_source_filter.dart';

class ProductCatalogPageViewState {
  const ProductCatalogPageViewState({
    required this.updatingStatusProductIds,
    required this.brandFilter,
    required this.sourceFilter,
    required this.editingProduto,
    required this.editorOpen,
  });

  factory ProductCatalogPageViewState.initial({String brandFilter = 'todas'}) {
    return ProductCatalogPageViewState(
      updatingStatusProductIds: <String>{},
      brandFilter: brandFilter,
      sourceFilter: ProductCatalogSourceFilter.catalogo,
      editingProduto: null,
      editorOpen: false,
    );
  }

  final Set<String> updatingStatusProductIds;
  final String brandFilter;
  final ProductCatalogSourceFilter sourceFilter;
  final Produto? editingProduto;
  final bool editorOpen;

  static const Object _noValue = Object();

  ProductCatalogPageViewState copyWith({
    Set<String>? updatingStatusProductIds,
    String? brandFilter,
    ProductCatalogSourceFilter? sourceFilter,
    Object? editingProduto = _noValue,
    bool? editorOpen,
  }) {
    return ProductCatalogPageViewState(
      updatingStatusProductIds:
          updatingStatusProductIds ?? this.updatingStatusProductIds,
      brandFilter: brandFilter ?? this.brandFilter,
      sourceFilter: sourceFilter ?? this.sourceFilter,
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

  ProductCatalogPageViewState withSourceFilter(
    ProductCatalogSourceFilter value,
  ) {
    return copyWith(sourceFilter: value);
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
