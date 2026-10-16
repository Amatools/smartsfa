import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/tabela_preco.dart';
import '../../repositories/tabela_preco_repository.dart';
import 'firestore_map_normalizer.dart';
import 'firestore_sync_metadata.dart';

class FirestoreTabelaPrecoRepository implements TabelaPrecoRepository {
  FirestoreTabelaPrecoRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final Map<String, List<TabelaPreco>> _tenantCache =
      <String, List<TabelaPreco>>{};

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('tabelas_preco');

  @override
  Stream<List<TabelaPreco>> watchAll({required String tenantId}) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const []);
    }

    return _collection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) {
                    final data = normalizeFirestoreMap(doc.data());
                    data.putIfAbsent('id', () => doc.id);
                    return TabelaPreco.fromMap(data);
                  })
                  .where((tabela) {
                    final deletedAt = tabela.deletedAt;
                    return deletedAt == null;
                  })
                  .toList()
                ..sort(
                  (a, b) =>
                      b.updatedAt?.compareTo(a.updatedAt ?? DateTime(1970)) ??
                      0,
                ),
        )
        .map((items) {
          _tenantCache[normalizedTenantId] = List<TabelaPreco>.unmodifiable(
            items,
          );
          return items;
        });
  }

  @override
  Future<List<TabelaPreco>> fetchAll({required String tenantId}) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const [];
    }

    final cached = _tenantCache[normalizedTenantId];
    if (cached != null) {
      return List<TabelaPreco>.from(cached);
    }

    final snapshot = await _collection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .get();
    final items = snapshot.docs
        .map((doc) {
          final data = normalizeFirestoreMap(doc.data());
          data.putIfAbsent('id', () => doc.id);
          return TabelaPreco.fromMap(data);
        })
        .where((tabela) {
          final deletedAt = tabela.deletedAt;
          return deletedAt == null;
        })
        .toList();

    items.sort((a, b) {
      final left = a.updatedAt ?? DateTime(1970);
      final right = b.updatedAt ?? DateTime(1970);
      return right.compareTo(left);
    });
    _tenantCache[normalizedTenantId] = List<TabelaPreco>.unmodifiable(items);
    return items;
  }

  @override
  Future<TabelaPreco?> fetchById({
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
    final entity = TabelaPreco.fromMap(data);
    if (entity.tenantId != normalizedTenantId) {
      return null;
    }
    if (entity.deletedAt != null) {
      return null;
    }
    return entity;
  }

  @override
  Future<void> save(TabelaPreco entity) {
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

    final isProtectedDefault =
        existing.origem.trim().toLowerCase() == 'system' &&
        existing.nome.trim().toLowerCase() == 'tabela padrao';
    if (isProtectedDefault) {
      throw StateError(
        'A tabela padrao do sistema nao pode ser excluida manualmente.',
      );
    }

    final basePrices = await _firestore
        .collection('product_base_prices')
        .where('tenantId', isEqualTo: tenantId.trim())
        .where('priceTableId', isEqualTo: id.trim())
        .get();
    if (basePrices.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in basePrices.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    final payload = buildSyncDeletePayload(source: existing.toMap());
    await _collection.doc(id).set(payload, SetOptions(merge: true));
    _tenantCache.remove(tenantId.trim());
  }
}
