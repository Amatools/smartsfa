import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsfa/src/core/services/catalog_incremental_sync_service.dart';

void main() {
  group('CatalogIncrementalSyncService', () {
    late FakeFirebaseFirestore firestore;
    late CatalogIncrementalSyncService service;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      firestore = FakeFirebaseFirestore();
      service = CatalogIncrementalSyncService(firestore);
    });

    test('pulls only tenant delta and advances cursor', () async {
      await firestore.collection('produtos').doc('p1').set({
        'id': 'p1',
        'tenantId': 'tenant_a',
        'descricao': 'Produto A',
        'syncVersion': 1,
      });
      await firestore.collection('produtos').doc('p2').set({
        'id': 'p2',
        'tenantId': 'tenant_a',
        'descricao': 'Produto B',
        'syncVersion': 2,
      });
      await firestore.collection('produtos').doc('p3').set({
        'id': 'p3',
        'tenantId': 'tenant_b',
        'descricao': 'Produto C',
        'syncVersion': 99,
      });

      final first = await service.pullDelta(
        tenantId: 'tenant_a',
        module: CatalogSyncModule.produtos,
      );

      expect(first.previousCursor, 0);
      expect(first.nextCursor, 2);
      expect(first.items.map((item) => item.id), ['p1', 'p2']);

      final second = await service.pullDelta(
        tenantId: 'tenant_a',
        module: CatalogSyncModule.produtos,
      );

      expect(second.previousCursor, 2);
      expect(second.nextCursor, 2);
      expect(second.items, isEmpty);

      await firestore.collection('produtos').doc('p4').set({
        'id': 'p4',
        'tenantId': 'tenant_a',
        'descricao': 'Produto D',
        'syncVersion': 3,
      });

      final third = await service.pullDelta(
        tenantId: 'tenant_a',
        module: CatalogSyncModule.produtos,
      );

      expect(third.previousCursor, 2);
      expect(third.nextCursor, 3);
      expect(third.items.map((item) => item.id), ['p4']);
    });

    test('resets module cursor', () async {
      await firestore.collection('tax_rules').doc('r1').set({
        'id': 'r1',
        'tenantId': 'tenant_a',
        'status': 'active',
        'ufOrigem': 'SP',
        'ufDestino': 'MG',
        'syncVersion': 5,
      });

      final first = await service.pullDelta(
        tenantId: 'tenant_a',
        module: CatalogSyncModule.taxRules,
      );
      expect(first.nextCursor, 5);

      await service.resetModuleCursor(
        tenantId: 'tenant_a',
        module: CatalogSyncModule.taxRules,
      );

      final second = await service.pullDelta(
        tenantId: 'tenant_a',
        module: CatalogSyncModule.taxRules,
      );
      expect(second.previousCursor, 0);
      expect(second.items.length, 1);
    });

    test('bootstraps docs without syncVersion only once', () async {
      await firestore.collection('clientes').doc('c1').set({
        'id': 'c1',
        'tenantId': 'tenant_a',
        'nome': 'Cliente A',
      });

      final first = await service.pullDelta(
        tenantId: 'tenant_a',
        module: CatalogSyncModule.clientes,
      );

      expect(first.items.length, 1);
      expect(first.nextCursor, 0);

      final second = await service.pullDelta(
        tenantId: 'tenant_a',
        module: CatalogSyncModule.clientes,
      );

      expect(second.items, isEmpty);
      expect(second.previousCursor, 0);
      expect(second.nextCursor, 0);
    });

    test('returns tombstone deletions in incremental pull', () async {
      await firestore.collection('tax_rules').doc('r1').set({
        'id': 'r1',
        'tenantId': 'tenant_a',
        'status': 'active',
        'syncVersion': 1,
      });

      final first = await service.pullDelta(
        tenantId: 'tenant_a',
        module: CatalogSyncModule.taxRules,
      );
      expect(first.nextCursor, 1);
      expect(first.items.length, 1);
      expect(first.items.first.isDeleted, isFalse);

      await firestore.collection('tax_rules').doc('r1').set({
        'id': 'r1',
        'tenantId': 'tenant_a',
        'status': 'inactive',
        'syncVersion': 2,
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
      });

      final second = await service.pullDelta(
        tenantId: 'tenant_a',
        module: CatalogSyncModule.taxRules,
      );

      expect(second.previousCursor, 1);
      expect(second.nextCursor, 2);
      expect(second.items.length, 1);
      expect(second.items.first.id, 'r1');
      expect(second.items.first.isDeleted, isTrue);
    });
  });
}
