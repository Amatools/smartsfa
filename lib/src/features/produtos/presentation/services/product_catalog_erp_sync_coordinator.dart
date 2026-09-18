enum ProductCatalogErpSyncExecutionResultType {
  updated,
  cancelled,
  failed,
}

class ProductCatalogErpSyncExecutionResult {
  const ProductCatalogErpSyncExecutionResult({
    required this.type,
    this.error,
  });

  final ProductCatalogErpSyncExecutionResultType type;
  final Object? error;
}

class ProductCatalogErpSyncCoordinator {
  const ProductCatalogErpSyncCoordinator();

  Future<ProductCatalogErpSyncExecutionResult> execute({
    required bool enabled,
    required String tenantId,
    required Future<bool> Function() confirmDisable,
    required Future<void> Function({required String tenantId, required bool enabled})
        persistSyncEnabled,
    required void Function(bool isLoading) onLoadingChanged,
  }) async {
    if (!enabled) {
      final proceed = await confirmDisable();
      if (!proceed) {
        return const ProductCatalogErpSyncExecutionResult(
          type: ProductCatalogErpSyncExecutionResultType.cancelled,
        );
      }
    }

    onLoadingChanged(true);
    try {
      await persistSyncEnabled(
        tenantId: tenantId,
        enabled: enabled,
      );
      return const ProductCatalogErpSyncExecutionResult(
        type: ProductCatalogErpSyncExecutionResultType.updated,
      );
    } catch (error) {
      return ProductCatalogErpSyncExecutionResult(
        type: ProductCatalogErpSyncExecutionResultType.failed,
        error: error,
      );
    } finally {
      onLoadingChanged(false);
    }
  }
}
