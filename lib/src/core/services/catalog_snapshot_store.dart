import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_incremental_sync_service.dart';

class CatalogSnapshotStore {
  static const String _key = 'smart_sfa_catalog_snapshot_v1';
  static const int _temporaryImportLimit = 5;
  static const Set<CatalogSyncModule> _temporaryLimitedModules =
      <CatalogSyncModule>{
        CatalogSyncModule.produtos,
        CatalogSyncModule.clientes,
        CatalogSyncModule.tabelasPreco,
      };
  static const Map<CatalogSyncModule, List<String>>
  _temporaryZeroCodeFieldsByModule = <CatalogSyncModule, List<String>>{
    CatalogSyncModule.produtos: <String>[
      'erpProductId',
      'codigoProduto',
      'codigoInterno',
      'codigo',
    ],
    CatalogSyncModule.clientes: <String>[
      'erpPartnerId',
      'codigoParceiro',
      'codigo',
    ],
    CatalogSyncModule.tabelasPreco: <String>[
      'erpPriceTableId',
      'codigoTabela',
      'codigo',
    ],
  };

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

    _applyTemporaryImportPolicy(module: module, moduleMap: moduleMap);

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

  static void _applyTemporaryImportPolicy({
    required CatalogSyncModule module,
    required Map<String, Map<String, Object?>> moduleMap,
  }) {
    if (!_temporaryLimitedModules.contains(module)) {
      return;
    }

    moduleMap.removeWhere(
      (_, payload) => _hasConfiguredZeroCode(module: module, payload: payload),
    );

    if (moduleMap.length <= _temporaryImportLimit) {
      return;
    }

    final entries = moduleMap.entries.toList(growable: false)
      ..sort((left, right) {
        final leftSyncVersion = _readPayloadInt(left.value['syncVersion']) ?? 0;
        final rightSyncVersion =
            _readPayloadInt(right.value['syncVersion']) ?? 0;
        final syncVersionCompare = rightSyncVersion.compareTo(leftSyncVersion);
        if (syncVersionCompare != 0) {
          return syncVersionCompare;
        }

        final leftUpdatedAt = _readPayloadDateTime(left.value['updatedAt']);
        final rightUpdatedAt = _readPayloadDateTime(right.value['updatedAt']);

        if (leftUpdatedAt != null && rightUpdatedAt != null) {
          final updatedCompare = rightUpdatedAt.compareTo(leftUpdatedAt);
          if (updatedCompare != 0) {
            return updatedCompare;
          }
        } else if (leftUpdatedAt != null) {
          return -1;
        } else if (rightUpdatedAt != null) {
          return 1;
        }

        return left.key.compareTo(right.key);
      });

    final limitedEntries = entries.take(_temporaryImportLimit);
    moduleMap.clear();
    for (final entry in limitedEntries) {
      moduleMap[entry.key] = entry.value;
    }
  }

  static bool _hasConfiguredZeroCode({
    required CatalogSyncModule module,
    required Map<String, Object?> payload,
  }) {
    final fields = _temporaryZeroCodeFieldsByModule[module];
    if (fields == null || fields.isEmpty) {
      return false;
    }

    for (final field in fields) {
      if (!payload.containsKey(field)) {
        continue;
      }
      if (_isZeroCodeValue(payload[field])) {
        return true;
      }
    }

    return false;
  }

  static bool _isZeroCodeValue(Object? value) {
    if (value == null) {
      return false;
    }

    if (value is num) {
      return value == 0;
    }

    final text = value.toString().trim();
    if (text.isEmpty) {
      return false;
    }

    final numeric = num.tryParse(text.replaceAll(',', '.'));
    if (numeric != null && numeric == 0) {
      return true;
    }

    return RegExp(r'^0+$').hasMatch(text);
  }

  static int? _readPayloadInt(Object? value) {
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

  static DateTime? _readPayloadDateTime(Object? value) {
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
}
