import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cliente.dart';
import '../models/cliente_pre_cadastro.dart';
import '../models/domain_types.dart';

class LocalPreCadastroRecord {
  const LocalPreCadastroRecord({required this.entity, required this.synced});

  final ClientePreCadastro entity;
  final bool synced;
}

class LocalClienteRecord {
  const LocalClienteRecord({required this.entity, required this.synced});

  final Cliente entity;
  final bool synced;
}

class OfflineSyncQueueItem {
  const OfflineSyncQueueItem({
    required this.id,
    required this.type,
    required this.tenantId,
    required this.payload,
    required this.createdAt,
    this.synced = false,
  });

  final String id;
  final String type;
  final String tenantId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final bool synced;

  Map<String, dynamic> get payloadMap => payload;

  OfflineSyncQueueItem copyWith({
    Map<String, dynamic>? payload,
    bool? synced,
  }) {
    return OfflineSyncQueueItem(
      id: id,
      type: type,
      tenantId: tenantId,
      payload: payload ?? this.payload,
      createdAt: createdAt,
      synced: synced ?? this.synced,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'tenantId': tenantId,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'synced': synced,
    };
  }

  factory OfflineSyncQueueItem.fromMap(Map<String, dynamic> map) {
    return OfflineSyncQueueItem(
      id: map['id']?.toString() ?? '',
      type: map['type']?.toString() ?? 'unknown',
      tenantId: map['tenantId']?.toString() ?? '',
      payload: Map<String, dynamic>.from(map['payload'] ?? const {}),
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      synced: map['synced'] == true,
    );
  }
}

class OfflineSyncQueue {
  static const _key = 'smart_sfa_offline_sync_queue';
  static const _deletedKey = 'smart_sfa_offline_deleted_entities';

  /// Persists [payload] as a local-first record. This queue doubles as the
  /// device's local database for the entity, so this is an upsert keyed by
  /// the entity's own id (falling back to a generated id only when the
  /// payload has none) rather than a blind append — re-saving the same
  /// entity (e.g. after a remote sync attempt) updates the existing record
  /// instead of creating a duplicate.
  static Future<void> enqueue({
    required String type,
    required String tenantId,
    required Map<String, Object?> payload,
    bool synced = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await readAll();
    final entityId = payload['id']?.toString() ?? '';
    final id = entityId.isNotEmpty
        ? entityId
        : 'sync_${DateTime.now().microsecondsSinceEpoch}';

    final item = OfflineSyncQueueItem(
      id: id,
      type: type,
      tenantId: tenantId,
      payload: payload.map((key, value) => MapEntry(key, value)),
      createdAt: DateTime.now(),
      synced: synced,
    );

    final next = [
      ...existing.where((entry) => entry.id != id),
      item,
    ];
    await prefs.setString(
      _key,
      jsonEncode(next.map((entry) => entry.toMap()).toList()),
    );
  }

  /// Marks a local record as already synced with the backend without
  /// removing it, so it keeps being visible locally (local-first) with an
  /// accurate sync badge.
  static Future<void> markSynced(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await readAll();
    final next = all
        .map((item) => item.id == id ? item.copyWith(synced: true) : item)
        .toList();
    await prefs.setString(
      _key,
      jsonEncode(next.map((entry) => entry.toMap()).toList()),
    );
  }

  /// Cleans up leftover duplicate pre-cadastros created before duplicate
  /// documents were blocked. Records are grouped by tenant + normalized
  /// documento; within each group only the most recently updated one is
  /// kept (preferring an already-synced record, since deleting that one
  /// would just cause it to be re-created on the next sync pass). Returns
  /// how many duplicate records were removed.
  static Future<int> deduplicatePreCadastros() async {
    final all = await readAll();
    final others = all.where((item) => item.type != 'cliente_pre_cadastro').toList();
    final preCadastros = all.where((item) => item.type == 'cliente_pre_cadastro').toList();

    final groups = <String, List<OfflineSyncQueueItem>>{};
    for (final item in preCadastros) {
      final entity = ClientePreCadastro.fromMap(Map<String, Object?>.from(item.payload));
      final normalizedDocumento = entity.documento.replaceAll(RegExp(r'\D'), '');
      final documentoKey =
          normalizedDocumento.isNotEmpty ? normalizedDocumento : entity.documento.trim().toLowerCase();
      final key = '${entity.tenantId.trim()}::$documentoKey';
      groups.putIfAbsent(key, () => []).add(item);
    }

    final toKeep = <OfflineSyncQueueItem>[];
    var removedCount = 0;

    for (final group in groups.values) {
      if (group.length <= 1) {
        toKeep.addAll(group);
        continue;
      }

      group.sort((a, b) {
        if (a.synced != b.synced) {
          return a.synced ? -1 : 1;
        }
        final entityA = ClientePreCadastro.fromMap(Map<String, Object?>.from(a.payload));
        final entityB = ClientePreCadastro.fromMap(Map<String, Object?>.from(b.payload));
        final dateA = entityA.updatedAt ?? entityA.createdAt ?? a.createdAt;
        final dateB = entityB.updatedAt ?? entityB.createdAt ?? b.createdAt;
        return dateB.compareTo(dateA);
      });

      toKeep.add(group.first);
      removedCount += group.length - 1;
    }

    if (removedCount > 0) {
      final prefs = await SharedPreferences.getInstance();
      final next = [...others, ...toKeep];
      await prefs.setString(
        _key,
        jsonEncode(next.map((entry) => entry.toMap()).toList()),
      );
    }

    return removedCount;
  }

  /// Removes legacy "approved" pre-cadastro records that were never converted
  /// into a real cliente. This gives the user a clean slate to re-use the same
  /// data in a fresh workflow without the stale orphan remaining in local storage.
  static Future<int> removeOrphanApprovedPreCadastros({
    String? tenantId,
    bool includePersonalWorkspace = false,
  }) async {
    final all = await readAll();
    final next = <OfflineSyncQueueItem>[];
    var removedCount = 0;

    for (final item in all) {
      if (item.type != 'cliente_pre_cadastro') {
        next.add(item);
        continue;
      }

      final entity = ClientePreCadastro.fromMap(Map<String, Object?>.from(item.payload));
      final normalizedTenantId = (tenantId ?? '').trim();
      final normalizedEntityTenant = entity.tenantId.trim();

      final matchesScope = normalizedTenantId.isEmpty
          ? normalizedEntityTenant.isEmpty ||
              (includePersonalWorkspace && normalizedEntityTenant.startsWith('personal_'))
          : normalizedEntityTenant == normalizedTenantId ||
              (includePersonalWorkspace &&
                  (normalizedEntityTenant.startsWith('personal_') ||
                      normalizedEntityTenant.isEmpty));

      final isOrphan = entity.status == PreRegistrationStatus.approved &&
          (entity.mergedClienteId == null || entity.mergedClienteId!.isEmpty);

      if (matchesScope && isOrphan) {
        removedCount++;
        continue;
      }

      next.add(item);
    }

    if (removedCount > 0) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(next.map((entry) => entry.toMap()).toList()),
      );
    }

