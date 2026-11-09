import '../../models/tax_rule.dart';
import '../../repositories/tax_rule_repository.dart';
import '../../services/catalog_incremental_sync_service.dart';
import '../../services/catalog_snapshot_store.dart';

/// Decorator offline-first de leitura para `tax_rules`: tenta o snapshot
/// local (`CatalogSnapshotStore`, ja populado pelo sync automatico/manual via
/// `CatalogSyncModule.taxRules`) antes de recorrer ao repositorio remoto.
///
/// Motivo: o calculo de imposto do item de pedido (`ProductTaxEngineService`)
/// precisa funcionar 100% offline, igual a leitura de produtos no editor de
/// pedido (`_resolveProductsForEditor`), em vez de depender de uma consulta
/// ao vivo no Firestore toda vez que a tela de Pedidos e reaberta.
///
/// `fetchById`/`save`/`delete`/`watchAll` continuam delegados ao repositorio
/// remoto sem alteracao de comportamento (usados por telas de configuracao
/// de vida longa no portal web, que ja lidam bem com `.snapshots()` ao vivo).
class CatalogSnapshotTaxRuleRepository implements TaxRuleRepository {
  CatalogSnapshotTaxRuleRepository({
    required TaxRuleRepository remote,
    CatalogSnapshotStore? snapshotStore,
    // ignore: prefer_initializing_formals
  }) : _remote = remote,
       _snapshotStore = snapshotStore ?? CatalogSnapshotStore();

  final TaxRuleRepository _remote;
  final CatalogSnapshotStore _snapshotStore;

  @override
  Future<List<TaxRule>> fetchAll({required String tenantId}) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const <TaxRule>[];
    }

    final cachedPayloads = await _snapshotStore.readAll(
      tenantId: normalizedTenantId,
      module: CatalogSyncModule.taxRules,
    );
    // ignore: avoid_print
    print(
      '[TAX-DEBUG] snapshot readAll tenant=$normalizedTenantId '
      'cachedPayloads=${cachedPayloads.length}',
    );

    if (cachedPayloads.isNotEmpty) {
      final cachedRules = <TaxRule>[];
      for (final payload in cachedPayloads) {
        try {
          final docType = (payload['docType'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (docType == 'operation_profile') {
            continue;
          }
          final rule = TaxRule.fromMap(payload);
          if (rule.deletedAt != null) {
            continue;
          }
          cachedRules.add(rule);
        } catch (e) {
          // ignore: avoid_print
          print('[TAX-DEBUG] snapshot payload parse error: $e | payload=$payload');
        }
      }

      if (cachedRules.isNotEmpty) {
        cachedRules.sort((a, b) => b.priority.compareTo(a.priority));
        // ignore: avoid_print
        print('[TAX-DEBUG] snapshot cachedRules=${cachedRules.length} -> usando local');
        return cachedRules;
      }
    }

    // Snapshot local vazio (ex.: antes do primeiro sync) -> mantem o
    // comportamento anterior de cair para leitura remota.
    // ignore: avoid_print
    print('[TAX-DEBUG] snapshot vazio/sem regras validas -> fallback remoto');
    return _remote.fetchAll(tenantId: normalizedTenantId);
  }

  @override
  Stream<List<TaxRule>> watchAll({required String tenantId}) =>
      _remote.watchAll(tenantId: tenantId);

  @override
  Future<TaxRule?> fetchById({required String tenantId, required String id}) =>
      _remote.fetchById(tenantId: tenantId, id: id);

  @override
  Future<void> save(TaxRule entity) => _remote.save(entity);

  @override
  Future<void> delete({required String tenantId, required String id}) =>
      _remote.delete(tenantId: tenantId, id: id);
}
