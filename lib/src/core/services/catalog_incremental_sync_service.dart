import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/firestore/firestore_map_normalizer.dart';
import 'catalog_sync_cursor_store.dart';

enum CatalogSyncModule { clientes, produtos, tabelasPreco, taxRules }

extension CatalogSyncModuleCollectionName on CatalogSyncModule {
  String get collectionName {
    switch (this) {
      case CatalogSyncModule.clientes:
        return 'clientes';
      case CatalogSyncModule.produtos:
        return 'produtos';
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
  });

  final CatalogSyncModule module;
  final int previousCursor;
  final int nextCursor;
  final List<CatalogSyncDeltaItem> items;
  final bool hasMore;
}

class CatalogIncrementalSyncService {
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

    final documents = shouldBootstrap
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
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return 0;
    }

    final previousCursor = await _cursorStore.readCursor(
      tenantId: normalizedTenantId,
      module: module.collectionName,
    );
    final bootstrapComplete = await _cursorStore.isBootstrapComplete(
      tenantId: normalizedTenantId,
      module: module.collectionName,
    );

    final shouldBootstrap = previousCursor == 0 && !bootstrapComplete;
    if (shouldBootstrap) {
      final snapshot = await _firestore
          .collection(module.collectionName)
          .where('tenantId', isEqualTo: normalizedTenantId)
          .get();
      return snapshot.docs.length;
    }

    try {
      final snapshot = await _firestore
          .collection(module.collectionName)
          .where('tenantId', isEqualTo: normalizedTenantId)
          .where('syncVersion', isGreaterThan: previousCursor)
          .get();
      return snapshot.docs.length;
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') {
        rethrow;
      }

      // Fallback when rollout still misses a composite index.
      final snapshot = await _firestore
          .collection(module.collectionName)
          .where('tenantId', isEqualTo: normalizedTenantId)
          .get();
      final docs = snapshot.docs
          .where((doc) {
            final normalized = normalizeFirestoreMap(doc.data());
            final syncVersion = _readInt(normalized['syncVersion']) ?? 0;
            return syncVersion > previousCursor;
          })
          .toList(growable: false);

      return docs.length;
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _fetchInitialBootstrapDocuments({
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

    return docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _fetchIncrementalDocuments({
    required String tenantId,
    required CatalogSyncModule module,
    required int previousCursor,
    required int pageSize,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(module.collectionName)
          .where('tenantId', isEqualTo: tenantId)
          .where('syncVersion', isGreaterThan: previousCursor)
          .orderBy('syncVersion')
          .limit(pageSize)
          .get();
      return snapshot.docs;
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') {
        rethrow;
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

      if (docs.length <= pageSize) {
        return docs;
      }
      return docs.sublist(0, pageSize);
    }
  }
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
