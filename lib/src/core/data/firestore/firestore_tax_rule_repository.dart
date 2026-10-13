import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/tax_rule.dart';
import '../../repositories/tax_rule_repository.dart';
import 'firestore_map_normalizer.dart';
import 'firestore_sync_metadata.dart';

class FirestoreTaxRuleRepository implements TaxRuleRepository {
  FirestoreTaxRuleRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final Map<String, List<TaxRule>> _tenantCache = <String, List<TaxRule>>{};

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('tax_rules');

  @override
  Stream<List<TaxRule>> watchAll({required String tenantId}) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <TaxRule>[]);
    }

    return _collection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs.map((doc) {
            final data = normalizeFirestoreMap(doc.data());
            data.putIfAbsent('id', () => doc.id);
            return TaxRule.fromMap(data);
          }).toList();
          items.sort((a, b) => b.priority.compareTo(a.priority));
          _tenantCache[normalizedTenantId] = List<TaxRule>.unmodifiable(items);
          return items;
        });
  }

  @override
  Future<List<TaxRule>> fetchAll({required String tenantId}) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const <TaxRule>[];
    }

    final cached = _tenantCache[normalizedTenantId];
    if (cached != null) {
      return List<TaxRule>.from(cached);
    }

    final snapshot = await _collection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .get();
    final items = snapshot.docs.map((doc) {
      final data = normalizeFirestoreMap(doc.data());
      data.putIfAbsent('id', () => doc.id);
      return TaxRule.fromMap(data);
    }).toList();
    items.sort((a, b) => b.priority.compareTo(a.priority));
    _tenantCache[normalizedTenantId] = List<TaxRule>.unmodifiable(items);
    return items;
  }

  @override
  Future<TaxRule?> fetchById({
    required String tenantId,
    required String id,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedId = id.trim();
    if (normalizedTenantId.isEmpty || normalizedId.isEmpty) {
      return null;
    }

    final cached = _tenantCache[normalizedTenantId];
    if (cached != null) {
      for (final item in cached) {
        if (item.id == normalizedId) {
          return item;
        }
      }
    }

    final doc = await _collection.doc(normalizedId).get();
    if (!doc.exists) {
      return null;
    }

    final data = normalizeFirestoreMap(doc.data() ?? <String, dynamic>{});
    data.putIfAbsent('id', () => doc.id);
    final entity = TaxRule.fromMap(data);
    if (entity.tenantId != normalizedTenantId) {
      return null;
    }
    return entity;
  }

  @override
  Future<void> save(TaxRule entity) {
    final payload = buildSyncUpsertPayload(source: entity.toMap());
    _tenantCache.remove(entity.tenantId.trim());
    return _collection.doc(entity.id).set(payload);
  }

  @override
  Future<void> delete({required String tenantId, required String id}) async {
    final existing = await fetchById(tenantId: tenantId, id: id);
    if (existing == null) {
      return;
    }
    await _collection.doc(id).delete();
    _tenantCache.remove(tenantId.trim());
  }
}
