import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/produto.dart';
import '../../repositories/produto_repository.dart';
import 'firestore_map_normalizer.dart';
import 'firestore_sync_metadata.dart';

class FirestoreProdutoRepository implements ProdutoRepository {
  FirestoreProdutoRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final Map<String, List<Produto>> _tenantCache = <String, List<Produto>>{};

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('produtos');

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
        )
        .map((items) {
          _tenantCache[normalizedTenantId] = List<Produto>.unmodifiable(items);
          return items;
        });
  }

  @override
  Future<List<Produto>> fetchAll({required String tenantId}) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const [];
    }

    final cached = _tenantCache[normalizedTenantId];
    if (cached != null) {
      return List<Produto>.from(cached);
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
    _tenantCache[normalizedTenantId] = List<Produto>.unmodifiable(items);
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
    final entity = Produto.fromMap(data);
    if (entity.tenantId != normalizedTenantId) {
      return null;
    }
    return entity;
  }

  @override
  Future<void> save(Produto entity) async {
    final docRef = _collection.doc(entity.id);
    try {
      final payload = buildSyncUpsertPayload(source: entity.toMap());
      await docRef.set(payload);
      _tenantCache.remove(entity.tenantId.trim());
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw StateError(
          'permissao negada ao gravar em produtos para o tenant ${entity.tenantId}',
        );
      }
      rethrow;
    }
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
