import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/firestore/firestore_map_normalizer.dart';
import 'catalog_sync_cursor_store.dart';

enum CatalogSyncModule { clientes, produtos, pedidos, tabelasPreco, taxRules }

extension CatalogSyncModuleCollectionName on CatalogSyncModule {
  String get collectionName {
    switch (this) {
      case CatalogSyncModule.clientes:
        return 'clientes';
      case CatalogSyncModule.produtos:
        return 'produtos';
      case CatalogSyncModule.pedidos:
        return 'pedidos';
      case CatalogSyncModule.tabelasPreco:
        return 'tabelas_preco';
      case CatalogSyncModule.taxRules:
        return 'tax_rules';
    }
  }
}

class CatalogSyncDeltaItem {
  const CatalogSyncDeltaItem({
    required this.id,
    required this.syncVersion,
    required this.payload,
    this.deletedAt,
  });

  final String id;
  final int syncVersion;
  final DateTime? deletedAt;
  final Map<String, Object?> payload;

  bool get isDeleted => deletedAt != null;
}

class CatalogSyncPullResult {
  const CatalogSyncPullResult({
    required this.module,
    required this.previousCursor,
    required this.nextCursor,
    required this.items,
    required this.hasMore,
    this.estimatedDocumentReads = 0,
    this.queryOperations = 0,
    this.fallbackFullReads = 0,
  });

  final CatalogSyncModule module;
  final int previousCursor;
  final int nextCursor;
  final List<CatalogSyncDeltaItem> items;
  final bool hasMore;
  final int estimatedDocumentReads;
  final int queryOperations;
  final int fallbackFullReads;

  bool get usedFallbackFullRead => fallbackFullReads > 0;
}

class CatalogSyncPendingCountResult {
  const CatalogSyncPendingCountResult({
    required this.pendingCount,
    required this.estimatedDocumentReads,
    required this.queryOperations,
    required this.fromCache,
    required this.fallbackFullReads,
  });

  final int pendingCount;
  final int estimatedDocumentReads;
  final int queryOperations;
  final bool fromCache;
  final int fallbackFullReads;
}

class CatalogIncrementalSyncService {
  static const Duration _missingIndexRetryWindow = Duration(minutes: 15);
  static const Duration _fullFallbackCooldown = Duration(hours: 2);
  static final Map<String, DateTime> _retryAfterByModule = <String, DateTime>{};
  static final Map<String, DateTime> _lastFullFallbackByModule =
      <String, DateTime>{};
  static final Map<String, int> _lastKnownPendingByModule = <String, int>{};

  CatalogIncrementalSyncService(
    this._firestore, {
    CatalogSyncCursorStore? cursorStore,
  }) : _cursorStore = cursorStore ?? CatalogSyncCursorStore();

  final FirebaseFirestore _firestore;
  final CatalogSyncCursorStore _cursorStore;

  Future<CatalogSyncPullResult> pullDelta({
    required String tenantId,
    required CatalogSyncModule module,
    int pageSize = 500,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return CatalogSyncPullResult(
        module: module,
        previousCursor: 0,
        nextCursor: 0,
        items: const <CatalogSyncDeltaItem>[],
        hasMore: false,
      );
    }

    final safePageSize = pageSize < 1 ? 1 : pageSize;
    final previousCursor = await _cursorStore.readCursor(
      tenantId: normalizedTenantId,
      module: module.collectionName,
    );
    final bootstrapComplete = await _cursorStore.isBootstrapComplete(
      tenantId: normalizedTenantId,
      module: module.collectionName,
    );

    final shouldBootstrap = previousCursor == 0 && !bootstrapComplete;

    final fetchResult = shouldBootstrap
        ? await _fetchInitialBootstrapDocuments(
            tenantId: normalizedTenantId,
            module: module,
          )
        : await _fetchIncrementalDocuments(
            tenantId: normalizedTenantId,
            module: module,
            previousCursor: previousCursor,
            pageSize: safePageSize,
          );
    final documents = fetchResult.documents;

    final items = <CatalogSyncDeltaItem>[];
    var nextCursor = previousCursor;

    for (final doc in documents) {
      final normalized = normalizeFirestoreMap(doc.data());
      normalized.putIfAbsent('id', () => doc.id);

      final syncVersion = _readInt(normalized['syncVersion']) ?? 0;
      if (!shouldBootstrap && syncVersion <= previousCursor) {
        continue;
      }

      final deletedAt = _readDateTime(normalized['deletedAt']);
      items.add(
        CatalogSyncDeltaItem(
          id: doc.id,
          syncVersion: syncVersion,
          deletedAt: deletedAt,
          payload: normalized,
        ),
      );

      if (syncVersion > nextCursor) {
        nextCursor = syncVersion;
      }
    }

    items.sort((left, right) => left.syncVersion.compareTo(right.syncVersion));

    if (nextCursor > previousCursor) {
      await _cursorStore.writeCursor(
        tenantId: normalizedTenantId,
        module: module.collectionName,
        cursor: nextCursor,
      );
    }

    if (shouldBootstrap) {
      await _cursorStore.markBootstrapComplete(
        tenantId: normalizedTenantId,
        module: module.collectionName,
      );
    }

    return CatalogSyncPullResult(
      module: module,
      previousCursor: previousCursor,
      nextCursor: nextCursor,
      items: items,
      hasMore: shouldBootstrap ? false : items.length >= safePageSize,
      estimatedDocumentReads: fetchResult.estimatedDocumentReads,
      queryOperations: fetchResult.queryOperations,
      fallbackFullReads: fetchResult.fallbackFullReads,
    );
  }

