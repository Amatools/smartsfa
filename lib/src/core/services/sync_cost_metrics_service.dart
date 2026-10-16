import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_environment.dart';

enum SyncCostAlertLevel { warning, critical }

class SyncCostAlert {
  const SyncCostAlert({
    required this.level,
    required this.title,
    required this.message,
  });

  final SyncCostAlertLevel level;
  final String title;
  final String message;
}

class SyncCostMetricsSnapshot {
  const SyncCostMetricsSnapshot({
    required this.tenantId,
    required this.userId,
    required this.dateKey,
    required this.cloudSnapshotChecks,
    required this.cloudQueryOperations,
    required this.warmupRuns,
    required this.warmupPages,
    required this.warmupItems,
    required this.estimatedDocumentReads,
    required this.fallbackFullReads,
    required this.lastQueryReviewAt,
    required this.lastUpdatedAt,
  });

  const SyncCostMetricsSnapshot.empty()
    : tenantId = '',
      userId = '',
      dateKey = '',
      cloudSnapshotChecks = 0,
      cloudQueryOperations = 0,
      warmupRuns = 0,
      warmupPages = 0,
      warmupItems = 0,
      estimatedDocumentReads = 0,
      fallbackFullReads = 0,
      lastQueryReviewAt = null,
      lastUpdatedAt = null;

