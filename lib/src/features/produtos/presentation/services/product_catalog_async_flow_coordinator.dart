import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';
import 'product_catalog_erp_disable_flow_coordinator.dart';
import 'product_catalog_erp_products_deactivation_coordinator.dart';
import 'product_catalog_erp_sync_coordinator.dart';
import 'product_catalog_outcome_coordinator.dart';
import 'product_catalog_status_toggle_coordinator.dart';

class ProductCatalogAsyncFlowCoordinator {
  const ProductCatalogAsyncFlowCoordinator({
    this.erpDisableFlowCoordinator =
        const ProductCatalogErpDisableFlowCoordinator(),
    this.erpSyncCoordinator = const ProductCatalogErpSyncCoordinator(),
    this.statusToggleCoordinator =
        const ProductCatalogStatusToggleCoordinator(),
    this.outcomeCoordinator = const ProductCatalogOutcomeCoordinator(),
  });

  final ProductCatalogErpDisableFlowCoordinator erpDisableFlowCoordinator;
  final ProductCatalogErpSyncCoordinator erpSyncCoordinator;
  final ProductCatalogStatusToggleCoordinator statusToggleCoordinator;
  final ProductCatalogOutcomeCoordinator outcomeCoordinator;

  Future<List<String>> updateErpSync({
    required bool enabled,
    required String tenantId,
    required Future<ProductCatalogErpDisableSelection?> Function()
    requestDisableSelection,
    required Future<ProductCatalogErpProductsDeactivationResult> Function()
    deactivateErpProducts,
    required Future<void> Function({
      required String tenantId,
      required bool enabled,
    })
    persistSyncEnabled,
    required void Function(bool isLoading) onLoadingChanged,
    required Object Function(Object? error) resolveError,
  }) async {
    final feedbackMessages = <String>[];

    Future<bool> confirmDisable() async {
      return true;
    }

    if (!enabled) {
      final disableFlowResult = await erpDisableFlowCoordinator.execute(
        requestSelection: requestDisableSelection,
        deactivateErpProducts: deactivateErpProducts,
      );
      if (!disableFlowResult.shouldProceed) {
        return feedbackMessages;
      }

      final disableFeedback = disableFlowResult.feedbackMessage;
      if (disableFeedback != null) {
        feedbackMessages.add(disableFeedback);
      }
    }

    final result = await erpSyncCoordinator.execute(
      enabled: enabled,
      tenantId: tenantId,
      confirmDisable: confirmDisable,
      persistSyncEnabled: persistSyncEnabled,
      onLoadingChanged: onLoadingChanged,
    );

    final syncFeedback = outcomeCoordinator.resolveErpSyncFeedback(
      result: result,
      enabled: enabled,
      resolveError: resolveError,
    );
    if (syncFeedback != null) {
      feedbackMessages.add(syncFeedback);
    }

    return feedbackMessages;
  }

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
