import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/cliente.dart';
import '../../repositories/cliente_repository.dart';
import 'firestore_map_normalizer.dart';
import 'firestore_sync_metadata.dart';

class FirestoreClienteRepository implements ClienteRepository {
  FirestoreClienteRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final Map<String, List<Cliente>> _tenantCache = <String, List<Cliente>>{};

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('clientes');

  List<Cliente> _mapAndSortClientes(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final items = snapshot.docs
        .map((doc) {
          final data = normalizeFirestoreMap(doc.data());
          data.putIfAbsent('id', () => doc.id);
          return Cliente.fromMap(data);
        })
        .where((cliente) => cliente.deletedAt == null)
        .toList();
    items.sort((a, b) => a.nome.compareTo(b.nome));
    return items;
  }

  void _setTenantCache(String tenantId, List<Cliente> items) {
    _tenantCache[tenantId] = List<Cliente>.unmodifiable(items);
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

    // First pass: direct scope-by-uid probes often work even when membership
    // is unavailable or legacy data is partially inconsistent.
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
      // Membership read is best-effort. We still keep direct uid-scope queries.
    }

    return queries;
  }

  Future<List<Cliente>> _fetchScopedFallbackClientes({
    required String tenantId,
  }) async {
    final queries = await _buildScopedFallbackQueries(tenantId: tenantId);
    if (queries.isEmpty) {
      return const [];
    }

    final byId = <String, Cliente>{};
    FirebaseException? lastPermissionDenied;

    for (final query in queries) {
      try {
        final snapshot = await query.get();
        for (final doc in snapshot.docs) {
          final data = normalizeFirestoreMap(doc.data());
          data.putIfAbsent('id', () => doc.id);
          final cliente = Cliente.fromMap(data);
          if (cliente.deletedAt != null) {
            continue;
          }
          if (cliente.id.trim().isEmpty) {
            continue;
          }
          byId[cliente.id] = cliente;
        }
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          lastPermissionDenied = error;
          continue;
        }

        if (error.code == 'failed-precondition') {
          // Missing index for one scope query should not block other fallbacks.
          continue;
        }

        rethrow;
      }
    }

    if (byId.isNotEmpty) {
      final items = byId.values.toList();
      items.sort((a, b) => a.nome.compareTo(b.nome));
      _setTenantCache(tenantId, items);
      return items;
    }

    if (lastPermissionDenied != null) {
      throw lastPermissionDenied;
    }

    return const [];
  }

  Stream<List<Cliente>> _watchScopedFallbackClientes({
    required String tenantId,
  }) {
    return Stream.multi((controller) async {
      final queries = await _buildScopedFallbackQueries(tenantId: tenantId);
      if (queries.isEmpty) {
        controller.add(const []);
        controller.close();
        return;
      }

      final byQuery = <int, Map<String, Cliente>>{
        for (var index = 0; index < queries.length; index++)
          index: <String, Cliente>{},
      };
      final subscriptions =
          <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

      void emitMerged() {
        final byId = <String, Cliente>{};
        for (final partial in byQuery.values) {
          byId.addAll(partial);
        }

        final merged = byId.values.toList()
          ..sort((a, b) => a.nome.compareTo(b.nome));
        _setTenantCache(tenantId, merged);
        controller.add(merged);
      }

      for (var index = 0; index < queries.length; index++) {
        final scopedIndex = index;
        final subscription = queries[scopedIndex].snapshots().listen(
          (snapshot) {
            final current = <String, Cliente>{};
            for (final doc in snapshot.docs) {
              final data = normalizeFirestoreMap(doc.data());
              data.putIfAbsent('id', () => doc.id);
              final cliente = Cliente.fromMap(data);
              if (cliente.deletedAt != null) {
                continue;
              }
              if (cliente.id.trim().isEmpty) {
                continue;
              }
              current[cliente.id] = cliente;
            }
            byQuery[scopedIndex] = current;
            emitMerged();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (error is FirebaseException &&
                (error.code == 'permission-denied' ||
                    error.code == 'failed-precondition')) {
              byQuery[scopedIndex] = <String, Cliente>{};
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
  Stream<List<Cliente>> watchAll({required String tenantId}) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const []);
    }

    return Stream.multi((controller) {
      StreamSubscription<List<Cliente>>? fallbackSubscription;

      final primarySubscription = _collection
          .where('tenantId', isEqualTo: normalizedTenantId)
          .snapshots()
          .map(_mapAndSortClientes)
          .listen(
            (items) {
              _setTenantCache(normalizedTenantId, items);
              controller.add(items);
            },
            onError: (Object error, StackTrace stackTrace) {
              final isPermissionDenied =
                  error is FirebaseException &&
                  error.code == 'permission-denied';
              if (isPermissionDenied && fallbackSubscription == null) {
                fallbackSubscription =
                    _watchScopedFallbackClientes(tenantId: normalizedTenantId)
                        .listen((items) {
                          _setTenantCache(normalizedTenantId, items);
                          controller.add(items);
                        }, onError: controller.addError);
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
  Future<List<Cliente>> fetchAll({required String tenantId}) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const [];
    }

    final cached = _tenantCache[normalizedTenantId];
    if (cached != null) {
      return List<Cliente>.from(cached);
    }

    try {
      final snapshot = await _collection
          .where('tenantId', isEqualTo: normalizedTenantId)
          .get();
      final items = _mapAndSortClientes(snapshot);
      _setTenantCache(normalizedTenantId, items);
      return items;
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }

      final scopedItems = await _fetchScopedFallbackClientes(
        tenantId: normalizedTenantId,
      );
      if (scopedItems.isNotEmpty) {
        return scopedItems;
      }

      // Preserve UX continuity in restrictive/legacy datasets by returning an
      // empty result instead of hard-failing the screen. Caller may use local
      // cache as a secondary source.
      return const [];
    }
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
    final entity = Cliente.fromMap(data);
    if (entity.tenantId != normalizedTenantId) {
      return null;
    }
    if (entity.deletedAt != null) {
      return null;
    }
    return entity;
  }

  @override
  Future<void> save(Cliente entity) {
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

    final payload = buildSyncDeletePayload(source: existing.toMap());
    await _collection.doc(id).set(payload, SetOptions(merge: true));
    _tenantCache.remove(tenantId.trim());
  }
}
