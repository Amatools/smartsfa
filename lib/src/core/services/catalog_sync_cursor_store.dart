import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CatalogSyncCursorStore {
  static const String _key = 'smart_sfa_catalog_sync_cursors_v1';

  Future<bool> isBootstrapComplete({
    required String tenantId,
    required String module,
  }) async {
    final all = await readAll();
    final normalizedTenantId = tenantId.trim();
    final normalizedModule = module.trim();
    if (normalizedTenantId.isEmpty || normalizedModule.isEmpty) {
      return false;
    }

    return all[_composeBootstrapKey(normalizedTenantId, normalizedModule)] == 1;
  }

  Future<void> markBootstrapComplete({
    required String tenantId,
    required String module,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedModule = module.trim();
    if (normalizedTenantId.isEmpty || normalizedModule.isEmpty) {
      return;
    }

    final all = await readAll();
    all[_composeBootstrapKey(normalizedTenantId, normalizedModule)] = 1;
    await _writeAll(all);
  }

  Future<int> readCursor({
    required String tenantId,
    required String module,
  }) async {
    final all = await readAll();
    final normalizedTenantId = tenantId.trim();
    final normalizedModule = module.trim();
    if (normalizedTenantId.isEmpty || normalizedModule.isEmpty) {
      return 0;
    }

    return all[_composeKey(normalizedTenantId, normalizedModule)] ?? 0;
  }

  Future<void> writeCursor({
    required String tenantId,
    required String module,
    required int cursor,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedModule = module.trim();
    if (normalizedTenantId.isEmpty || normalizedModule.isEmpty) {
      return;
    }

    final all = await readAll();
    all[_composeKey(normalizedTenantId, normalizedModule)] = cursor;
    await _writeAll(all);
  }

  Future<void> clearCursor({
    required String tenantId,
    required String module,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedModule = module.trim();
    if (normalizedTenantId.isEmpty || normalizedModule.isEmpty) {
      return;
    }

    final all = await readAll();
    all.remove(_composeKey(normalizedTenantId, normalizedModule));
    all.remove(_composeBootstrapKey(normalizedTenantId, normalizedModule));
    await _writeAll(all);
  }

  Future<void> clearTenant(String tenantId) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return;
    }

    final all = await readAll();
    all.removeWhere(
      (key, _) => key.startsWith('$normalizedTenantId::'),
    );
    await _writeAll(all);
  }

  Future<Map<String, int>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) {
      return <String, int>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return <String, int>{};
      }

      final output = <String, int>{};
      decoded.forEach((key, value) {
        final parsedValue = _readInt(value);
        if (parsedValue != null) {
          output[key] = parsedValue;
        }
      });
      return output;
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> _writeAll(Map<String, int> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(value));
  }

  static String _composeKey(String tenantId, String module) {
    return '$tenantId::$module';
  }

  static String _composeBootstrapKey(String tenantId, String module) {
    return '$tenantId::$module::bootstrap';
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
