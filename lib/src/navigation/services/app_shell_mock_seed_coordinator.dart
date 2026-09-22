import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/data/firestore/firestore_mock_seed_service.dart';
import '../../core/diagnostics/app_diagnostics.dart';
import '../../core/models/app_identity.dart';

class AppShellMockSeedCoordinator {
  const AppShellMockSeedCoordinator();

  Future<String?> seedIfNeeded({
    required bool isDebugMode,
    required bool enableFirestoreMockSeed,
    required AppIdentity identity,
    required FirebaseFirestore firestore,
    required String? actorUid,
  }) async {
    if (!isDebugMode || !enableFirestoreMockSeed) {
      return null;
    }

    final role = identity.role.trim().toLowerCase();
    if (role != 'owner' && role != 'platform_admin') {
      return null;
    }

    final normalizedActorUid = (actorUid ?? '').trim();
    if (normalizedActorUid.isEmpty) {
      return null;
    }

    try {
      final seedService = FirestoreMockSeedService(firestore);
      final result = await seedService.seedIfEmpty(
        identity: identity,
        actorUid: normalizedActorUid,
      );

      if (!result.anySeeded) {
        return null;
      }

      return 'Mock no banco carregado: ${result.seededClientes} clientes, '
          '${result.seededProdutos} produtos, ${result.seededPedidos} pedidos.';
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'app_shell.seed_mocks',
        message: 'Falha ao carregar dados de exemplo (mock) no Firestore.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
