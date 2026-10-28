import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/tax_operation_profile.dart';
import '../../repositories/tax_operation_profile_repository.dart';
import 'firestore_map_normalizer.dart';

/// Repositorio Firestore para `tax_operation_profiles`, usado pelo motor de
/// calculo para ler overrides dinamicos dos 10 perfis nativos (em vez de
/// depender apenas dos defaults fixos em memoria do classificador).
class FirestoreTaxOperationProfileRepository
    implements TaxOperationProfileRepository {
  FirestoreTaxOperationProfileRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final Map<String, List<TaxOperationProfile>> _tenantCache =
      <String, List<TaxOperationProfile>>{};

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('tax_operation_profiles');

  @override
  Stream<List<TaxOperationProfile>> watchAll({required String tenantId}) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <TaxOperationProfile>[]);
    }

    return _collection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs.map((doc) {
            final data = normalizeFirestoreMap(doc.data());
            data.putIfAbsent('id', () => doc.id);
            return TaxOperationProfile.fromMap(data);
          }).toList(growable: false);
          _tenantCache[normalizedTenantId] =
              List<TaxOperationProfile>.unmodifiable(items);
          return items;
        });
  }

  @override
  Future<List<TaxOperationProfile>> fetchAll({
    required String tenantId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const <TaxOperationProfile>[];
    }

    final cached = _tenantCache[normalizedTenantId];
    if (cached != null) {
      return List<TaxOperationProfile>.from(cached);
    }

    final snapshot = await _collection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .get();
    final items = snapshot.docs.map((doc) {
      final data = normalizeFirestoreMap(doc.data());
      data.putIfAbsent('id', () => doc.id);
      return TaxOperationProfile.fromMap(data);
    }).toList(growable: false);
    _tenantCache[normalizedTenantId] =
        List<TaxOperationProfile>.unmodifiable(items);
    return items;
  }

  @override
  Future<TaxOperationProfile?> fetchById({
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
    final entity = TaxOperationProfile.fromMap(data);
    if (entity.tenantId != normalizedTenantId) {
      return null;
    }
    return entity;
  }

  @override
  Future<void> save(TaxOperationProfile entity) {
    _tenantCache.remove(entity.tenantId.trim());
    return _collection.doc(entity.id).set(entity.toMap(), SetOptions(merge: true));
  }

  @override
  Future<void> delete({required String tenantId, required String id}) async {
    _tenantCache.remove(tenantId.trim());
    await _collection.doc(id).delete();
  }
}
