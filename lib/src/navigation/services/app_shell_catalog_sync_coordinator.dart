import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/catalog_incremental_sync_service.dart';
import '../../core/services/catalog_snapshot_store.dart';

class AppShellCatalogSyncCoordinator {
  const AppShellCatalogSyncCoordinator();

  Future<void> warmupCatalogs({
    required FirebaseFirestore firestore,
    required String tenantId,
    int pageSize = 500,
    int? maxPagesPerModule = 10,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return;
    }

    final syncService = CatalogIncrementalSyncService(firestore);
    final snapshotStore = CatalogSnapshotStore();
    final safePageSize = pageSize < 1 ? 1 : pageSize;
    final safeMaxPages = maxPagesPerModule == null
        ? null
        : (maxPagesPerModule < 1 ? 1 : maxPagesPerModule);

    for (final module in CatalogSyncModule.values) {
      var pages = 0;
      while (true) {
        if (safeMaxPages != null && pages >= safeMaxPages) {
          break;
        }

        final result = await syncService.pullDelta(
          tenantId: normalizedTenantId,
          module: module,
          pageSize: safePageSize,
        );
        await snapshotStore.applyDelta(
          tenantId: normalizedTenantId,
          module: module,
          items: result.items,
        );
        pages++;

        if (!result.hasMore || result.items.isEmpty) {
          break;
        }
      }
    }
  }
}
