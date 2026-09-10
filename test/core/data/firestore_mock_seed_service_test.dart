import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/core/data/firestore/firestore_mock_seed_service.dart';
import 'package:smartsfa/src/core/models/app_identity.dart';

void main() {
  test(
    'seeds mock data only once per tenant when collections are empty',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreMockSeedService(firestore);

      const identity = AppIdentity(
        tenantId: 'amatools',
        userLabel: 'owner@amatools.local',
        role: 'owner',
        tenantName: 'Amatools',
        isMock: false,
      );

      final first = await service.seedIfEmpty(
        identity: identity,
        actorUid: 'u_owner',
      );

      expect(first.seededClientes, 2);
      expect(first.seededProdutos, 2);
      expect(first.seededPedidos, 2);

      final clientes = await firestore
          .collection('clientes')
          .where('tenantId', isEqualTo: 'amatools')
          .get();
      final produtos = await firestore
          .collection('produtos')
          .where('tenantId', isEqualTo: 'amatools')
          .get();
      final pedidos = await firestore
          .collection('pedidos')
          .where('tenantId', isEqualTo: 'amatools')
          .get();

      expect(clientes.docs, hasLength(2));
      expect(produtos.docs, hasLength(2));
      expect(pedidos.docs, hasLength(2));

      final second = await service.seedIfEmpty(
        identity: identity,
        actorUid: 'u_owner',
      );
      expect(second.seededClientes, 0);
      expect(second.seededProdutos, 0);
      expect(second.seededPedidos, 0);
    },
  );
}
