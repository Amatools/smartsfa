import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/tabela_preco.dart';
import '../../../../core/models/tenant_entry_decision.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';

const String reservedSystemDefaultPriceTableName = 'tabela padrao';

class DefaultPriceTableGuard {
  static const String defaultPriceRegionId = 'default';
  static final Set<String> _autoEnsuredDefaultPriceScopes = <String>{};
  static final Set<String> _autoEnsuringDefaultPriceScopes = <String>{};
  static final Set<String> _autoSyncedDefaultPriceRowCounts = <String>{};
  static final Set<String> _autoSyncingDefaultPriceRowCounts = <String>{};

  static String normalizeDefaultPricingScopeKey(String? representedCompanyId) {
    final normalized = (representedCompanyId ?? '').trim();
    if (normalized.isEmpty) {
      return 'tenant_default';
    }
    return normalized.replaceAll('.', '_').replaceAll('/', '_');
  }

  static String legacyDefaultPricingScopeKey(String? representedCompanyId) {
    final normalized = (representedCompanyId ?? '').trim();
    if (normalized.isEmpty) {
      return 'tenant_default';
    }
    return normalized.replaceAll('/', '_');
  }

  static String defaultPriceTableIdForScope({
    required String tenantId,
    String? representedCompanyId,
  }) {
    final scopeKey = normalizeDefaultPricingScopeKey(representedCompanyId);
    final base = 'pt_default_${tenantId.trim()}';
    if (scopeKey == 'tenant_default') {
      return base;
    }
    return '${base}_$scopeKey';
  }

  static String legacyDefaultPriceTableIdForScope({
    required String tenantId,
    String? representedCompanyId,
  }) {
    final scopeKey = legacyDefaultPricingScopeKey(representedCompanyId);
    final base = 'pt_default_${tenantId.trim()}';
    if (scopeKey == 'tenant_default') {
      return base;
    }
    return '${base}_$scopeKey';
  }

  static String defaultProductCatalogIdForScope({
    required String tenantId,
    String? representedCompanyId,
  }) {
    final scopeKey = normalizeDefaultPricingScopeKey(representedCompanyId);
    return 'products_default_${tenantId.trim()}_$scopeKey';
  }

