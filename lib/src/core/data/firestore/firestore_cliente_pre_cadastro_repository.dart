import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/cliente_pre_cadastro.dart';
import '../../repositories/cliente_pre_cadastro_repository.dart';
import 'firestore_map_normalizer.dart';

class FirestoreClientePreCadastroRepository
    implements ClientePreCadastroRepository {
  FirestoreClientePreCadastroRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('cliente_pre_cadastros');

  @override
  Stream<List<ClientePreCadastro>> watchAll({required String tenantId}) {
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
            return ClientePreCadastro.fromMap(data);
          }).toList();
          items.sort((a, b) => (b.updatedAt ?? b.createdAt ?? DateTime.now())
              .compareTo(a.updatedAt ?? a.createdAt ?? DateTime.now()));
          return items;
        });
  }

  @override
  Future<List<ClientePreCadastro>> fetchAll({required String tenantId}) async {
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
      return ClientePreCadastro.fromMap(data);
    }).toList();
    items.sort((a, b) => (b.updatedAt ?? b.createdAt ?? DateTime.now())
        .compareTo(a.updatedAt ?? a.createdAt ?? DateTime.now()));
    return items;
  }

  @override
  Future<ClientePreCadastro?> fetchById({
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
    final entity = ClientePreCadastro.fromMap(data);
    if (entity.tenantId != normalizedTenantId) {
      return null;
    }
    return entity;
  }

  @override
  Future<void> save(ClientePreCadastro entity) {
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
