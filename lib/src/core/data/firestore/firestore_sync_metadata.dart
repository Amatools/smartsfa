Map<String, Object?> buildSyncUpsertPayload({
  required Map<String, Object?> source,
  DateTime? nowUtc,
}) {
  final now = (nowUtc ?? DateTime.now().toUtc()).toIso8601String();
  final currentVersion = _readInt(source['syncVersion']) ?? 0;

  return <String, Object?>{
    ...source,
    'createdAt': source['createdAt'] ?? now,
    'updatedAt': now,
    'syncVersion': currentVersion + 1,
    'deletedAt': null,
  };
}

Map<String, Object?> buildSyncDeletePayload({
  required Map<String, Object?> source,
  DateTime? nowUtc,
}) {
  final now = (nowUtc ?? DateTime.now().toUtc()).toIso8601String();
  final currentVersion = _readInt(source['syncVersion']) ?? 0;

  return <String, Object?>{
    ...source,
    'createdAt': source['createdAt'] ?? now,
    'updatedAt': now,
    'syncVersion': currentVersion + 1,
    'deletedAt': now,
  };
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
