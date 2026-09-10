import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartsfa/src/core/models/cliente_pre_cadastro.dart';
import 'package:smartsfa/src/core/models/domain_types.dart';
import 'package:smartsfa/src/core/repositories/cliente_pre_cadastro_repository.dart';
import 'package:smartsfa/src/core/services/offline_sync_queue.dart';
import 'package:smartsfa/src/core/services/pre_cadastro_save_service.dart';

class _FakeRepository implements ClientePreCadastroRepository {
  _FakeRepository({this.shouldFail = false});

  final bool shouldFail;

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
    if (shouldFail) {
      throw StateError('forced failure');
    }
  }

  @override
  Future<void> delete({required String tenantId, required String id}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('smart_sfa_offline_sync_queue');
  });

  test('saveOrQueue keeps the record locally when offline', () async {
    final entity = ClientePreCadastro(
      id: 'pre-1',
      tenantId: 'personal_test',
      nome: 'Empresa Teste',
      documento: '12345678000199',
      status: PreRegistrationStatus.pending,
      requestedByUid: 'uid-1',
      origemCadastro: CustomerOrigin.manual,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final result = await PreCadastroSaveService.saveOrQueue(
      entity: entity,
      repository: _FakeRepository(),
      tenantId: 'personal_test',
      isOffline: true,
    );

    expect(result.savedRemotely, isFalse);
    expect(result.savedLocally, isTrue);
  });

  test('saveOrQueue queues when backend save throws', () async {
    final entity = ClientePreCadastro(
      id: 'pre-2',
      tenantId: 'personal_test',
      nome: 'Empresa Teste 2',
      documento: '12345678000100',
      status: PreRegistrationStatus.pending,
      requestedByUid: 'uid-2',
      origemCadastro: CustomerOrigin.manual,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final result = await PreCadastroSaveService.saveOrQueue(
      entity: entity,
      repository: _FakeRepository(shouldFail: true),
      tenantId: 'personal_test',
      isOffline: false,
    );

    expect(result.savedRemotely, isFalse);
    expect(result.savedLocally, isTrue);
  });

  test(
      'local-first: a pre-cadastro saved successfully online stays visible '
      'locally afterwards (never deleted from the local cache), only '
      'flagged as synced', () async {
    final entity = ClientePreCadastro(
      id: 'pre-3',
      tenantId: 'personal_test',
      nome: 'Empresa Teste 3',
      documento: '12345678000122',
      status: PreRegistrationStatus.pending,
      requestedByUid: 'uid-3',
      origemCadastro: CustomerOrigin.manual,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final result = await PreCadastroSaveService.saveOrQueue(
      entity: entity,
      repository: _FakeRepository(),
      tenantId: 'personal_test',
      isOffline: false,
    );

    expect(result.savedRemotely, isTrue);
    expect(result.savedLocally, isTrue);

    final records = await OfflineSyncQueue.readLocalPreCadastroRecords(
      tenantId: 'personal_test',
      includePersonalWorkspace: true,
    );

    final record = records.singleWhere((r) => r.entity.id == 'pre-3');
    expect(record.synced, isTrue);
  });
}
