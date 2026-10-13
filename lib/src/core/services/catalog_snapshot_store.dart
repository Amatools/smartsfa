import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_incremental_sync_service.dart';

class CatalogSnapshotStore {
  static const String _key = 'smart_sfa_catalog_snapshot_v1';

  Future<List<Map<String, Object?>>> readAll({
    required String tenantId,
    required CatalogSyncModule module,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const <Map<String, Object?>>[];
    }

    final snapshot = await _readSnapshot();
    final moduleMap = _readModuleMap(
      snapshot[_composeKey(normalizedTenantId, module.collectionName)],
    );

    return moduleMap.values.map((item) {
      return Map<String, Object?>.from(item);
    }).toList(growable: false);
  }

  Future<void> applyDelta({
    required String tenantId,
    required CatalogSyncModule module,
    required List<CatalogSyncDeltaItem> items,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty || items.isEmpty) {
      return;
    }

    final snapshot = await _readSnapshot();
    final storageKey = _composeKey(normalizedTenantId, module.collectionName);
    final moduleMap = _readModuleMap(snapshot[storageKey]);

    for (final item in items) {
      if (item.isDeleted) {
        moduleMap.remove(item.id);
        continue;
      }

      moduleMap[item.id] = Map<String, Object?>.from(item.payload);
    }

    snapshot[storageKey] = moduleMap;
    await _writeSnapshot(snapshot);
  }

  Future<void> clearModule({
    required String tenantId,
    required CatalogSyncModule module,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return;
    }

    final snapshot = await _readSnapshot();
    snapshot.remove(_composeKey(normalizedTenantId, module.collectionName));
    await _writeSnapshot(snapshot);
  }

  Future<Map<String, Object?>> _readSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) {
      return <String, Object?>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return <String, Object?>{};
      }
      return Map<String, Object?>.from(decoded);
    } catch (_) {
      return <String, Object?>{};
    }
  }

  Future<void> _writeSnapshot(Map<String, Object?> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(value));
  }

  static Map<String, Map<String, Object?>> _readModuleMap(Object? rawValue) {
    if (rawValue is! Map) {
      return <String, Map<String, Object?>>{};
    }

    final output = <String, Map<String, Object?>>{};
    rawValue.forEach((key, value) {
      if (value is Map) {
        output[key.toString()] = Map<String, Object?>.from(
          value.map((itemKey, itemValue) {
            return MapEntry(itemKey.toString(), itemValue);
          }),
        );
      }
    });
    return output;
  }

  static String _composeKey(String tenantId, String module) {
    return '$tenantId::$module';
  }
}
