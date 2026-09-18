import 'package:flutter/widgets.dart';

class ProductCatalogBrandFilterSyncCoordinator {
  const ProductCatalogBrandFilterSyncCoordinator();

  void syncAfterFrameIfNeeded({
    required String currentBrandFilter,
    required String effectiveBrandFilter,
    required WidgetsBinding widgetsBinding,
    required bool Function() isMounted,
    required void Function(String syncedBrandFilter) onSync,
  }) {
    if (currentBrandFilter == effectiveBrandFilter) {
      return;
    }

    widgetsBinding.addPostFrameCallback((_) {
      if (!isMounted()) {
        return;
      }
      onSync(effectiveBrandFilter);
    });
  }
}
