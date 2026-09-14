import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/product_base_price.dart';
import '../../repositories/product_base_price_repository.dart';
import 'firestore_map_normalizer.dart';

class FirestoreProductBasePriceRepository implements ProductBasePriceRepository {
  FirestoreProductBasePriceRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('product_base_prices');

  @override
  Stream<List<ProductBasePrice>> watchAll({required String tenantId}) {
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
        return ProductBasePrice.fromMap(data);
      }).toList();
      items.sort((a, b) => a.productId.compareTo(b.productId));
      return items;
    });
  }

  @override
  Future<List<ProductBasePrice>> fetchAll({required String tenantId}) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const [];
    }

    final snapshot =
        await _collection.where('tenantId', isEqualTo: normalizedTenantId).get();
    final items = snapshot.docs.map((doc) {
      final data = normalizeFirestoreMap(doc.data());
      data.putIfAbsent('id', () => doc.id);
      return ProductBasePrice.fromMap(data);
    }).toList();
    items.sort((a, b) => a.productId.compareTo(b.productId));
    return items;
  }

  @override
  Future<ProductBasePrice?> fetchById({
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
    final entity = ProductBasePrice.fromMap(data);
    if (entity.tenantId != normalizedTenantId) {
      return null;
    }
    return entity;
  }

  @override
  Future<void> save(ProductBasePrice entity) {
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
