import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/core/data/firestore/firestore_cliente_repository.dart';
import 'package:smartsfa/src/core/data/firestore/firestore_pedido_repository.dart';
import 'package:smartsfa/src/core/data/firestore/firestore_produto_repository.dart';

void main() {
  group('Firestore tenant-scoped repositories', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test(
      'Cliente repository filters by tenant and normalizes timestamps',
      () async {
        await firestore.collection('clientes').doc('c1').set({
          'id': 'c1',
          'tenantId': 'tenant_a',
          'nome': 'Cliente A',
          'documento': '11.111.111/0001-11',
          'origemCadastro': 'manual',
          'status': 'approved',
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2, 3, 4)),
        });
        await firestore.collection('clientes').doc('c2').set({
          'id': 'c2',
          'tenantId': 'tenant_b',
          'nome': 'Cliente B',
          'documento': '22.222.222/0001-22',
          'origemCadastro': 'erp',
          'status': 'synchronized',
        });

        final repository = FirestoreClienteRepository(firestore);
        final items = await repository.fetchAll(tenantId: 'tenant_a');

        expect(items, hasLength(1));
        expect(items.first.id, 'c1');
        expect(items.first.createdAt, isNotNull);
      },
    );

    test('Produto repository filters by tenant', () async {
      await firestore.collection('produtos').doc('p1').set({
        'id': 'p1',
        'tenantId': 'tenant_a',
        'codigoInterno': 'P-A',
        'descricao': 'Produto A',
        'origemCadastro': 'manual',
        'status': 'active',
      });
      await firestore.collection('produtos').doc('p2').set({
        'id': 'p2',
        'tenantId': 'tenant_b',
        'codigoInterno': 'P-B',
        'descricao': 'Produto B',
        'origemCadastro': 'erp',
        'status': 'active',
      });

      final repository = FirestoreProdutoRepository(firestore);
      final items = await repository.fetchAll(tenantId: 'tenant_a');

      expect(items, hasLength(1));
      expect(items.first.id, 'p1');
    });

    test(
      'Pedido repository maps nested customer reference and filters by tenant',
      () async {
        await firestore.collection('pedidos').doc('o1').set({
          'id': 'o1',
          'tenantId': 'tenant_a',
          'origemPedido': 'manual',
          'statusFila': 'pendente_envio',
          'clienteReferencia': {
            'id': 'c1',
            'type': 'official',
            'nomeSnapshot': 'Cliente A',
            'documentoSnapshot': '11.111.111/0001-11',
          },
        });
        await firestore.collection('pedidos').doc('o2').set({
          'id': 'o2',
          'tenantId': 'tenant_b',
          'origemPedido': 'manual',
          'statusFila': 'pendente_envio',
        });

        final repository = FirestorePedidoRepository(firestore);
        final items = await repository.fetchAll(tenantId: 'tenant_a');

        expect(items, hasLength(1));
        expect(items.first.id, 'o1');
        expect(items.first.clienteReferencia?.nomeSnapshot, 'Cliente A');
      },
    );
  });
}
