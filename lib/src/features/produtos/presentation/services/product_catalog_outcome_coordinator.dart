import 'product_catalog_erp_sync_coordinator.dart';
import 'product_catalog_feedback.dart';
import 'product_catalog_status_toggle_coordinator.dart';

class ProductCatalogOutcomeCoordinator {
  const ProductCatalogOutcomeCoordinator();

  String? resolveErpSyncFeedback({
    required ProductCatalogErpSyncExecutionResult result,
    required bool enabled,
    required Object Function(Object? error) resolveError,
  }) {
    switch (result.type) {
      case ProductCatalogErpSyncExecutionResultType.cancelled:
        return null;
      case ProductCatalogErpSyncExecutionResultType.failed:
        return ProductCatalogFeedback.erpSyncUpdateFailureMessage(
          resolveError(result.error),
        );
      case ProductCatalogErpSyncExecutionResultType.updated:
        return ProductCatalogFeedback.erpSyncUpdatedMessage(enabled: enabled);
    }
  }

  String resolveStatusToggleFeedback({
    required ProductCatalogStatusToggleExecutionResult result,
    required Object Function(Object? error) resolveError,
  }) {
    if (result.type == ProductCatalogStatusToggleExecutionResultType.failed) {
      return ProductCatalogFeedback.productStatusUpdateFailureMessage(
        resolveError(result.error),
      );
    }

    final nextStatus = result.nextStatus;
    if (nextStatus == null) {
      return ProductCatalogFeedback.productStatusUpdateFailureMessage(
        resolveError(null),
      );
    }

    return ProductCatalogFeedback.productStatusUpdatedMessage(nextStatus);
  }
}
