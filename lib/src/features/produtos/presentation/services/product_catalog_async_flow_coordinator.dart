import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';
import 'product_catalog_outcome_coordinator.dart';
import 'product_catalog_status_toggle_coordinator.dart';

class ProductCatalogAsyncFlowCoordinator {
  const ProductCatalogAsyncFlowCoordinator({
    this.statusToggleCoordinator =
        const ProductCatalogStatusToggleCoordinator(),
    this.outcomeCoordinator = const ProductCatalogOutcomeCoordinator(),
  });

  final ProductCatalogStatusToggleCoordinator statusToggleCoordinator;
  final ProductCatalogOutcomeCoordinator outcomeCoordinator;

  Future<String?> toggleProductStatus({
    required Produto produto,
    required Set<String> updatingStatusProductIds,
    required ProdutoRepository repository,
    required void Function(String productId) onToggleStarted,
    required void Function(String productId) onToggleFinished,
    required Object Function(Object? error) resolveError,
  }) async {
    if (updatingStatusProductIds.contains(produto.id)) {
      return null;
    }

    onToggleStarted(produto.id);
    try {
      final result = await statusToggleCoordinator.executeToggle(
        produto: produto,
        repository: repository,
      );

      return outcomeCoordinator.resolveStatusToggleFeedback(
        result: result,
        resolveError: resolveError,
      );
    } finally {
      onToggleFinished(produto.id);
    }
  }
}
