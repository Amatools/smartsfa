import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/pedido.dart';
import '../../repositories/pedido_repository.dart';
import 'firestore_map_normalizer.dart';

class FirestorePedidoRepository implements PedidoRepository {
  FirestorePedidoRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final Map<String, List<Pedido>> _tenantCache = <String, List<Pedido>>{};

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('pedidos');

  List<Pedido> _mapAndSortPedidos(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final items = snapshot.docs.map((doc) {
      final data = normalizeFirestoreMap(doc.data());
      data.putIfAbsent('id', () => doc.id);
      return Pedido.fromMap(data);
    }).toList();
    items.sort((a, b) => a.id.compareTo(b.id));
    return items;
  }

  void _setTenantCache(String tenantId, List<Pedido> items) {
    _tenantCache[tenantId] = List<Pedido>.unmodifiable(items);
  }

  Query<Map<String, dynamic>> _queryByScope({
    required String tenantId,
    required String field,
    required String value,
  }) {
    return _collection
        .where('tenantId', isEqualTo: tenantId)
        .where(field, isEqualTo: value);
  }

  Future<List<Query<Map<String, dynamic>>>> _buildScopedFallbackQueries({
    required String tenantId,
  }) async {
    final queries = <Query<Map<String, dynamic>>>[];
    final seen = <String>{};

    void addScopeQuery(String field, String rawValue) {
      final value = rawValue.trim();
      if (value.isEmpty) {
        return;
      }

      final key = '$field::$value';
      if (!seen.add(key)) {
        return;
      }

      queries.add(
        _queryByScope(tenantId: tenantId, field: field, value: value),
      );
    }

    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      return const [];
    }

    // Direct uid probes keep fallback resilient when membership lookup fails.
    addScopeQuery('ownerId', uid);
    addScopeQuery('gerenteId', uid);
    addScopeQuery('representanteId', uid);
    addScopeQuery('vendedorId', uid);

    try {
      DocumentSnapshot<Map<String, dynamic>>? membershipDoc;
      final byPatternId = await _firestore
          .collection('tenant_memberships')
          .doc('${tenantId}_$uid')
          .get();
      if (byPatternId.exists) {
        membershipDoc = byPatternId;
      } else {
        final byQuery = await _firestore
            .collection('tenant_memberships')
            .where('tenantId', isEqualTo: tenantId)
            .where('uid', isEqualTo: uid)
            .where('ativo', isEqualTo: true)
            .limit(1)
            .get();
        if (byQuery.docs.isNotEmpty) {
          membershipDoc = byQuery.docs.first;
        }
      }

      if (membershipDoc != null && membershipDoc.exists) {
        final membership = normalizeFirestoreMap(
          membershipDoc.data() ?? <String, dynamic>{},
        );
        if (membership['ativo'] == true) {
          addScopeQuery('ownerId', (membership['ownerId'] ?? '').toString());
          addScopeQuery(
            'gerenteId',
            (membership['gerenteId'] ?? '').toString(),
          );
          addScopeQuery(
            'representanteId',
            (membership['representanteId'] ?? '').toString(),
          );
          addScopeQuery(
            'vendedorId',
            (membership['vendedorId'] ?? '').toString(),
          );
        }
      }
    } catch (_) {
      // Membership read is best-effort only.
    }

