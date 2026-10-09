import '../../core/diagnostics/app_diagnostics.dart';
import '../../core/models/app_identity.dart';
import '../../core/models/cliente.dart';
import '../../core/models/cliente_pre_cadastro.dart';
import '../../core/models/pedido.dart';
import '../../core/repositories/cliente_pre_cadastro_repository.dart';
import '../../core/repositories/cliente_repository.dart';
import '../../core/repositories/pedido_repository.dart';
import '../../core/services/offline_sync_queue.dart';

class AppShellOfflineSyncCoordinator {
  const AppShellOfflineSyncCoordinator();

  Future<void> syncPendingChanges({
    required AppIdentity identity,
    required ClienteRepository clienteRepository,
    required ClientePreCadastroRepository preCadastroRepository,
    required PedidoRepository pedidoRepository,
  }) async {
    final pending = await OfflineSyncQueue.readAll();
    final pendingDeletesPreview = await OfflineSyncQueue.readPendingDeletes();
    if (pending.isEmpty && pendingDeletesPreview.isEmpty) {
      return;
    }

    for (final item in pending) {
      if (item.synced) {
        continue;
      }

      if (item.type == 'cliente_pre_cadastro') {
        await _syncPreCadastroItem(
          item,
          identity: identity,
          preCadastroRepository: preCadastroRepository,
        );
        continue;
      }

      if (item.type == 'cliente') {
        await _syncClienteItem(
          item,
          identity: identity,
          clienteRepository: clienteRepository,
        );
        continue;
      }

      if (item.type == 'pedido') {
        await _syncPedidoItem(
          item,
          identity: identity,
          pedidoRepository: pedidoRepository,
        );
      }
    }

    for (final tombstone in pendingDeletesPreview) {
      await _syncDeleteTombstone(
        tombstone,
        identity: identity,
        clienteRepository: clienteRepository,
        preCadastroRepository: preCadastroRepository,
        pedidoRepository: pedidoRepository,
      );
    }
  }

  Future<void> _syncPreCadastroItem(
    OfflineSyncQueueItem item, {
    required AppIdentity identity,
    required ClientePreCadastroRepository preCadastroRepository,
  }) async {
    try {
      final payload = item.payloadMap;
      final entity = ClientePreCadastro.fromMap(payload);
      if (entity.tenantId == identity.tenantId ||
          identity.isPersonalWorkspace) {
        await preCadastroRepository.save(entity);
        await OfflineSyncQueue.markSynced(item.id);
      }
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'app_shell.sync.pre_cadastro',
        message: 'Falha ao sincronizar pre-cadastro em segundo plano.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _syncClienteItem(
    OfflineSyncQueueItem item, {
    required AppIdentity identity,
    required ClienteRepository clienteRepository,
  }) async {
    try {
      final payload = item.payloadMap;
      final entity = Cliente.fromMap(payload);
      if (entity.tenantId == identity.tenantId ||
          identity.isPersonalWorkspace) {
        await clienteRepository.save(entity);
        await OfflineSyncQueue.markSynced(item.id);
      }
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'app_shell.sync.cliente',
        message: 'Falha ao sincronizar cliente em segundo plano.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _syncPedidoItem(
    OfflineSyncQueueItem item, {
    required AppIdentity identity,
    required PedidoRepository pedidoRepository,
  }) async {
    try {
      final payload = item.payloadMap;
      final entity = Pedido.fromMap(payload);
      if (entity.tenantId == identity.tenantId ||
          identity.isPersonalWorkspace) {
        await pedidoRepository.save(entity);
        await OfflineSyncQueue.markSynced(item.id);
      }
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'app_shell.sync.pedido',
        message: 'Falha ao sincronizar pedido em segundo plano.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _syncDeleteTombstone(
    Map<String, dynamic> tombstone, {
    required AppIdentity identity,
    required ClienteRepository clienteRepository,
    required ClientePreCadastroRepository preCadastroRepository,
    required PedidoRepository pedidoRepository,
  }) async {
    final type = tombstone['type']?.toString();
    final id = tombstone['id']?.toString() ?? '';
    final tenantId = tombstone['tenantId']?.toString() ?? '';
    if (id.isEmpty) {
      return;
    }
    if (tenantId != identity.tenantId && !identity.isPersonalWorkspace) {
      return;
    }

    try {
      if (type == 'cliente_pre_cadastro') {
        await preCadastroRepository.delete(tenantId: tenantId, id: id);
        await OfflineSyncQueue.clearTombstone(id);
      } else if (type == 'cliente') {
        await clienteRepository.delete(tenantId: tenantId, id: id);
        await OfflineSyncQueue.clearTombstone(id);
      } else if (type == 'pedido') {
        await pedidoRepository.delete(tenantId: tenantId, id: id);
        await OfflineSyncQueue.clearTombstone(id);
      }
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'app_shell.sync.delete_retry',
        message:
            'Falha ao confirmar exclusao remota de $type/$id em segundo plano.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
