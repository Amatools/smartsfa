import '../../../../core/models/cliente.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/repositories/cliente_repository.dart';
import '../../../../core/services/catalog_incremental_sync_service.dart';
import '../../../../core/services/catalog_snapshot_store.dart';

/// Resolves the list of approved clientes for a tenant, preferring the local
/// catalog snapshot cache (offline-first) and falling back to the remote
/// [ClienteRepository] when no cached snapshot is available.
///
/// Extracted from `_PedidoInlineEditorState._resolveApprovedClientes` to
/// isolate this (pure, repository-backed) lookup from the surrounding
/// setState/ScaffoldMessenger orchestration.
class PedidoClienteLookupService {
  PedidoClienteLookupService({
    required this.clienteRepository,
    required this.catalogSnapshotStore,
  });

  final ClienteRepository clienteRepository;
  final CatalogSnapshotStore catalogSnapshotStore;

  Future<List<Cliente>> resolveApprovedClientes(String tenantId) async {
    final cachedPayloads = await catalogSnapshotStore.readAll(
      tenantId: tenantId,
      module: CatalogSyncModule.clientes,
    );
    if (cachedPayloads.isNotEmpty) {
      final cachedClientes = <Cliente>[];
      for (final payload in cachedPayloads) {
        try {
          cachedClientes.add(Cliente.fromMap(payload));
        } catch (_) {
          // Skip invalid cached payloads and fallback to repository when needed.
        }
      }

      final approvedCached =
          cachedClientes
              .where(
                (item) =>
                    item.status == CustomerStatus.approved &&
                    item.deletedAt == null,
              )
              .toList()
            ..sort(
              (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
            );
      if (approvedCached.isNotEmpty) {
        return approvedCached;
      }
    }

    final clientes = await clienteRepository.fetchAll(tenantId: tenantId);
    final approved =
        clientes
            .where((item) => item.status == CustomerStatus.approved)
            .toList()
          ..sort(
            (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
          );
    return approved;
  }
}
