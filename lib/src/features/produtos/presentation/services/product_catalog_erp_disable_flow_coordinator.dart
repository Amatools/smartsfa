import 'product_catalog_erp_products_deactivation_coordinator.dart';
import 'product_catalog_feedback.dart';

enum ProductCatalogErpDisableSelection { keepCurrent, deactivateErpProducts }

class ProductCatalogErpDisableFlowResult {
  const ProductCatalogErpDisableFlowResult({
    required this.shouldProceed,
    this.feedbackMessage,
  });

  final bool shouldProceed;
  final String? feedbackMessage;
}

class ProductCatalogErpDisableFlowCoordinator {
  const ProductCatalogErpDisableFlowCoordinator();

  Future<ProductCatalogErpDisableFlowResult> execute({
    required Future<ProductCatalogErpDisableSelection?> Function()
    requestSelection,
    required Future<ProductCatalogErpProductsDeactivationResult> Function()
    deactivateErpProducts,
  }) async {
    final selection = await requestSelection();
    if (selection == null) {
      return const ProductCatalogErpDisableFlowResult(shouldProceed: false);
    }

    if (selection == ProductCatalogErpDisableSelection.keepCurrent) {
      return const ProductCatalogErpDisableFlowResult(shouldProceed: true);
    }

    final deactivationResult = await deactivateErpProducts();
    return ProductCatalogErpDisableFlowResult(
      shouldProceed: true,
      feedbackMessage: ProductCatalogFeedback.erpProductsDeactivatedMessage(
        deactivationResult.updatedCount,
      ),
    );
  }
}
