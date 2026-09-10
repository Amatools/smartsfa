import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/cliente.dart';
import '../../repositories/cliente_repository.dart';
import 'firestore_map_normalizer.dart';

class FirestoreClienteRepository implements ClienteRepository {
  FirestoreClienteRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('clientes');

  @override
  Stream<List<Cliente>> watchAll({required String tenantId}) {
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
            return Cliente.fromMap(data);
          }).toList()..sort((a, b) => a.nome.compareTo(b.nome)),
        );
  }

  @override
  Future<List<Cliente>> fetchAll({required String tenantId}) async {
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
      return Cliente.fromMap(data);
    }).toList();
    items.sort((a, b) => a.nome.compareTo(b.nome));
    return items;
  }

  @override
  Future<Cliente?> fetchById({
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
    final entity = Cliente.fromMap(data);
    if (entity.tenantId != normalizedTenantId) {
      return null;
    }
    return entity;
  }

  @override
  Future<void> save(Cliente entity) {
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