    return removedCount;
  }

  static Future<List<OfflineSyncQueueItem>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return <OfflineSyncQueueItem>[];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => OfflineSyncQueueItem.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <OfflineSyncQueueItem>[];
    }
  }

  static Future<List<ClientePreCadastro>> readQueuedPreCadastros({
    String? tenantId,
    bool includePersonalWorkspace = false,
    String? requestedByUid,
  }) async {
    final records = await readLocalPreCadastroRecords(
      tenantId: tenantId,
      includePersonalWorkspace: includePersonalWorkspace,
      requestedByUid: requestedByUid,
    );
    return records.map((record) => record.entity).toList();
  }

  /// Local-first read of every cliente persisted on this device — including
  /// clientes created here from an approved pre-cadastro before a Firestore
  /// sync round-trip ever happened. Kept around (flagged as `synced`) even
  /// after a successful sync, exactly like [readLocalPreCadastroRecords].
  static Future<List<LocalClienteRecord>> readLocalClientes({
    String? tenantId,
    bool includePersonalWorkspace = false,
  }) async {
    final queued = await readAll();
    final normalizedTenantId = (tenantId ?? '').trim();

    final items = queued
        .where((item) => item.type == 'cliente')
        .where((item) {
          final entity = Cliente.fromMap(Map<String, Object?>.from(item.payload));
          if (entity.id.isEmpty) {
            return false;
          }

          final normalizedEntityTenant = entity.tenantId.trim();

          if (normalizedTenantId.isEmpty) {
            return normalizedEntityTenant.isEmpty ||
                (includePersonalWorkspace && normalizedEntityTenant.startsWith('personal_'));
          }

          if (normalizedEntityTenant == normalizedTenantId) {
            return true;
          }

          return includePersonalWorkspace &&
              normalizedEntityTenant.startsWith('personal_');
        })
        .map((item) => LocalClienteRecord(
              entity: Cliente.fromMap(Map<String, Object?>.from(item.payload)),
              synced: item.synced,
            ))
        .toList();

    return items;
  }

  /// Local-first read of every pre-cadastro persisted on this device,
  /// including the ones already synced with the backend (kept around,
  /// flagged as `synced`, instead of being deleted) so the UI never depends
  /// on a remote round-trip to know a pre-cadastro exists.
  static Future<List<LocalPreCadastroRecord>> readLocalPreCadastroRecords({
    String? tenantId,
    bool includePersonalWorkspace = false,
    String? requestedByUid,
  }) async {
    final queued = await readAll();
    final items = queued
        .where((item) => item.type == 'cliente_pre_cadastro')
        .where((item) {
          final entity =
              ClientePreCadastro.fromMap(Map<String, Object?>.from(item.payload));
          if (entity.id.isEmpty) {
            return false;
          }

          final normalizedTenantId = (tenantId ?? '').trim();
          final normalizedEntityTenant = entity.tenantId.trim();
          final normalizedRequestedBy = (requestedByUid ?? '').trim();

          if (normalizedTenantId.isEmpty && normalizedRequestedBy.isEmpty) {
            return entity.tenantId.trim().isEmpty ||
                (includePersonalWorkspace && entity.tenantId.startsWith('personal_'));
          }

          if (normalizedEntityTenant == normalizedTenantId) {
            return true;
          }

          if (includePersonalWorkspace &&
              (entity.tenantId.startsWith('personal_') ||
                  normalizedEntityTenant.isEmpty)) {
            return true;
          }

          if (normalizedRequestedBy.isNotEmpty &&
              entity.requestedByUid.trim() == normalizedRequestedBy) {
            return true;
          }

          return false;
        })
        .map((item) => LocalPreCadastroRecord(
              entity: ClientePreCadastro.fromMap(
                Map<String, Object?>.from(item.payload),
              ),
              synced: item.synced,
            ))
        .toList();

    return items;
  }

  static Future<void> updatePreCadastroStatus(
    String id,
    ClientePreCadastro updated,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await readAll();
    final next = all.map((item) {
      if (item.id != id || item.type != 'cliente_pre_cadastro') {
        return item;
      }

      final payload = <String, Object?>{
        ...item.payload,
        ...updated.toMap(),
      };

      // This changes the record's payload (e.g. pending -> merged after an
      // approval), so any previous `synced: true` flag no longer reflects
      // reality — it described the OLD payload, not this new one. Leaving it
      // `true` here would make every retry path (manual "Sincronizar agora"
      // and the background auto-sync) skip this record forever if the
      // caller's own best-effort remote save right after this call fails,
      // permanently stranding Firestore with a stale status.
      return OfflineSyncQueueItem(
        id: item.id,
        type: item.type,
        tenantId: item.tenantId,
        payload: payload,
        createdAt: item.createdAt,
        synced: false,
      );
    }).toList();

    await prefs.setString(
      _key,
      jsonEncode(next.map((entry) => entry.toMap()).toList()),
    );
  }

  static Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await readAll();
    final next = all.where((item) => item.id != id).toList();
    await prefs.setString(
      _key,
      jsonEncode(next.map((entry) => entry.toMap()).toList()),
    );
  }

  /// Local-first delete: removes the entity from the on-device queue
  /// immediately (via [remove], so it disappears from the UI regardless of
  /// connectivity) AND records a tombstone. This is the piece that used to
  /// be missing: a remote fetch/live stream that merges server data with
  /// local data has no other way of knowing "this id was deleted here on
  /// purpose" versus "this id simply was never created here" — without a
  /// tombstone, any record whose remote delete hasn't completed yet (still
  /// offline, a transient error, or a permission mismatch) reappears the
  /// moment the app re-reads or re-streams from the backend. Every
  /// remote-merge read must filter its results through [readDeletedIds].
  /// Call [clearTombstone] once the remote delete is confirmed, or retry it
  /// later (e.g. from a "Sincronizar agora" action) using
  /// [readPendingDeletes].
  static Future<void> markDeleted({
    required String type,
    required String tenantId,
    required String id,
  }) async {
    await remove(id);
    final prefs = await SharedPreferences.getInstance();
    final tombstones = _decodeTombstones(prefs.getString(_deletedKey));
    tombstones.removeWhere((entry) => entry['id'] == id);
    tombstones.add({
      'id': id,
      'type': type,
      'tenantId': tenantId,
      'deletedAt': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_deletedKey, jsonEncode(tombstones));
  }

  /// Clears a tombstone once the remote delete for [id] has been confirmed
  /// (or if the record needs to be recreated with the same id).
  static Future<void> clearTombstone(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final tombstones = _decodeTombstones(prefs.getString(_deletedKey));
    tombstones.removeWhere((entry) => entry['id'] == id);
    await prefs.setString(_deletedKey, jsonEncode(tombstones));
  }

  /// All tombstones still pending remote confirmation, optionally filtered
  /// by entity [type] (`cliente` or `cliente_pre_cadastro`).
  static Future<List<Map<String, dynamic>>> readPendingDeletes({
    String? type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final tombstones = _decodeTombstones(prefs.getString(_deletedKey));
    if (type == null) {
      return tombstones;
    }
    return tombstones.where((entry) => entry['type'] == type).toList();
  }

  /// Convenience set of tombstoned ids for [type], used to filter out
  /// locally-deleted records from any remote fetch/stream result before
  /// merging it with local-first data.
  static Future<Set<String>> readDeletedIds({String? type}) async {
    final entries = await readPendingDeletes(type: type);
    return entries.map((entry) => entry['id'].toString()).toSet();
  }

  static List<Map<String, dynamic>> _decodeTombstones(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <Map<String, dynamic>>[];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}