  Future<void> resetModuleCursor({
    required String tenantId,
    required CatalogSyncModule module,
  }) {
    return _cursorStore.clearCursor(
      tenantId: tenantId,
      module: module.collectionName,
    );
  }

  Future<int> countPendingCloudToDeviceDelta({
    required String tenantId,
    required CatalogSyncModule module,
  }) async {
    final result = await countPendingCloudToDeviceDeltaDetailed(
      tenantId: tenantId,
      module: module,
    );
    return result.pendingCount;
  }

  Future<CatalogSyncPendingCountResult> countPendingCloudToDeviceDeltaDetailed({
    required String tenantId,
    required CatalogSyncModule module,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const CatalogSyncPendingCountResult(
        pendingCount: 0,
        estimatedDocumentReads: 0,
        queryOperations: 0,
        fromCache: false,
        fallbackFullReads: 0,
      );
    }

    final previousCursor = await _cursorStore.readCursor(
      tenantId: normalizedTenantId,
      module: module.collectionName,
    );
    final bootstrapComplete = await _cursorStore.isBootstrapComplete(
      tenantId: normalizedTenantId,
      module: module.collectionName,
    );
    final moduleKey = _moduleKey(normalizedTenantId, module);

    final shouldBootstrap = previousCursor == 0 && !bootstrapComplete;
    if (shouldBootstrap) {
      final snapshot = await _firestore
          .collection(module.collectionName)
          .where('tenantId', isEqualTo: normalizedTenantId)
          .get();
      _markDeltaIndexHealthy(moduleKey);
      _lastKnownPendingByModule[moduleKey] = snapshot.docs.length;
      return CatalogSyncPendingCountResult(
        pendingCount: snapshot.docs.length,
        estimatedDocumentReads: snapshot.docs.length,
        queryOperations: 1,
        fromCache: false,
        fallbackFullReads: 0,
      );
    }

    if (_shouldSkipIndexedDeltaQuery(moduleKey)) {
      return CatalogSyncPendingCountResult(
        pendingCount: _lastKnownPendingByModule[moduleKey] ?? 0,
        estimatedDocumentReads: 0,
        queryOperations: 0,
        fromCache: true,
        fallbackFullReads: 0,
      );
    }

    try {
      final snapshot = await _firestore
          .collection(module.collectionName)
          .where('tenantId', isEqualTo: normalizedTenantId)
          .where('syncVersion', isGreaterThan: previousCursor)
          .get();
      _markDeltaIndexHealthy(moduleKey);
      _lastKnownPendingByModule[moduleKey] = snapshot.docs.length;
      return CatalogSyncPendingCountResult(
        pendingCount: snapshot.docs.length,
        estimatedDocumentReads: snapshot.docs.length,
        queryOperations: 1,
        fromCache: false,
        fallbackFullReads: 0,
      );
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') {
        rethrow;
      }

      _markDeltaIndexUnavailable(moduleKey);
      return CatalogSyncPendingCountResult(
        pendingCount: _lastKnownPendingByModule[moduleKey] ?? 0,
        estimatedDocumentReads: 0,
        queryOperations: 1,
        fromCache: true,
        fallbackFullReads: 0,
      );
    }
  }

  Future<_CatalogFetchResult> _fetchInitialBootstrapDocuments({
    required String tenantId,
    required CatalogSyncModule module,
  }) async {
    final snapshot = await _firestore
        .collection(module.collectionName)
        .where('tenantId', isEqualTo: tenantId)
        .get();

    final docs = snapshot.docs.toList();
    docs.sort((left, right) {
      final leftMap = normalizeFirestoreMap(left.data());
      final rightMap = normalizeFirestoreMap(right.data());

      final leftVersion = _readInt(leftMap['syncVersion']) ?? 0;
      final rightVersion = _readInt(rightMap['syncVersion']) ?? 0;
      if (leftVersion != rightVersion) {
        return leftVersion.compareTo(rightVersion);
      }

      final leftUpdated = _readDateTime(leftMap['updatedAt']);
      final rightUpdated = _readDateTime(rightMap['updatedAt']);
      if (leftUpdated != null && rightUpdated != null) {
        final compare = leftUpdated.compareTo(rightUpdated);
        if (compare != 0) {
          return compare;
        }
      }

      return left.id.compareTo(right.id);
    });

    return _CatalogFetchResult(
      documents: docs,
      estimatedDocumentReads: snapshot.docs.length,
      queryOperations: 1,
      fallbackFullReads: 0,
    );
  }

  Future<_CatalogFetchResult> _fetchIncrementalDocuments({
    required String tenantId,
    required CatalogSyncModule module,
    required int previousCursor,
    required int pageSize,
  }) async {
    final moduleKey = _moduleKey(tenantId, module);
    if (_shouldSkipIndexedDeltaQuery(moduleKey)) {
      return const _CatalogFetchResult(
        documents: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
        estimatedDocumentReads: 0,
        queryOperations: 0,
        fallbackFullReads: 0,
      );
    }

    try {
      final snapshot = await _firestore
          .collection(module.collectionName)
          .where('tenantId', isEqualTo: tenantId)
          .where('syncVersion', isGreaterThan: previousCursor)
          .orderBy('syncVersion')
          .limit(pageSize)
          .get();
      _markDeltaIndexHealthy(moduleKey);
      return _CatalogFetchResult(
        documents: snapshot.docs,
        estimatedDocumentReads: snapshot.docs.length,
        queryOperations: 1,
        fallbackFullReads: 0,
      );
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') {
        rethrow;
      }

      _markDeltaIndexUnavailable(moduleKey);
      if (!_canRunExpensiveFallback(moduleKey)) {
        return const _CatalogFetchResult(
          documents: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
          estimatedDocumentReads: 0,
          queryOperations: 1,
          fallbackFullReads: 0,
        );
      }

      // Fallback path when index is missing during rollout.
      final snapshot = await _firestore
          .collection(module.collectionName)
          .where('tenantId', isEqualTo: tenantId)
          .get();
      final docs = snapshot.docs.where((doc) {
        final normalized = normalizeFirestoreMap(doc.data());
        final syncVersion = _readInt(normalized['syncVersion']) ?? 0;
        return syncVersion > previousCursor;
      }).toList();

      docs.sort((left, right) {
        final leftVersion =
            _readInt(normalizeFirestoreMap(left.data())['syncVersion']) ?? 0;
        final rightVersion =
            _readInt(normalizeFirestoreMap(right.data())['syncVersion']) ?? 0;
        return leftVersion.compareTo(rightVersion);
      });

      final normalizedDocs = docs.length <= pageSize
          ? docs
          : docs.sublist(0, pageSize);
      _lastFullFallbackByModule[moduleKey] = DateTime.now();

      if (docs.length <= pageSize) {
        return _CatalogFetchResult(
          documents: normalizedDocs,
          estimatedDocumentReads: snapshot.docs.length,
          queryOperations: 2,
          fallbackFullReads: 1,
        );
      }

      return _CatalogFetchResult(
        documents: normalizedDocs,
        estimatedDocumentReads: snapshot.docs.length,
        queryOperations: 2,
        fallbackFullReads: 1,
      );
    }
  }

  static String _moduleKey(String tenantId, CatalogSyncModule module) {
    return '${tenantId.trim()}::${module.collectionName}';
  }

  static bool _shouldSkipIndexedDeltaQuery(String moduleKey) {
    final retryAfter = _retryAfterByModule[moduleKey];
    if (retryAfter == null) {
      return false;
    }
    return DateTime.now().isBefore(retryAfter);
  }

  static void _markDeltaIndexUnavailable(String moduleKey) {
    _retryAfterByModule[moduleKey] = DateTime.now().add(
      _missingIndexRetryWindow,
    );
  }

  static void _markDeltaIndexHealthy(String moduleKey) {
    _retryAfterByModule.remove(moduleKey);
  }

  static bool _canRunExpensiveFallback(String moduleKey) {
    final lastFallbackAt = _lastFullFallbackByModule[moduleKey];
    if (lastFallbackAt == null) {
      return true;
    }

    return DateTime.now().difference(lastFallbackAt) >= _fullFallbackCooldown;
  }
}

class _CatalogFetchResult {
  const _CatalogFetchResult({
    required this.documents,
    required this.estimatedDocumentReads,
    required this.queryOperations,
    required this.fallbackFullReads,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> documents;
  final int estimatedDocumentReads;
  final int queryOperations;
  final int fallbackFullReads;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is double) {
    return value.round();
  }

  if (value is String) {
    return int.tryParse(value.trim());
  }

  return null;
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }

  if (value is String) {
    return DateTime.tryParse(value);
  }

  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  return null;
}
