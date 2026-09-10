import '../diagnostics/app_diagnostics.dart';
import '../models/cliente_pre_cadastro.dart';
import '../repositories/cliente_pre_cadastro_repository.dart';
import 'offline_sync_queue.dart';

class PreCadastroSaveResult {
  const PreCadastroSaveResult({
    required this.savedRemotely,
    required this.savedLocally,
  });

  final bool savedRemotely;
  final bool savedLocally;

  bool get savedLocalOnly => savedLocally && !savedRemotely;
}

class PreCadastroSaveService {
  const PreCadastroSaveService._();

  /// Local-first save: the entity is always written to the on-device queue
  /// first, so it is guaranteed to be visible immediately regardless of
  /// connectivity or Firestore behavior. A remote save is then attempted as
  /// a best-effort background sync — on success the local record is kept
  /// (not deleted) and flagged as synced; on failure it simply stays
  /// unsynced until the next sync pass.
  static Future<PreCadastroSaveResult> saveOrQueue({
    required ClientePreCadastro entity,
    required ClientePreCadastroRepository repository,
    required String tenantId,
    required bool isOffline,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final safeTenantId = normalizedTenantId.isNotEmpty
        ? normalizedTenantId
        : entity.tenantId.trim();

    final safeEntity = entity.copyWith(
      tenantId: safeTenantId,
      requestedByUid: entity.requestedByUid.trim().isNotEmpty
          ? entity.requestedByUid
          : 'unknown_user',
    );

    await OfflineSyncQueue.enqueue(
      type: 'cliente_pre_cadastro',
      tenantId: safeTenantId,
      payload: safeEntity.toMap(),
    );

    if (isOffline) {
      return const PreCadastroSaveResult(
        savedRemotely: false,
        savedLocally: true,
      );
    }

    try {
      await repository.save(safeEntity);
      await OfflineSyncQueue.markSynced(safeEntity.id);
      return const PreCadastroSaveResult(
        savedRemotely: true,
        savedLocally: true,
      );
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'pre_cadastro.save',
        message: 'Falha ao sincronizar pr\u00e9-cadastro ${safeEntity.nome} com o Firebase.',
        error: error,
        stackTrace: stackTrace,
      );
      return const PreCadastroSaveResult(
        savedRemotely: false,
        savedLocally: true,
      );
    }
  }
}
