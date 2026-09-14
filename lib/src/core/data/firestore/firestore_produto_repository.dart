import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/produto.dart';
import '../../repositories/produto_repository.dart';
import 'firestore_map_normalizer.dart';

class FirestoreProdutoRepository implements ProdutoRepository {
  FirestoreProdutoRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('produtos');

    CollectionReference<Map<String, dynamic>> get _counterCollection =>
      _firestore.collection('tenant_counters');

  @override
  Stream<List<Produto>> watchAll({required String tenantId}) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const []);
    }

    return _collection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = normalizeFirestoreMap(doc.data());
            data.putIfAbsent('id', () => doc.id);
            return Produto.fromMap(data);
          }).toList()..sort((a, b) => a.descricao.compareTo(b.descricao)),
        );
  }

  @override
  Future<List<Produto>> fetchAll({required String tenantId}) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const [];
    }

    final snapshot = await _collection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .get();
    final items = snapshot.docs.map((doc) {
      final data = normalizeFirestoreMap(doc.data());
      data.putIfAbsent('id', () => doc.id);
      return Produto.fromMap(data);
    }).toList();
    items.sort((a, b) => a.descricao.compareTo(b.descricao));
    return items;
  }

  @override
  Future<Produto?> fetchById({
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
    final entity = Produto.fromMap(data);
    if (entity.tenantId != normalizedTenantId) {
      return null;
    }
    return entity;
  }

  @override
  Future<void> save(Produto entity) async {
    final docRef = _collection.doc(entity.id);

    await _firestore.runTransaction((transaction) async {
      final existingDoc = await transaction.get(docRef);
      if (existingDoc.exists) {
        transaction.set(docRef, entity.toMap());
        return;
      }

      final counterRef = _counterCollection.doc(entity.tenantId);
      final counterDoc = await transaction.get(counterRef);
      final currentSequence =
          ((counterDoc.data()?['productCodeSequence'] as num?) ?? 0).toInt();
      final nextSequence = currentSequence + 1;
      final generatedCode = 'PRD-${nextSequence.toString().padLeft(6, '0')}';

      final entityWithCode = entity.copyWith(codigoInterno: generatedCode);
      transaction.set(counterRef, {
        'tenantId': entity.tenantId,
        'productCodeSequence': nextSequence,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.set(docRef, entityWithCode.toMap());
    });
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
