import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';

enum ProductCatalogStatusToggleExecutionResultType {
  updated,
  failed,
}

class ProductCatalogStatusToggleExecutionResult {
  const ProductCatalogStatusToggleExecutionResult({
    required this.type,
    this.nextStatus,
    this.error,
  });

  final ProductCatalogStatusToggleExecutionResultType type;
  final ProductStatus? nextStatus;
  final Object? error;
}

class ProductCatalogStatusToggleCoordinator {
  const ProductCatalogStatusToggleCoordinator();

  Future<ProductCatalogStatusToggleExecutionResult> executeToggle({
    required Produto produto,
    required ProdutoRepository repository,
  }) async {
    final nextStatus = produto.status == ProductStatus.active
        ? ProductStatus.inactive
        : ProductStatus.active;

    try {
      await repository.save(
        produto.copyWith(
          status: nextStatus,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      return ProductCatalogStatusToggleExecutionResult(
        type: ProductCatalogStatusToggleExecutionResultType.updated,
        nextStatus: nextStatus,
      );
    } catch (error) {
      return ProductCatalogStatusToggleExecutionResult(
        type: ProductCatalogStatusToggleExecutionResultType.failed,
        error: error,
      );
    }
  }
}
