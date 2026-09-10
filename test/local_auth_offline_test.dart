import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartsfa/src/core/models/cliente_pre_cadastro.dart';
import 'package:smartsfa/src/core/models/domain_types.dart';
import 'package:smartsfa/src/core/services/offline_sync_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads queued pre-cadastros for the current personal workspace only', () async {
    SharedPreferences.setMockInitialValues({});

    final personalEntity = ClientePreCadastro(
      id: 'pre-personal-1',
      tenantId: 'personal_vendedor',
      nome: 'Cliente pessoal',
      documento: '12345678000199',
      status: PreRegistrationStatus.pending,
      requestedByUid: 'uid-1',
      origemCadastro: CustomerOrigin.manual,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final tenantEntity = ClientePreCadastro(
      id: 'pre-tenant-1',
      tenantId: 'amatools',
      nome: 'Cliente do tenant',
      documento: '98765432000188',
      status: PreRegistrationStatus.pending,
      requestedByUid: 'uid-2',
      origemCadastro: CustomerOrigin.manual,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await OfflineSyncQueue.enqueue(
      type: 'cliente_pre_cadastro',
      tenantId: personalEntity.tenantId,
      payload: personalEntity.toMap(),
    );
    await OfflineSyncQueue.enqueue(
      type: 'cliente_pre_cadastro',
      tenantId: tenantEntity.tenantId,
      payload: tenantEntity.toMap(),
    );

    final queued = await OfflineSyncQueue.readQueuedPreCadastros(
      tenantId: 'personal_vendedor',
      includePersonalWorkspace: true,
    );

    expect(queued.map((item) => item.id), contains('pre-personal-1'));
    expect(queued.map((item) => item.id), isNot(contains('pre-tenant-1')));
  });

  test('keeps visible personal-workspace queued pre-cadastros even when tenant is blank', () async {
    SharedPreferences.setMockInitialValues({});

    final personalEntity = ClientePreCadastro(
      id: 'pre-blank-tenant',
      tenantId: '',
      nome: 'Cliente sem tenant',
      documento: '11222333000144',
      status: PreRegistrationStatus.pending,
      requestedByUid: 'uid-personal',
      origemCadastro: CustomerOrigin.manual,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await OfflineSyncQueue.enqueue(
      type: 'cliente_pre_cadastro',
      tenantId: '',
      payload: personalEntity.toMap(),
    );

    final queued = await OfflineSyncQueue.readQueuedPreCadastros(
      tenantId: 'personal_uid-personal',
      includePersonalWorkspace: true,
      requestedByUid: 'uid-personal',
    );

    expect(queued.map((item) => item.id), contains('pre-blank-tenant'));
  });
}