  final String tenantId;
  final String userId;
  final String dateKey;
  final int cloudSnapshotChecks;
  final int cloudQueryOperations;
  final int warmupRuns;
  final int warmupPages;
  final int warmupItems;
  final int estimatedDocumentReads;
  final int fallbackFullReads;
  final DateTime? lastQueryReviewAt;
  final DateTime? lastUpdatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'tenantId': tenantId,
      'userId': userId,
      'dateKey': dateKey,
      'cloudSnapshotChecks': cloudSnapshotChecks,
      'cloudQueryOperations': cloudQueryOperations,
      'warmupRuns': warmupRuns,
      'warmupPages': warmupPages,
      'warmupItems': warmupItems,
      'estimatedDocumentReads': estimatedDocumentReads,
      'fallbackFullReads': fallbackFullReads,
      'lastQueryReviewAt': lastQueryReviewAt?.toUtc().toIso8601String(),
      'lastUpdatedAt': lastUpdatedAt?.toUtc().toIso8601String(),
    };
  }

  factory SyncCostMetricsSnapshot.fromMap(Map<String, Object?> map) {
    return SyncCostMetricsSnapshot(
      tenantId: (map['tenantId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      dateKey: (map['dateKey'] ?? '').toString(),
      cloudSnapshotChecks: _readInt(map['cloudSnapshotChecks']),
      cloudQueryOperations: _readInt(map['cloudQueryOperations']),
      warmupRuns: _readInt(map['warmupRuns']),
      warmupPages: _readInt(map['warmupPages']),
      warmupItems: _readInt(map['warmupItems']),
      estimatedDocumentReads: _readInt(map['estimatedDocumentReads']),
      fallbackFullReads: _readInt(map['fallbackFullReads']),
      lastQueryReviewAt: _readDateTime(map['lastQueryReviewAt']),
      lastUpdatedAt: _readDateTime(map['lastUpdatedAt']),
    );
  }

  SyncCostMetricsSnapshot copyWith({
    int? cloudSnapshotChecks,
    int? cloudQueryOperations,
    int? warmupRuns,
    int? warmupPages,
    int? warmupItems,
    int? estimatedDocumentReads,
    int? fallbackFullReads,
    DateTime? lastQueryReviewAt,
    bool clearLastQueryReviewAt = false,
    DateTime? lastUpdatedAt,
  }) {
    return SyncCostMetricsSnapshot(
      tenantId: tenantId,
      userId: userId,
      dateKey: dateKey,
      cloudSnapshotChecks: cloudSnapshotChecks ?? this.cloudSnapshotChecks,
      cloudQueryOperations: cloudQueryOperations ?? this.cloudQueryOperations,
      warmupRuns: warmupRuns ?? this.warmupRuns,
      warmupPages: warmupPages ?? this.warmupPages,
      warmupItems: warmupItems ?? this.warmupItems,
      estimatedDocumentReads:
          estimatedDocumentReads ?? this.estimatedDocumentReads,
      fallbackFullReads: fallbackFullReads ?? this.fallbackFullReads,
      lastQueryReviewAt: clearLastQueryReviewAt
          ? null
          : (lastQueryReviewAt ?? this.lastQueryReviewAt),
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }
}

class SyncCostMetricsService {
  static const String _storageKey = 'smart_sfa_sync_cost_metrics_v1';
  static const int _maxEntries = 90;

  Future<SyncCostMetricsSnapshot> readToday({
    required String tenantId,
    required String userId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedUserId = userId.trim();
    if (normalizedTenantId.isEmpty || normalizedUserId.isEmpty) {
      return const SyncCostMetricsSnapshot.empty();
    }

    final dateKey = _todayDateKey();
    final key = _composeKey(normalizedTenantId, normalizedUserId, dateKey);
    final all = await _readAll();
    final existing = all[key];

    if (existing is Map<String, dynamic>) {
      return SyncCostMetricsSnapshot.fromMap(existing);
    }

    return SyncCostMetricsSnapshot(
      tenantId: normalizedTenantId,
      userId: normalizedUserId,
      dateKey: dateKey,
      cloudSnapshotChecks: 0,
      cloudQueryOperations: 0,
      warmupRuns: 0,
      warmupPages: 0,
      warmupItems: 0,
      estimatedDocumentReads: 0,
      fallbackFullReads: 0,
      lastQueryReviewAt: null,
      lastUpdatedAt: null,
    );
  }

  Future<SyncCostMetricsSnapshot> recordCloudSnapshotCheck({
    required String tenantId,
    required String userId,
    required int queryOperations,
    required int estimatedDocumentReads,
    required int fallbackFullReads,
  }) {
    return _mutateToday(
      tenantId: tenantId,
      userId: userId,
      mutate: (current) => current.copyWith(
        cloudSnapshotChecks: current.cloudSnapshotChecks + 1,
        cloudQueryOperations: current.cloudQueryOperations + queryOperations,
        estimatedDocumentReads:
            current.estimatedDocumentReads + estimatedDocumentReads,
        fallbackFullReads: current.fallbackFullReads + fallbackFullReads,
        lastUpdatedAt: DateTime.now(),
      ),
    );
  }

  Future<SyncCostMetricsSnapshot> recordWarmupRun({
    required String tenantId,
    required String userId,
    required int pagesPulled,
    required int itemsPulled,
    required int queryOperations,
    required int estimatedDocumentReads,
    required int fallbackFullReads,
  }) {
    return _mutateToday(
      tenantId: tenantId,
      userId: userId,
      mutate: (current) => current.copyWith(
        warmupRuns: current.warmupRuns + 1,
        warmupPages: current.warmupPages + pagesPulled,
        warmupItems: current.warmupItems + itemsPulled,
        cloudQueryOperations: current.cloudQueryOperations + queryOperations,
        estimatedDocumentReads:
            current.estimatedDocumentReads + estimatedDocumentReads,
        fallbackFullReads: current.fallbackFullReads + fallbackFullReads,
        lastUpdatedAt: DateTime.now(),
      ),
    );
  }

  Future<SyncCostMetricsSnapshot> markQueryPaginationReview({
    required String tenantId,
    required String userId,
  }) {
    return _mutateToday(
      tenantId: tenantId,
      userId: userId,
      mutate: (current) => current.copyWith(
        lastQueryReviewAt: DateTime.now(),
        lastUpdatedAt: DateTime.now(),
      ),
    );
  }

  SyncCostAlert? evaluateRegression({
    required SyncCostMetricsSnapshot summary,
  }) {
    final readThreshold = AppEnvironmentConfig.costReadRegressionThreshold;
    final queryOpThreshold =
        AppEnvironmentConfig.costQueryOperationRegressionThreshold;

    if (summary.fallbackFullReads >= 3) {
      return SyncCostAlert(
        level: SyncCostAlertLevel.critical,
        title: 'Alerta critico de custo',
        message:
            'Fallback full-read repetido (${summary.fallbackFullReads}x) hoje. Revisar indice/query imediatamente.',
      );
    }

    if (summary.estimatedDocumentReads >= readThreshold) {
      return SyncCostAlert(
        level: SyncCostAlertLevel.critical,
        title: 'Cota de leitura em risco',
        message:
            'Leituras estimadas hoje (${summary.estimatedDocumentReads}) acima do limite de alerta ($readThreshold).',
      );
    }

    if (summary.cloudQueryOperations >= queryOpThreshold) {
      return SyncCostAlert(
        level: SyncCostAlertLevel.warning,
        title: 'Regressao de consultas',
        message:
            'Operacoes de consulta hoje (${summary.cloudQueryOperations}) acima do esperado ($queryOpThreshold).',
      );
    }

    if (summary.estimatedDocumentReads >= (readThreshold * 0.8).round()) {
      return SyncCostAlert(
        level: SyncCostAlertLevel.warning,
        title: 'Aproximando limite de leitura',
        message:
            'Leituras estimadas hoje em ${summary.estimatedDocumentReads}; revisar paginação e filtros.',
      );
    }

    return null;
  }

  bool isQueryPaginationReviewOverdue(SyncCostMetricsSnapshot summary) {
    final reviewAt = summary.lastQueryReviewAt;
    if (reviewAt == null) {
      return true;
    }
    return DateTime.now().difference(reviewAt) >
        AppEnvironmentConfig.queryPaginationReviewCadence;
  }

  Future<SyncCostMetricsSnapshot> _mutateToday({
    required String tenantId,
    required String userId,
    required SyncCostMetricsSnapshot Function(SyncCostMetricsSnapshot current)
    mutate,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedUserId = userId.trim();
    if (normalizedTenantId.isEmpty || normalizedUserId.isEmpty) {
      return const SyncCostMetricsSnapshot.empty();
    }

    final dateKey = _todayDateKey();
    final key = _composeKey(normalizedTenantId, normalizedUserId, dateKey);
    final all = await _readAll();
    final current = await readToday(
      tenantId: normalizedTenantId,
      userId: normalizedUserId,
    );
    final next = mutate(current);
    all[key] = next.toMap();

    _trimOldEntries(all);
    await _writeAll(all);
    return next;
  }

  Future<Map<String, Object?>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, Object?>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      return <String, Object?>{};
    }

    return <String, Object?>{};
  }

  Future<void> _writeAll(Map<String, Object?> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(value));
  }

  void _trimOldEntries(Map<String, Object?> all) {
    if (all.length <= _maxEntries) {
      return;
    }

    final keys = all.keys.toList(growable: false);
    keys.sort();
    final overflow = all.length - _maxEntries;
    if (overflow <= 0) {
      return;
    }

    for (var i = 0; i < overflow; i++) {
      all.remove(keys[i]);
    }
  }

  static String _composeKey(String tenantId, String userId, String dateKey) {
    return '$tenantId::$userId::$dateKey';
  }

  static String _todayDateKey() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? 0;
  }
  return 0;
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}
