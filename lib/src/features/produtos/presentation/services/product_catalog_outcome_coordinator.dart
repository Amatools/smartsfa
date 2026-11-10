import 'product_catalog_feedback.dart';
import 'product_catalog_status_toggle_coordinator.dart';

class ProductCatalogOutcomeCoordinator {
  const ProductCatalogOutcomeCoordinator();

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
