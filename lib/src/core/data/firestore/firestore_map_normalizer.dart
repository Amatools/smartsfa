import 'package:cloud_firestore/cloud_firestore.dart';

Map<String, Object?> normalizeFirestoreMap(Map<String, dynamic> source) {
  final target = <String, Object?>{};
  source.forEach((key, value) {
    target[key] = _normalizeValue(value);
  });
  return target;
}

Object? _normalizeValue(Object? value) {
  if (value is Timestamp) {
    return value.toDate().toIso8601String();
  }

  if (value is DateTime) {
    return value.toIso8601String();
  }

  if (value is Map<String, dynamic>) {
    return normalizeFirestoreMap(value);
  }

  if (value is List) {
    return value.map(_normalizeValue).toList();
  }

  return value;
}
