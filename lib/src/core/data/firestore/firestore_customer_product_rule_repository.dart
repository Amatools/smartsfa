import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/customer_product_rule.dart';
import '../../repositories/customer_product_rule_repository.dart';
import 'firestore_map_normalizer.dart';

class FirestoreCustomerProductRuleRepository
    implements CustomerProductRuleRepository {
  FirestoreCustomerProductRuleRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('customer_product_rules');

  @override
  Stream<List<CustomerProductRule>> watchAll({required String tenantId}) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const []);
    }

    return _collection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map((doc) {
        final data = normalizeFirestoreMap(doc.data());
        data.putIfAbsent('id', () => doc.id);
        return CustomerProductRule.fromMap(data);
      }).toList();
      items.sort((a, b) => b.priority.compareTo(a.priority));
      return items;
    });
  }

  @override
  Future<List<CustomerProductRule>> fetchAll({required String tenantId}) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const [];
    }

    final snapshot =
        await _collection.where('tenantId', isEqualTo: normalizedTenantId).get();
    final items = snapshot.docs.map((doc) {
      final data = normalizeFirestoreMap(doc.data());
      data.putIfAbsent('id', () => doc.id);
      return CustomerProductRule.fromMap(data);
    }).toList();
    items.sort((a, b) => b.priority.compareTo(a.priority));
    return items;
  }

  @override
  Future<CustomerProductRule?> fetchById({
    required String tenantId,
    required String id,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedId = id.trim();
    if (normalizedTenantId.isEmpty || normalizedId.isEmpty) {
      return null;
    }

    final doc = await _collection.doc(normalizedId).get();
    if (!doc.exists) {
      return null;
    }

    final data = normalizeFirestoreMap(doc.data() ?? <String, dynamic>{});
    data.putIfAbsent('id', () => doc.id);
    final entity = CustomerProductRule.fromMap(data);
    if (entity.tenantId != normalizedTenantId) {
      return null;
    }
    return entity;
  }

  @override
  Future<void> save(CustomerProductRule entity) {
    return _collection.doc(entity.id).set(entity.toMap());
  }

  @override
  Future<void> delete({required String tenantId, required String id}) async {
    final existing = await fetchById(tenantId: tenantId, id: id);
    if (existing == null) {
      return;
    }
    await _collection.doc(id).delete();
  }
}