    return queries;
  }

  Future<List<Pedido>> _fetchScopedFallbackPedidos({
    required String tenantId,
  }) async {
    final queries = await _buildScopedFallbackQueries(tenantId: tenantId);
    if (queries.isEmpty) {
      return const [];
    }

    final byId = <String, Pedido>{};
    FirebaseException? lastPermissionDenied;

    for (final query in queries) {
      try {
        final snapshot = await query.get();
        for (final doc in snapshot.docs) {
          final data = normalizeFirestoreMap(doc.data());
          data.putIfAbsent('id', () => doc.id);
          final pedido = Pedido.fromMap(data);
          if (pedido.id.trim().isEmpty) {
            continue;
          }
          byId[pedido.id] = pedido;
        }
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          lastPermissionDenied = error;
          continue;
        }

        if (error.code == 'failed-precondition') {
          // Missing index on one scoped query should not block the rest.
          continue;
        }

        rethrow;
      }
    }

    if (byId.isNotEmpty) {
      final items = byId.values.toList();
      items.sort((a, b) => a.id.compareTo(b.id));
      _setTenantCache(tenantId, items);
      return items;
    }

    if (lastPermissionDenied != null) {
      throw lastPermissionDenied;
    }

    return const [];
  }

  Stream<List<Pedido>> _watchScopedFallbackPedidos({
    required String tenantId,
  }) {
    return Stream.multi((controller) async {
      final queries = await _buildScopedFallbackQueries(tenantId: tenantId);
      if (queries.isEmpty) {
        controller.add(const []);
        controller.close();
        return;
      }

      final byQuery = <int, Map<String, Pedido>>{
        for (var index = 0; index < queries.length; index++)
          index: <String, Pedido>{},
      };
      final subscriptions =
          <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

      void emitMerged() {
        final byId = <String, Pedido>{};
        for (final partial in byQuery.values) {
          byId.addAll(partial);
        }
        final merged = byId.values.toList()
          ..sort((a, b) => a.id.compareTo(b.id));
        _setTenantCache(tenantId, merged);
        controller.add(merged);
      }

      for (var index = 0; index < queries.length; index++) {
        final scopedIndex = index;
        final subscription = queries[scopedIndex].snapshots().listen(
          (snapshot) {
            final current = <String, Pedido>{};
            for (final doc in snapshot.docs) {
              final data = normalizeFirestoreMap(doc.data());
              data.putIfAbsent('id', () => doc.id);
              final pedido = Pedido.fromMap(data);
              if (pedido.id.trim().isEmpty) {
                continue;
              }
              current[pedido.id] = pedido;
            }
            byQuery[scopedIndex] = current;
            emitMerged();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (error is FirebaseException &&
                (error.code == 'permission-denied' ||
                    error.code == 'failed-precondition')) {
              byQuery[scopedIndex] = <String, Pedido>{};
              emitMerged();
              return;
            }

            controller.addError(error, stackTrace);
          },
        );
        subscriptions.add(subscription);
      }

      emitMerged();

      controller.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  @override
  Stream<List<Pedido>> watchAll({required String tenantId}) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const []);
    }

    return Stream.multi((controller) {
      StreamSubscription<List<Pedido>>? fallbackSubscription;

      final primarySubscription = _collection
          .where('tenantId', isEqualTo: normalizedTenantId)
          .snapshots()
          .map(_mapAndSortPedidos)
          .listen(
            (items) {
              _setTenantCache(normalizedTenantId, items);
              controller.add(items);
            },
            onError: (Object error, StackTrace stackTrace) {
              final isPermissionDenied =
                  error is FirebaseException && error.code == 'permission-denied';
              if (isPermissionDenied && fallbackSubscription == null) {
                fallbackSubscription = _watchScopedFallbackPedidos(
                  tenantId: normalizedTenantId,
                ).listen(
                  (items) {
                    _setTenantCache(normalizedTenantId, items);
                    controller.add(items);
                  },
                  onError: controller.addError,
                );
                return;
              }

              controller.addError(error, stackTrace);
            },
          );

      controller.onCancel = () async {
        await primarySubscription.cancel();
        await fallbackSubscription?.cancel();
      };
    });
  }

  @override
  Future<List<Pedido>> fetchAll({required String tenantId}) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const [];
    }

    final cached = _tenantCache[normalizedTenantId];
    if (cached != null) {
      return List<Pedido>.from(cached);
    }

    try {
      final snapshot = await _collection
          .where('tenantId', isEqualTo: normalizedTenantId)
          .get();
      final items = _mapAndSortPedidos(snapshot);
      _setTenantCache(normalizedTenantId, items);
      return items;
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }

      final scopedItems = await _fetchScopedFallbackPedidos(
        tenantId: normalizedTenantId,
      );
      if (scopedItems.isNotEmpty) {
        return scopedItems;
      }

      // Keep screen usable in restrictive legacy datasets.
      return const [];
    }
  }

  @override
  Future<Pedido?> fetchById({
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
    final entity = Pedido.fromMap(data);
    if (entity.tenantId != normalizedTenantId) {
      return null;
    }
    return entity;
  }

  @override
  Future<void> save(Pedido entity) {
    _tenantCache.remove(entity.tenantId.trim());
    return _collection.doc(entity.id).set(entity.toMap());
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