  static Future<void> ensureDefaultPriceTable({
    required AppIdentity identity,
    required TabelaPrecoRepository repository,
    required String? selectedRepresentedCompanyId,
    Set<String>? ensuredScopes,
  }) async {
    final scopeKey = normalizeDefaultPricingScopeKey(selectedRepresentedCompanyId);
    final legacyScopeKey = legacyDefaultPricingScopeKey(selectedRepresentedCompanyId);
    if (ensuredScopes?.contains(scopeKey) == true) {
      return;
    }

    final defaultPriceTableId = defaultPriceTableIdForScope(
      tenantId: identity.tenantId,
      representedCompanyId: selectedRepresentedCompanyId,
    );
    final representedCompanyId = (selectedRepresentedCompanyId ?? '').trim();

    try {
      final now = DateTime.now().toUtc();
      await repository.save(
        TabelaPreco(
          id: defaultPriceTableId,
          tenantId: identity.tenantId,
          nome: 'Tabela padrao',
          scopeType: scopeKey == 'tenant_default' ? 'general' : 'represented_company',
          scopeLabel: scopeKey == 'tenant_default'
              ? 'Tabela principal da conta'
              : 'Tabela padrao da representada',
          scopeIndex: <String>['default', scopeKey],
          origem: 'system',
          status: 'ativo',
          linkedEntityId: scopeKey == 'tenant_default' ? null : representedCompanyId,
          rowCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await FirebaseFirestore.instance.collection('tenants').doc(identity.tenantId).set(
        {
          'defaultPriceTableIds': {scopeKey: defaultPriceTableId},
          'defaultPriceRegionIds': {scopeKey: defaultPriceRegionId},
          'defaultProductCatalogIds': {
            scopeKey: defaultProductCatalogIdForScope(
              tenantId: identity.tenantId,
              representedCompanyId: selectedRepresentedCompanyId,
            ),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (legacyScopeKey != scopeKey) {
        final legacyDefaultPriceTableId = legacyDefaultPriceTableIdForScope(
          tenantId: identity.tenantId,
          representedCompanyId: selectedRepresentedCompanyId,
        );
        if (legacyDefaultPriceTableId != defaultPriceTableId) {
          final legacy = await repository.fetchById(
            tenantId: identity.tenantId,
            id: legacyDefaultPriceTableId,
          );
          if (legacy != null &&
              legacy.origem == 'system' &&
              legacy.nome.trim().toLowerCase() == reservedSystemDefaultPriceTableName) {
            await repository.delete(
              tenantId: identity.tenantId,
              id: legacyDefaultPriceTableId,
            );
          }
        }

        await FirebaseFirestore.instance.collection('tenants').doc(identity.tenantId).set(
          {
            'defaultPriceTableIds': {legacyScopeKey: FieldValue.delete()},
            'defaultPriceRegionIds': {legacyScopeKey: FieldValue.delete()},
            'defaultProductCatalogIds': {legacyScopeKey: FieldValue.delete()},
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      ensuredScopes?.add(scopeKey);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw StateError('permissao negada ao gravar em tabelas_preco');
      }
      rethrow;
    }
  }

  static void queueEnsureDefaultPriceTableIfMissing({
    required AppIdentity identity,
    required TenantEntryOption activeTenant,
    required TabelaPrecoRepository repository,
    required List<TabelaPreco> allTables,
    required String? selectedRepresentedCompanyId,
    required String? activeRepresentedCompanyName,
  }) {
    final workspaceType = activeTenant.workspaceType.trim().toLowerCase();
    final representedId = (selectedRepresentedCompanyId ?? '').trim();
    final representedName = (activeRepresentedCompanyName ?? '').trim();
    final representedContext = workspaceType == 'rep_workspace' || representedName.isNotEmpty;
    final shouldUseRepresentedScope = representedContext && representedId.isNotEmpty;

    final scopeKey = shouldUseRepresentedScope
        ? normalizeDefaultPricingScopeKey(representedId)
        : 'tenant_default';
    if (_autoEnsuredDefaultPriceScopes.contains(scopeKey) ||
        _autoEnsuringDefaultPriceScopes.contains(scopeKey)) {
      return;
    }

    final exists = allTables.any((table) {
      final isSystemDefault =
          table.origem.trim().toLowerCase() == 'system' &&
          table.nome.trim().toLowerCase() == reservedSystemDefaultPriceTableName;
      if (!isSystemDefault) {
        return false;
      }

      final linked = (table.linkedEntityId ?? '').trim();
      if (shouldUseRepresentedScope) {
        return linked == representedId;
      }
      return linked.isEmpty;
    });

    if (exists) {
      _autoEnsuredDefaultPriceScopes.add(scopeKey);
      return;
    }

    _autoEnsuringDefaultPriceScopes.add(scopeKey);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final now = DateTime.now().toUtc();
        final defaultTableId = defaultPriceTableIdForScope(
          tenantId: identity.tenantId,
          representedCompanyId: shouldUseRepresentedScope ? representedId : null,
        );

        await repository.save(
          TabelaPreco(
            id: defaultTableId,
            tenantId: identity.tenantId,
            nome: 'Tabela padrao',
            scopeType: shouldUseRepresentedScope ? 'represented_company' : 'general',
            scopeLabel: shouldUseRepresentedScope
                ? (representedName.isEmpty
                    ? 'Tabela padrao da representada'
                    : 'Tabela padrao - $representedName')
                : 'Tabela principal da conta',
            scopeIndex: <String>['default', scopeKey],
            origem: 'system',
            status: 'ativo',
            linkedEntityId: shouldUseRepresentedScope ? representedId : null,
            rowCount: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );

        await FirebaseFirestore.instance.collection('tenants').doc(identity.tenantId).set(
          {
            'defaultPriceTableIds': {scopeKey: defaultTableId},
            'defaultPriceRegionIds': {scopeKey: defaultPriceRegionId},
            'defaultProductCatalogIds': {
              scopeKey: defaultProductCatalogIdForScope(
                tenantId: identity.tenantId,
                representedCompanyId: shouldUseRepresentedScope ? representedId : null,
              ),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        _autoEnsuredDefaultPriceScopes.add(scopeKey);
      } catch (_) {
        // Best effort self-healing: if write fails, the UI remains readable.
      } finally {
        _autoEnsuringDefaultPriceScopes.remove(scopeKey);
      }
    });
  }

  static void queueSyncDefaultPriceTableRowCount({
    required AppIdentity identity,
    required TenantEntryOption activeTenant,
    required TabelaPrecoRepository repository,
    required List<TabelaPreco> allTables,
    required String? selectedRepresentedCompanyId,
    required String? activeRepresentedCompanyName,
  }) {
    final workspaceType = activeTenant.workspaceType.trim().toLowerCase();
    final representedId = (selectedRepresentedCompanyId ?? '').trim();
    final representedName = (activeRepresentedCompanyName ?? '').trim();
    final representedContext = workspaceType == 'rep_workspace' || representedName.isNotEmpty;
    final shouldUseRepresentedScope = representedContext && representedId.isNotEmpty;

    final scopeKey = shouldUseRepresentedScope
        ? normalizeDefaultPricingScopeKey(representedId)
        : 'tenant_default';
    if (_autoSyncedDefaultPriceRowCounts.contains(scopeKey) ||
        _autoSyncingDefaultPriceRowCounts.contains(scopeKey)) {
      return;
    }

    TabelaPreco? targetDefault;
    for (final table in allTables) {
      final isSystemDefault =
          table.origem.trim().toLowerCase() == 'system' &&
          table.nome.trim().toLowerCase() == reservedSystemDefaultPriceTableName;
      if (!isSystemDefault) {
        continue;
      }

      final linked = (table.linkedEntityId ?? '').trim();
      if (shouldUseRepresentedScope && linked == representedId) {
        targetDefault = table;
        break;
      }
      if (!shouldUseRepresentedScope && linked.isEmpty) {
        targetDefault = table;
        break;
      }
    }

    if (targetDefault == null) {
      return;
    }

    _autoSyncingDefaultPriceRowCounts.add(scopeKey);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final prices = await FirebaseFirestore.instance
            .collection('product_base_prices')
            .where('tenantId', isEqualTo: identity.tenantId)
            .where('priceTableId', isEqualTo: targetDefault!.id)
            .where('status', isEqualTo: 'active')
            .get();
        final rowCount = prices.docs.length;

        if ((targetDefault?.rowCount ?? 0) != rowCount) {
          await repository.save(
            targetDefault!.copyWith(
              rowCount: rowCount,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
        }

        _autoSyncedDefaultPriceRowCounts.add(scopeKey);
      } catch (_) {
        // Best effort: failing to sync count must not break the page.
      } finally {
        _autoSyncingDefaultPriceRowCounts.remove(scopeKey);
      }
    });
  }

  static List<TabelaPreco> dedupeSystemDefaultTables(
    List<TabelaPreco> tables, {
    required bool collapseRepresentedDefaults,
  }) {
    final deduped = <TabelaPreco>[];
    final seenDefaultScopes = <String>{};

    for (final table in tables) {
      final isSystemDefault =
          table.origem.trim().toLowerCase() == 'system' &&
          table.nome.trim().toLowerCase() == reservedSystemDefaultPriceTableName;
      if (!isSystemDefault) {
        deduped.add(table);
        continue;
      }

      final linked = (table.linkedEntityId ?? '').trim();
      final scopeKey = linked.isEmpty
          ? 'tenant_default'
          : (collapseRepresentedDefaults ? 'represented_active' : 'represented:$linked');
      if (seenDefaultScopes.contains(scopeKey)) {
        continue;
      }
      seenDefaultScopes.add(scopeKey);
      deduped.add(table);
    }

    return deduped;
  }
}