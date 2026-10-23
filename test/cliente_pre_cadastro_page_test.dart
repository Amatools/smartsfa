import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartsfa/src/core/models/cliente_pre_cadastro.dart';
import 'package:smartsfa/src/core/models/domain_types.dart';
import 'package:smartsfa/src/core/repositories/cliente_pre_cadastro_repository.dart';
import 'package:smartsfa/src/core/services/offline_sync_queue.dart';
import 'package:smartsfa/src/core/services/pre_cadastro_save_service.dart';

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

  test('saveOrQueue keeps pre-cadastro in local queue when connectivity is treated as offline', () async {
    final repository = _FakeRepository();
    final now = DateTime.now();
    final entity = ClientePreCadastro(
      id: 'pre-test-offline-widget-parity',
      tenantId: 'personal_test-uid',
      nome: 'Cliente Teste Fluxo',
      documento: '07228424000157',
      tipoPessoa: 'pj',
      canal: 'vendedor',
      celular: '11999999999',
      taxRegime: defaultTaxRegime,
      origemCadastro: CustomerOrigin.manual,
      status: PreRegistrationStatus.pending,
      requestedByUid: 'test-uid',
      createdAt: now,
      updatedAt: now,
    );

    final result = await PreCadastroSaveService.saveOrQueue(
      entity: entity,
      repository: repository,
      tenantId: 'personal_test-uid',
      isOffline: true,
    );

    final queuedRaw = await OfflineSyncQueue.readAll();
    final hasQueuedPreCadastro = queuedRaw.any((item) {
      if (item.type != 'cliente_pre_cadastro') {
        return false;
      }

      final payloadId = (item.payload['id'] ?? '').toString();
      return payloadId == entity.id;
    });

    expect(result.savedLocally, isTrue);
    expect(result.savedRemotely, isFalse);
    expect(hasQueuedPreCadastro, isTrue);
    expect(repository.saved, isEmpty);
  });
}
