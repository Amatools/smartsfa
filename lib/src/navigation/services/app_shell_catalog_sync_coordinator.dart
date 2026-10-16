import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/catalog_incremental_sync_service.dart';
import '../../core/services/catalog_snapshot_store.dart';

class CatalogWarmupSummary {
  const CatalogWarmupSummary({
    required this.modulesProcessed,
    required this.pagesPulled,
    required this.itemsPulled,
    required this.queryOperations,
    required this.estimatedDocumentReads,
    required this.fallbackFullReads,
  });

  const CatalogWarmupSummary.empty()
    : modulesProcessed = 0,
      pagesPulled = 0,
      itemsPulled = 0,
      queryOperations = 0,
      estimatedDocumentReads = 0,
      fallbackFullReads = 0;

  final int modulesProcessed;
  final int pagesPulled;
  final int itemsPulled;
  final int queryOperations;
  final int estimatedDocumentReads;
  final int fallbackFullReads;
}

class AppShellCatalogSyncCoordinator {
  const AppShellCatalogSyncCoordinator();

  Future<CatalogWarmupSummary> warmupCatalogs({
    required FirebaseFirestore firestore,
    required String tenantId,
    int pageSize = 500,
    int? maxPagesPerModule = 10,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const CatalogWarmupSummary.empty();
    }

    final syncService = CatalogIncrementalSyncService(firestore);
    final snapshotStore = CatalogSnapshotStore();
    final safePageSize = pageSize < 1 ? 1 : pageSize;
    final safeMaxPages = maxPagesPerModule == null
        ? null
        : (maxPagesPerModule < 1 ? 1 : maxPagesPerModule);
    var modulesProcessed = 0;
    var pagesPulled = 0;
    var itemsPulled = 0;
    var queryOperations = 0;
    var estimatedDocumentReads = 0;
    var fallbackFullReads = 0;

    for (final module in CatalogSyncModule.values) {
      modulesProcessed++;
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
        pagesPulled++;
        itemsPulled += result.items.length;
        queryOperations += result.queryOperations;
        estimatedDocumentReads += result.estimatedDocumentReads;
        fallbackFullReads += result.fallbackFullReads;

        if (!result.hasMore || result.items.isEmpty) {
          break;
        }
      }
    }

    return CatalogWarmupSummary(
      modulesProcessed: modulesProcessed,
      pagesPulled: pagesPulled,
      itemsPulled: itemsPulled,
      queryOperations: queryOperations,
      estimatedDocumentReads: estimatedDocumentReads,
      fallbackFullReads: fallbackFullReads,
    );
  }
}
