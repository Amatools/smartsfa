import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartsfa/src/core/data/in_memory/in_memory_cliente_repository.dart';
import 'package:smartsfa/src/core/models/app_identity.dart';
import 'package:smartsfa/src/core/models/cliente_pre_cadastro.dart';
import 'package:smartsfa/src/core/models/domain_types.dart';
import 'package:smartsfa/src/core/services/offline_sync_queue.dart';
import 'package:smartsfa/src/features/clientes/presentation/pages/clientes_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('clientes page exposes a pre-cadastro action', (tester) async {
    final identity = AppIdentity(
      tenantId: 'tenant-1',
      userLabel: 'Aureo',
      role: 'owner',
      tenantName: 'Amatools',
      isMock: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ClientesPage(
          identity: identity,
          repository: InMemoryClienteRepository(),
          preCadastroRepository: null,
        ),
      ),
    );

    expect(find.text('Pré-cadastro'), findsWidgets);
    expect(find.text('Novo pré-cadastro'), findsOneWidget);

    await tester.tap(find.text('Novo pré-cadastro'));
    await tester.pumpAndSettle();

    expect(find.text('Novo pré-cadastro'), findsWidgets);
  });

  test('removes orphan approved pre-cadastro records so they can be reused', () async {
    final entity = ClientePreCadastro(
      id: 'orphan-1',
      tenantId: 'tenant-1',
      nome: 'Empresa Orfã',
      documento: '12345678000199',
      email: 'orfao@example.com',
      telefone: '11999999999',
      logradouro: 'Rua A',
      numero: '10',
      bairro: 'Centro',
      cidade: 'São Paulo',
      estado: 'SP',
      cep: '01000-000',
      pais: 'Brasil',
      status: PreRegistrationStatus.approved,
      requestedByUid: 'u-1',
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    await OfflineSyncQueue.enqueue(
      type: 'cliente_pre_cadastro',
      tenantId: 'tenant-1',
      payload: entity.toMap(),
    );

    final removed = await OfflineSyncQueue.removeOrphanApprovedPreCadastros(
      tenantId: 'tenant-1',
    );

    expect(removed, 1);
    final remaining = await OfflineSyncQueue.readLocalPreCadastroRecords(
      tenantId: 'tenant-1',
    );
    expect(remaining, isEmpty);
  });
}
