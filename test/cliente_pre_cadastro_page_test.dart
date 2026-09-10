import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartsfa/src/core/models/cliente_pre_cadastro.dart';
import 'package:smartsfa/src/core/repositories/cliente_pre_cadastro_repository.dart';
import 'package:smartsfa/src/core/services/offline_sync_queue.dart';
import 'package:smartsfa/src/features/clientes/presentation/pages/cliente_pre_cadastro_page.dart';

class _FakeRepository implements ClientePreCadastroRepository {
  final List<ClientePreCadastro> saved = [];

  @override
  Stream<List<ClientePreCadastro>> watchAll({required String tenantId}) {
    return Stream.value(const []);
  }

  @override
  Future<List<ClientePreCadastro>> fetchAll({required String tenantId}) async {
    return const [];
  }

  @override
  Future<ClientePreCadastro?> fetchById({
    required String tenantId,
    required String id,
  }) async {
    return null;
  }

  @override
  Future<void> save(ClientePreCadastro entity) async {
    saved.add(entity);
  }

  @override
  Future<void> delete({required String tenantId, required String id}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'submitting the form ends up queued locally when connectivity cannot be resolved '
    '(no platform channel registered, exactly like a real permission/network failure)',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;

      final repository = _FakeRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ClientePreCadastroPage(
            tenantId: 'personal_test-uid',
            requestedByUid: 'test-uid',
            repository: repository,
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome / razao social *'),
        'Cliente Teste Fluxo',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'CPF / CNPJ *'),
        '12345678000199',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Celular'),
        '11999999999',
      );

      final submitButtonFinder = find.widgetWithText(
        FilledButton,
        'Salvar pré-cadastro',
      );

      // The connectivity check uses a real bounded timeout internally, so we
      // must drive real async time here instead of the fake test clock.
      await tester.runAsync(() async {
        await tester.tap(submitButtonFinder);
        await Future<void>.delayed(const Duration(seconds: 4));
      });
      await tester.pumpAndSettle();

      final queued = await OfflineSyncQueue.readQueuedPreCadastros(
        tenantId: 'personal_test-uid',
        includePersonalWorkspace: true,
      );

      expect(
        queued.any((item) => item.documento == '12345678000199'),
        isTrue,
        reason:
            'The pre-cadastro must land in the local queue even when the '
            'connectivity check throws, otherwise the data is silently lost.',
      );
    },
  );
}
