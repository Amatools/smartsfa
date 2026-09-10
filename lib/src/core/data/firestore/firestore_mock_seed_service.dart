import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/app_identity.dart';
import '../in_memory/demo_workspace.dart';

class FirestoreMockSeedResult {
  const FirestoreMockSeedResult({
    required this.seededClientes,
    required this.seededProdutos,
    required this.seededPedidos,
  });

  final int seededClientes;
  final int seededProdutos;
  final int seededPedidos;

  bool get anySeeded =>
      seededClientes > 0 || seededProdutos > 0 || seededPedidos > 0;
}

class FirestoreMockSeedService {
  FirestoreMockSeedService(this._firestore);

  final FirebaseFirestore _firestore;

  Future<FirestoreMockSeedResult> seedIfEmpty({
    required AppIdentity identity,
    required String actorUid,
  }) async {
    final tenantId = identity.tenantId.trim();
    final normalizedActorUid = actorUid.trim();
    if (tenantId.isEmpty || normalizedActorUid.isEmpty) {
      return const FirestoreMockSeedResult(
        seededClientes: 0,
        seededProdutos: 0,
        seededPedidos: 0,
      );
    }

    final workspace = DemoWorkspace.seeded(identity);
    final seededClientes = await _seedClientesIfEmpty(
      tenantId: tenantId,
      actorUid: normalizedActorUid,
      workspace: workspace,
    );
    final seededProdutos = await _seedProdutosIfEmpty(
      tenantId: tenantId,
      workspace: workspace,
    );
    final seededPedidos = await _seedPedidosIfEmpty(
      tenantId: tenantId,
      actorUid: normalizedActorUid,
      workspace: workspace,
    );

    return FirestoreMockSeedResult(
      seededClientes: seededClientes,
      seededProdutos: seededProdutos,
      seededPedidos: seededPedidos,
    );
  }

  Future<int> _seedClientesIfEmpty({
    required String tenantId,
    required String actorUid,
    required DemoWorkspace workspace,
  }) async {
    final first = await _firestore
        .collection('clientes')
        .where('tenantId', isEqualTo: tenantId)
        .limit(1)
        .get();
    if (first.docs.isNotEmpty) {
      return 0;
    }

    final seedItems = await workspace.clientes.fetchAll(tenantId: tenantId);
    final batch = _firestore.batch();
    for (final item in seedItems) {
      final docRef = _firestore.collection('clientes').doc(item.id);
      final normalized = item.copyWith(
        tenantId: tenantId,
        ownerId: actorUid,
        gerenteId: actorUid,
        representanteId: actorUid,
        vendedorId: actorUid,
      );
      batch.set(docRef, normalized.toMap(), SetOptions(merge: true));
    }
    await batch.commit();
    return seedItems.length;
  }

  Future<int> _seedProdutosIfEmpty({
    required String tenantId,
    required DemoWorkspace workspace,
  }) async {
    final first = await _firestore
        .collection('produtos')
        .where('tenantId', isEqualTo: tenantId)
        .limit(1)
        .get();
    if (first.docs.isNotEmpty) {
      return 0;
    }

    final seedItems = await workspace.produtos.fetchAll(tenantId: tenantId);
    final batch = _firestore.batch();
    for (final item in seedItems) {
      final docRef = _firestore.collection('produtos').doc(item.id);
      final normalized = item.copyWith(tenantId: tenantId);
      batch.set(docRef, normalized.toMap(), SetOptions(merge: true));
    }
    await batch.commit();
    return seedItems.length;
  }

  Future<int> _seedPedidosIfEmpty({
    required String tenantId,
    required String actorUid,
    required DemoWorkspace workspace,
  }) async {
    final first = await _firestore
        .collection('pedidos')
        .where('tenantId', isEqualTo: tenantId)
        .limit(1)
        .get();
    if (first.docs.isNotEmpty) {
      return 0;
    }

    final seedItems = await workspace.pedidos.fetchAll(tenantId: tenantId);
    final batch = _firestore.batch();
    for (final item in seedItems) {
      final docRef = _firestore.collection('pedidos').doc(item.id);
      final normalized = item.copyWith(
        tenantId: tenantId,
        ownerId: actorUid,
        gerenteId: actorUid,
        representanteId: actorUid,
        vendedorId: actorUid,
      );
      batch.set(docRef, normalized.toMap(), SetOptions(merge: true));
    }
    await batch.commit();
    return seedItems.length;
  }
}
