import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/data/firestore/firestore_cliente_repository.dart';
import '../../../../core/data/firestore/firestore_customer_price_table_assignment_repository.dart';
import '../../../../core/data/firestore/firestore_product_base_price_repository.dart';
import '../../../../core/data/firestore/firestore_tax_operation_profile_repository.dart';
import '../../../../core/data/firestore/firestore_tax_rule_repository.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/cliente.dart';
import '../../../../core/models/cliente_reference.dart';
import '../../../../core/models/pedido.dart';
import '../../../../core/repositories/cliente_repository.dart';
import '../../../../core/repositories/customer_price_table_assignment_repository.dart';
import '../../../../core/repositories/pedido_repository.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../../core/services/catalog_incremental_sync_service.dart';
import '../../../../core/services/catalog_snapshot_store.dart';
import '../../../../core/services/offline_sync_queue.dart';
import '../../../../core/models/produto.dart';
import '../../../auth/services/tenant_membership_service.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../../../precos/services/product_tax_engine_service.dart';
import '../models/computed_pedido_item_values.dart';
import '../services/pedido_cliente_lookup_service.dart';
import '../services/pedido_commercial_pricing_service.dart';
import '../services/pedido_discount_controller_manager.dart';
import '../services/pedido_format_utils.dart';
import '../services/pedido_item_pricing_service.dart';
import '../services/pedido_product_search_service.dart';
import '../widgets/pedido_customer_selector_section.dart';
import '../widgets/pedido_editor_desktop_search_header.dart';
import '../widgets/pedido_editor_top_bar.dart';
import '../widgets/pedido_item_row.dart';
import '../widgets/pedido_item_tax_details_dialog.dart';
import '../widgets/pedido_list_widgets.dart';
import '../widgets/pedido_mobile_add_item_sheet.dart';
import '../widgets/pedido_search_results_dialog.dart';
import '../widgets/pedido_search_results_preview_list.dart';

String _pedidoDisplayNumber(String id) {
  return PedidoFormatUtils.pedidoDisplayNumber(id);
}

String _formatMoneyBr(double value) {
  return PedidoFormatUtils.formatMoneyBr(value);
}

class PedidosPage extends StatefulWidget {
  const PedidosPage({
    super.key,
    required this.identity,
    required this.repository,
    required this.produtoRepository,
    this.representedCompanyId,
    this.originCompanyUnitId,
    this.originCompanyUnitLabel,
    this.originCompanyUf,
  });

  final AppIdentity identity;
  final PedidoRepository repository;
  final ProdutoRepository produtoRepository;
  final String? representedCompanyId;
  final String? originCompanyUnitId;
  final String? originCompanyUnitLabel;
  final String? originCompanyUf;

  @override
  State<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends State<PedidosPage> {
  bool _creatingDraft = false;
  bool _loadingProductsForEditor = false;
  bool _savingDraftEdition = false;
  bool _loadingRepresentedContext = false;
  String? _editingOrderId;
  String? _selectedRepresentedCompanyId;
  String? _selectedOriginCompanyUnitId;
  String? _selectedOriginCompanyUnitLabel;
  String? _selectedOriginCompanyUf;
  List<_RepresentedOriginContextOption> _representedOptions =
      const <_RepresentedOriginContextOption>[];
  List<Produto> _editorProducts = const [];
  late final ClienteRepository _clienteRepository;
  late final WorkspaceProfileService _workspaceProfileService;
  late final CustomerPriceTableAssignmentRepository
  _customerPriceTableAssignmentRepository;
  late final ProductTaxEngineService _taxEngineService;
  final CatalogSnapshotStore _catalogSnapshotStore = CatalogSnapshotStore();

  @override
  void initState() {
    super.initState();
    final firestore = FirebaseFirestore.instance;
    _workspaceProfileService = WorkspaceProfileService(firestore);
    _clienteRepository = FirestoreClienteRepository(firestore);
    _customerPriceTableAssignmentRepository =
        FirestoreCustomerPriceTableAssignmentRepository(firestore);
    _taxEngineService = ProductTaxEngineService(
      produtoRepository: widget.produtoRepository,
      basePriceRepository: FirestoreProductBasePriceRepository(firestore),
      taxRuleRepository: FirestoreTaxRuleRepository(firestore),
      taxOperationProfileRepository: FirestoreTaxOperationProfileRepository(
        firestore,
      ),
    );
    _loadRepresentedContextIfNeeded();
  }

  @override
  void didUpdateWidget(covariant PedidosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.tenantId.trim() != widget.identity.tenantId.trim()) {
      _representedOptions = const <_RepresentedOriginContextOption>[];
      _selectedRepresentedCompanyId = null;
      _selectedOriginCompanyUnitId = null;
      _selectedOriginCompanyUnitLabel = null;
      _selectedOriginCompanyUf = null;
      _loadRepresentedContextIfNeeded();
    }
  }

  double _roundCurrency(double value) {
    return PedidoFormatUtils.roundCurrency(value);
  }

  double _totalQuantity(List<PedidoItem> itens) {
    return itens.fold(0, (total, item) => total + item.quantity);
  }

  double _totalGross(List<PedidoItem> itens) {
    return itens.fold(0, (total, item) => total + item.totalPrice);
  }

  Future<void> _saveOrderLocalFirst({
    required Pedido order,
    required String syncedMessage,
    required String pendingActionLabel,
  }) async {
    await OfflineSyncQueue.enqueue(
      type: 'pedido',
      tenantId: order.tenantId,
      payload: order.toMap(),
    );

    var syncedRemotely = false;
    Object? remoteError;
    final isOffline = await _resolveIsOffline();
    if (!isOffline) {
      try {
        await widget.repository.save(order).timeout(const Duration(seconds: 8));
        await OfflineSyncQueue.markSynced(order.id);
        syncedRemotely = true;
      } catch (error) {
        remoteError = error;
      }
    } else {
      remoteError = const _PedidoOfflineSaveMarker();
    }

    if (!mounted) {
      return;
    }

    if (syncedRemotely) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(syncedMessage)));
    } else {
      final firebaseError = remoteError is FirebaseException
          ? remoteError.code
          : null;
      final isTimeout = remoteError is TimeoutException;
      final isOfflineMarker = remoteError is _PedidoOfflineSaveMarker;
      final isOfflineFallback = isOfflineMarker || isTimeout;
      if (isOfflineFallback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Salvo no dispositivo Local (off-line)'),
          ),
        );
      } else {
        final reason = firebaseError == 'permission-denied'
            ? 'Sem permissao no Firestore para este usuario.'
            : 'Sem sincronizar no servidor agora.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(reason)));
      }
    }

    setState(() {
      // Rebuild to refresh local queue merge and sync badges.
    });
  }

  Future<bool> _resolveIsOffline() async {
    try {
      final connectivity = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 3),
      );
      return connectivity.contains(ConnectivityResult.none);
    } catch (_) {
      // If we cannot resolve connectivity quickly, prefer local-first mode.
      return true;
    }
  }

  Future<Map<String, String>> _resolveScopeIdsForCurrentUser(
    String tenantId,
  ) async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      return {
        'ownerId': '',
        'gerenteId': '',
        'representanteId': '',
        'vendedorId': '',
      };
    }

    Map<String, String> fallbackFromRole() {
      final role = widget.identity.role.trim().toLowerCase();
      switch (role) {
        case 'owner':
        case 'platform_admin':
          return {
            'ownerId': uid,
            'gerenteId': '',
            'representanteId': '',
            'vendedorId': '',
          };
        case 'gerente':
          return {
            'ownerId': uid,
            'gerenteId': uid,
            'representanteId': '',
            'vendedorId': '',
          };
        case 'representante':
          return {
            'ownerId': uid,
            'gerenteId': uid,
            'representanteId': uid,
            'vendedorId': '',
          };
        case 'vendedor':
        case 'seller':
        case 'sales':
          return {
            'ownerId': uid,
            'gerenteId': uid,
            'representanteId': uid,
            'vendedorId': uid,
          };
        default:
          return {
            'ownerId': uid,
            'gerenteId': uid,
            'representanteId': uid,
            'vendedorId': uid,
          };
      }
    }

    bool hasUsableMembershipScope(Map<String, String> scope) {
      final role = widget.identity.role.trim().toLowerCase();
      final ownerId = (scope['ownerId'] ?? '').trim();
      final gerenteId = (scope['gerenteId'] ?? '').trim();
      final representanteId = (scope['representanteId'] ?? '').trim();
      final vendedorId = (scope['vendedorId'] ?? '').trim();

      if (ownerId.isEmpty) {
        return false;
      }

      if (role == 'owner' || role == 'platform_admin') {
        return ownerId == uid;
      }

      if (role == 'gerente') {
        return gerenteId.isNotEmpty;
      }

      if (role == 'representante') {
        return gerenteId.isNotEmpty && representanteId.isNotEmpty;
      }

      if (role == 'vendedor' || role == 'seller' || role == 'sales') {
        return gerenteId.isNotEmpty &&
            representanteId.isNotEmpty &&
            vendedorId.isNotEmpty;
      }

      return true;
    }

    try {
      final membership = await TenantMembershipService(
        FirebaseFirestore.instance,
      ).loadActiveByTenantAndUid(tenantId: tenantId, uid: uid);
      if (membership != null && membership.isActive) {
        final scope = {
          'ownerId': membership.ownerId,
          'gerenteId': membership.gerenteId,
          'representanteId': membership.representanteId,
          'vendedorId': membership.vendedorId,
        };

        if (hasUsableMembershipScope(scope)) {
          return scope;
        }
      }
    } catch (_) {
      // Falls back to role-based defaults when membership lookup is unavailable.
    }

    return fallbackFromRole();
  }

  Future<_PedidoLocalState> _readLocalPedidos() async {
    final records = await OfflineSyncQueue.readLocalPedidos(
      tenantId: widget.identity.tenantId,
      includePersonalWorkspace: widget.identity.isPersonalWorkspace,
    );
    final deletedIds = await OfflineSyncQueue.readDeletedIds(type: 'pedido');
    return _PedidoLocalState(records: records, deletedIds: deletedIds);
  }

  List<_PedidoListEntry> _mergePedidos({
    required List<Pedido> remote,
    required List<LocalPedidoRecord> local,
  }) {
    final byId = <String, _PedidoListEntry>{
      for (final pedido in remote)
        pedido.id: _PedidoListEntry(pedido: pedido, syncedRemotely: true),
    };

    for (final record in local) {
      final id = record.entity.id.trim();
      if (id.isEmpty) {
        continue;
      }

      final current = byId[id];
      if (current == null) {
        byId[id] = _PedidoListEntry(
          pedido: record.entity,
          syncedRemotely: record.synced,
        );
        continue;
      }

      final localDate =
          record.entity.updatedAt ?? record.entity.createdAt ?? DateTime(1970);
      final currentDate =
          current.pedido.updatedAt ??
          current.pedido.createdAt ??
          DateTime(1970);

      if (!record.synced || localDate.isAfter(currentDate)) {
        byId[id] = _PedidoListEntry(
          pedido: record.entity,
          syncedRemotely: record.synced,
        );
      }
    }

    final merged = byId.values.toList();
    merged.sort((a, b) {
      final aDate = a.pedido.updatedAt ?? a.pedido.createdAt ?? DateTime(1970);
      final bDate = b.pedido.updatedAt ?? b.pedido.createdAt ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });
    return merged;
  }

  bool get _usesExternalRepresentedContext {
    final widgetRepresentedId = (widget.representedCompanyId ?? '').trim();
    final widgetOriginUnitId = (widget.originCompanyUnitId ?? '').trim();
    final widgetOriginLabel = (widget.originCompanyUnitLabel ?? '').trim();
    final widgetOriginUf = (widget.originCompanyUf ?? '').trim();
    return widgetRepresentedId.isNotEmpty ||
        widgetOriginUnitId.isNotEmpty ||
        widgetOriginLabel.isNotEmpty ||
        widgetOriginUf.isNotEmpty;
  }

  String? get _effectiveRepresentedCompanyId {
    final fromWidget = (widget.representedCompanyId ?? '').trim();
    if (fromWidget.isNotEmpty) {
      return fromWidget;
    }
    final fromState = (_selectedRepresentedCompanyId ?? '').trim();
    return fromState.isEmpty ? null : fromState;
  }

  String? get _effectiveOriginCompanyUnitId {
    final fromWidget = (widget.originCompanyUnitId ?? '').trim();
    if (fromWidget.isNotEmpty) {
      return fromWidget;
    }
    final fromState = (_selectedOriginCompanyUnitId ?? '').trim();
    return fromState.isEmpty ? null : fromState;
  }

  String? get _effectiveOriginCompanyUnitLabel {
    final fromWidget = (widget.originCompanyUnitLabel ?? '').trim();
    if (fromWidget.isNotEmpty) {
      return fromWidget;
    }
    final fromState = (_selectedOriginCompanyUnitLabel ?? '').trim();
    return fromState.isEmpty ? null : fromState;
  }

  String? get _effectiveOriginCompanyUf {
    final fromWidget = (widget.originCompanyUf ?? '').trim().toUpperCase();
    if (fromWidget.isNotEmpty) {
      return fromWidget;
    }
    final fromState = (_selectedOriginCompanyUf ?? '').trim().toUpperCase();
    return fromState.isEmpty ? null : fromState;
  }

  Future<void> _loadRepresentedContextIfNeeded() async {
    if (_usesExternalRepresentedContext || _loadingRepresentedContext) {
      return;
    }

    final tenantId = widget.identity.tenantId.trim();
    if (tenantId.isEmpty) {
      return;
    }

    setState(() {
      _loadingRepresentedContext = true;
    });

    try {
      final workspace = await _workspaceProfileService
          .watchWorkspace(tenantId)
          .first;
      final favoriteRepresentedId =
          (workspace?['favoriteRepresentedCompanyId'] ?? '').toString().trim();

      final companies = await _workspaceProfileService
          .watchRepresentedCompanies(tenantId)
          .first;

      final options = <_RepresentedOriginContextOption>[];
      for (final raw in companies) {
        final representedId = (raw['companyId'] ?? '').toString().trim();
        if (representedId.isEmpty) {
          continue;
        }

        final isActive = raw['ativo'] != false;
        if (!isActive) {
          continue;
        }

        final companyName = (raw['nomeFantasia'] ?? '').toString().trim();
        final originLabel = companyName.isEmpty ? representedId : companyName;
        final originUf = (raw['uf'] ?? '').toString().trim().toUpperCase();
        options.add(
          _RepresentedOriginContextOption(
            representedCompanyId: representedId,
            originCompanyUnitId: representedId,
            originCompanyUnitLabel: originLabel,
            originCompanyUf: originUf,
          ),
        );
      }

      options.sort(
        (a, b) => a.originCompanyUnitLabel.toLowerCase().compareTo(
          b.originCompanyUnitLabel.toLowerCase(),
        ),
      );

      _RepresentedOriginContextOption? selected;
      if (favoriteRepresentedId.isNotEmpty) {
        for (final option in options) {
          if (option.representedCompanyId == favoriteRepresentedId) {
            selected = option;
            break;
          }
        }
      }
      selected ??= options.isEmpty ? null : options.first;

      if (!mounted) {
        return;
      }

      setState(() {
        _representedOptions =
            List<_RepresentedOriginContextOption>.unmodifiable(options);
        _selectedRepresentedCompanyId = selected?.representedCompanyId;
        _selectedOriginCompanyUnitId = selected?.originCompanyUnitId;
        _selectedOriginCompanyUnitLabel = selected?.originCompanyUnitLabel;
        _selectedOriginCompanyUf = selected?.originCompanyUf;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _representedOptions = const <_RepresentedOriginContextOption>[];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingRepresentedContext = false;
        });
      }
    }
  }

  void _onRepresentedSelectionChanged(String? representedCompanyId) {
    final selectedId = (representedCompanyId ?? '').trim();
    if (selectedId.isEmpty) {
      return;
    }

    for (final option in _representedOptions) {
      if (option.representedCompanyId == selectedId) {
        setState(() {
          _selectedRepresentedCompanyId = option.representedCompanyId;
          _selectedOriginCompanyUnitId = option.originCompanyUnitId;
          _selectedOriginCompanyUnitLabel = option.originCompanyUnitLabel;
          _selectedOriginCompanyUf = option.originCompanyUf;
        });
        return;
      }
    }
  }

  Widget _buildRepresentedSelectorCard() {
    if (_usesExternalRepresentedContext) {
      return const SizedBox.shrink();
    }

    final isCompact = MediaQuery.sizeOf(context).shortestSide < 700;
    final panelPadding = isCompact ? 8.0 : 12.0;
    final panelSpacing = isCompact ? 6.0 : 8.0;
    final progressSize = isCompact ? 16.0 : 18.0;

    if (_loadingRepresentedContext) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(panelPadding),
          child: Row(
            children: [
              SizedBox(
                width: progressSize,
                height: progressSize,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: panelSpacing),
              const Expanded(
                child: Text(
                  'Carregando representadas para definir origem do pedido...',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_representedOptions.isEmpty) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(panelPadding),
          child: const Text(
            'Nenhuma representada ativa encontrada. Cadastre/ative uma representada para habilitar a criação de pedidos.',
          ),
        ),
      );
    }

    final selectedId = _effectiveRepresentedCompanyId;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(panelPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Representada ativa do pedido',
              style: isCompact
                  ? Theme.of(context).textTheme.titleSmall
                  : Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: panelSpacing),
            DropdownButtonFormField<String>(
              initialValue: selectedId,
              decoration: const InputDecoration(
                labelText: 'Representada',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _representedOptions
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option.representedCompanyId,
                      child: Text(option.displayLabel),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _onRepresentedSelectionChanged,
            ),
          ],
        ),
      ),
    );
  }

  bool _isProductInRepresentedScope(Produto product) {
    final selectedRepresentedCompanyId = (_effectiveRepresentedCompanyId ?? '')
        .trim();
    if (selectedRepresentedCompanyId.isEmpty) {
      return true;
    }

    final productScope = (product.representedCompanyId ?? '').trim();
    if (productScope.isEmpty) {
      return true;
    }
    return productScope == selectedRepresentedCompanyId;
  }

  Future<void> _selectOrderForEditing(Pedido pedido) async {
    final tenantId = widget.identity.tenantId.trim();
    if (tenantId.isEmpty) {
      return;
    }

    setState(() {
      _editingOrderId = pedido.id;
      _loadingProductsForEditor = true;
    });

    try {
      final activeProducts = await _resolveProductsForEditor(tenantId);

      if (!mounted) {
        return;
      }

      setState(() {
        _editorProducts = activeProducts;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao carregar produtos: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingProductsForEditor = false;
        });
      }
    }
  }

  Future<List<Produto>> _resolveProductsForEditor(String tenantId) async {
    if (_editorProducts.isNotEmpty) {
      return _editorProducts;
    }

    final cachedPayloads = await _catalogSnapshotStore.readAll(
      tenantId: tenantId,
      module: CatalogSyncModule.produtos,
    );
    if (cachedPayloads.isNotEmpty) {
      final cachedProducts = <Produto>[];
      for (final payload in cachedPayloads) {
        try {
          cachedProducts.add(Produto.fromMap(payload));
        } catch (_) {
          // Skip invalid cached payloads and fall back to repository when empty.
        }
      }

      final activeCached =
          cachedProducts
              .where(
                (item) =>
                    item.status == ProductStatus.active &&
                    item.deletedAt == null &&
                    _isProductInRepresentedScope(item),
              )
              .toList()
            ..sort(
              (a, b) => a.descricao.toLowerCase().compareTo(
                b.descricao.toLowerCase(),
              ),
            );
      if (activeCached.isNotEmpty) {
        return activeCached;
      }
    }

    final products = await widget.produtoRepository.fetchAll(
      tenantId: tenantId,
    );
    final activeProducts =
        products
            .where(
              (item) =>
                  item.status == ProductStatus.active &&
                  item.deletedAt == null &&
                  _isProductInRepresentedScope(item),
            )
            .toList()
          ..sort(
            (a, b) =>
                a.descricao.toLowerCase().compareTo(b.descricao.toLowerCase()),
          );
    return activeProducts;
  }

  void _closeInlineEditor() {
    setState(() {
      _editingOrderId = null;
    });
  }

  _PedidoListEntry? _findEditingEntry(List<_PedidoListEntry> pedidos) {
    final targetId = (_editingOrderId ?? '').trim();
    if (targetId.isEmpty) {
      return null;
    }

    for (final entry in pedidos) {
      if (entry.pedido.id == targetId) {
        return entry;
      }
    }

    return null;
  }

  Future<void> _saveEditedItems(
    Pedido pedido,
    List<PedidoItem> editedItems,
    ClienteReference? editedClienteReferencia,
    SalePurpose editedSalePurpose,
    String? editedFormaPagamento,
  ) async {
    setState(() {
      _savingDraftEdition = true;
    });

    try {
      final now = DateTime.now().toUtc();
      final updatedOrder = pedido.copyWith(
        clienteReferencia: editedClienteReferencia,
        clearClienteReferencia: editedClienteReferencia == null,
        salePurpose: editedSalePurpose,
        formaPagamento: (editedFormaPagamento ?? '').trim().isEmpty
            ? null
            : editedFormaPagamento?.trim(),
        itens: editedItems,
        totalItens: _roundCurrency(_totalQuantity(editedItems)),
        totalBruto: _roundCurrency(_totalGross(editedItems)),
        updatedAt: now,
      );

      await _saveOrderLocalFirst(
        order: updatedOrder,
        syncedMessage:
            'Pedido ${_pedidoDisplayNumber(pedido.id)} atualizado com ${editedItems.length} item(ns).',
        pendingActionLabel: 'atualizado',
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingDraftEdition = false;
        });
      }
    }
  }

  Future<void> _createDraftOrder() async {
    if (_creatingDraft) {
      return;
    }

    final normalizedTenant = widget.identity.tenantId.trim();
    if (normalizedTenant.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tenant inválido para criar pedido.')),
      );
      return;
    }

    final representedCompanyId = _effectiveRepresentedCompanyId;
    final originCompanyUnitId = _effectiveOriginCompanyUnitId;
    final originLabel = (_effectiveOriginCompanyUnitLabel ?? '').trim();
    final originUf = (_effectiveOriginCompanyUf ?? '').trim().toUpperCase();
    if (originLabel.isEmpty || originUf.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecione a representada ativa para definir a origem (empresa e UF).',
          ),
        ),
      );
      return;
    }

    setState(() {
      _creatingDraft = true;
    });

    try {
      final now = DateTime.now().toUtc();
      final scopeIds = await _resolveScopeIdsForCurrentUser(normalizedTenant);

      final order = Pedido(
        id: 'ord_${now.microsecondsSinceEpoch}',
        tenantId: normalizedTenant,
        origemPedido: OrderOrigin.manual,
        statusFila: OrderStatus.draft,
        ownerId: scopeIds['ownerId'] ?? '',
        gerenteId: scopeIds['gerenteId'] ?? '',
        representanteId: scopeIds['representanteId'] ?? '',
        vendedorId: scopeIds['vendedorId'] ?? '',
        representedCompanyId: representedCompanyId,
        originCompanyUnitId: originCompanyUnitId,
        originCompanyUnitLabel: originLabel,
        originCompanyUf: originUf,
        salePurpose: SalePurpose.revenda,
        formaPagamento: null,
        itens: const [],
        totalItens: 0,
        totalBruto: 0,
        createdAt: now,
        updatedAt: now,
      );

      await _saveOrderLocalFirst(
        order: order,
        syncedMessage:
            'Pedido ${_pedidoDisplayNumber(order.id)} criado em rascunho com origem $originLabel ($originUf).',
        pendingActionLabel: 'salvo',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao criar pedido: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _creatingDraft = false;
        });
      }
    }
  }

  Future<void> _deleteOrderLocalFirst(Pedido order) async {
    if (!mounted) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Excluir pedido'),
            content: Text(
              'Deseja excluir o pedido ${_pedidoDisplayNumber(order.id)}? Esta ação remove o pedido localmente imediatamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    await OfflineSyncQueue.markDeleted(
      type: 'pedido',
      tenantId: order.tenantId,
      id: order.id,
    );

    if ((_editingOrderId ?? '').trim() == order.id) {
      _closeInlineEditor();
    }

    var deletedRemotely = false;
    Object? remoteError;
    try {
      await widget.repository.delete(tenantId: order.tenantId, id: order.id);
      await OfflineSyncQueue.clearTombstone(order.id);
      deletedRemotely = true;
    } catch (error) {
      remoteError = error;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      // Refreshes merged local/remote list after local-first delete.
    });

    if (deletedRemotely) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido ${_pedidoDisplayNumber(order.id)} excluído e sincronizado.',
          ),
        ),
      );
      return;
    }

    final firebaseError = remoteError is FirebaseException
        ? remoteError.code
        : null;
    final reason = firebaseError == 'permission-denied'
        ? 'sem permissao para excluir no Firestore agora'
        : 'aguardando sincronizacao com o servidor';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pedido ${_pedidoDisplayNumber(order.id)} excluído localmente ($reason). O app tentará confirmar a exclusão remota quando possível.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Pedido>>(
      stream: widget.repository.watchAll(tenantId: widget.identity.tenantId),
      initialData: const [],
      builder: (context, snapshot) {
        final remotePedidos = snapshot.data ?? const [];

        return FutureBuilder<_PedidoLocalState>(
          future: _readLocalPedidos(),
          initialData: _PedidoLocalState.empty,
          builder: (context, localSnapshot) {
            final localState = localSnapshot.data ?? _PedidoLocalState.empty;
            final localPedidos = localState.records;
            final filteredRemote = remotePedidos
                .where((pedido) => !localState.deletedIds.contains(pedido.id))
                .toList();
            final pedidos = _mergePedidos(
              remote: filteredRemote,
              local: localPedidos,
            );
            final editingEntry = _findEditingEntry(pedidos);

            return LayoutBuilder(
              builder: (context, constraints) {
                final editorBodyMaxHeight = (constraints.maxHeight - 220).clamp(
                  260.0,
                  1000.0,
                );
                final isEditing = (_editingOrderId ?? '').trim().isNotEmpty;
                final representedNameForNewOrder =
                    (_effectiveOriginCompanyUnitLabel ?? '').trim();
                final newOrderActionLabel = representedNameForNewOrder.isEmpty
                    ? 'Novo pedido'
                    : 'Novo pedido para $representedNameForNewOrder';

                if (isEditing) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
                    child: _PedidoInlineEditor(
                      pedido: editingEntry?.pedido,
                      products: _editorProducts,
                      tenantId: widget.identity.tenantId,
                      representedCompanyId: _effectiveRepresentedCompanyId,
                      originCompanyUf: _effectiveOriginCompanyUf,
                      clienteRepository: _clienteRepository,
                      customerPriceTableAssignmentRepository:
                          _customerPriceTableAssignmentRepository,
                      taxEngineService: _taxEngineService,
                      loadingProducts: _loadingProductsForEditor,
                      saving: _savingDraftEdition,
                      maxBodyHeight: editorBodyMaxHeight,
                      onClose: _closeInlineEditor,
                      onSave: _saveEditedItems,
                    ),
                  );
                }

                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 16, 10, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PedidoHeaderCard(
                          title: 'Pedidos',
                          subtitle: 'Lista de Pedidos.',
                          actionLabel: _creatingDraft
                              ? 'Criando...'
                              : newOrderActionLabel,
                          onAction: _createDraftOrder,
                          actionEnabled: !_creatingDraft,
                        ),
                        if (!_usesExternalRepresentedContext) ...[
                          const SizedBox(height: 12),
                          _buildRepresentedSelectorCard(),
                        ],
                        const SizedBox(height: 16),
                        if (pedidos.isEmpty)
                          const PedidoEmptyState(
                            title: 'Nenhum pedido carregado',
                            subtitle: 'Os pedidos locais aparecerão aqui assim que a fila for preenchida.',
                          )
                        else
                          ...pedidos.map(
                            (entry) => PedidoCard(
                              entry.pedido,
                              syncedRemotely: entry.syncedRemotely,
                              selected: false,
                              onTap: () => _selectOrderForEditing(entry.pedido),
                              onDelete: () =>
                                  _deleteOrderLocalFirst(entry.pedido),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PedidoListEntry {
  const _PedidoListEntry({required this.pedido, required this.syncedRemotely});

  final Pedido pedido;
  final bool syncedRemotely;
}

class _PedidoLocalState {
  const _PedidoLocalState({required this.records, required this.deletedIds});

  static const _PedidoLocalState empty = _PedidoLocalState(
    records: <LocalPedidoRecord>[],
    deletedIds: <String>{},
  );

  final List<LocalPedidoRecord> records;
  final Set<String> deletedIds;
}

class _RepresentedOriginContextOption {
  const _RepresentedOriginContextOption({
    required this.representedCompanyId,
    required this.originCompanyUnitId,
    required this.originCompanyUnitLabel,
    required this.originCompanyUf,
  });

  final String representedCompanyId;
  final String originCompanyUnitId;
  final String originCompanyUnitLabel;
  final String originCompanyUf;

  String get displayLabel {
    final uf = originCompanyUf.trim().toUpperCase();
    if (uf.isEmpty) {
      return originCompanyUnitLabel;
    }
    return '$originCompanyUnitLabel ($uf)';
  }
}

class _PedidoInlineEditor extends StatefulWidget {
  const _PedidoInlineEditor({
    required this.pedido,
    required this.products,
    required this.tenantId,
    required this.representedCompanyId,
    required this.originCompanyUf,
    required this.clienteRepository,
    required this.customerPriceTableAssignmentRepository,
    required this.taxEngineService,
    required this.loadingProducts,
    required this.saving,
    required this.maxBodyHeight,
    required this.onClose,
    required this.onSave,
  });

  final Pedido? pedido;
  final List<Produto> products;
  final String tenantId;
  final String? representedCompanyId;
  final String? originCompanyUf;
  final ClienteRepository clienteRepository;
  final CustomerPriceTableAssignmentRepository
  customerPriceTableAssignmentRepository;
  final ProductTaxEngineService taxEngineService;
  final bool loadingProducts;
  final bool saving;
  final double maxBodyHeight;
  final VoidCallback onClose;
  final Future<void> Function(
    Pedido pedido,
    List<PedidoItem> items,
    ClienteReference? clienteReferencia,
    SalePurpose salePurpose,
    String? formaPagamento,
  )
  onSave;

  @override
  State<_PedidoInlineEditor> createState() => _PedidoInlineEditorState();
}

class _PedidoInlineEditorState extends State<_PedidoInlineEditor> {
  static const Color _chromeColor = Color(0xFFF5F6F8);
  static const Color _bodyColor = Colors.white;
  static const Color _borderColor = Color(0xFFE3E6EA);
  static const Color _focusedBorderColor = Color(0xFFD0D6DE);

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _customerController = TextEditingController();
  final FocusNode _customerFocusNode = FocusNode();
  final PedidoDiscountControllerManager _discountControllerManager =
      PedidoDiscountControllerManager();
  bool _addingProductInFlight = false;
  List<PedidoItem> _items = const [];
  List<Cliente> _clientes = const [];
  List<PaymentConditionRule> _paymentConditionRules =
      const <PaymentConditionRule>[];
  bool _paymentConditionRulesLoaded = false;
  Future<void>? _paymentConditionRulesLoader;
  String? _selectedPaymentConditionDescription;
  bool _loadingClientes = false;
  bool _customerReadDenied = false;
  bool _commercialRulesLoaded = false;
  Future<void>? _commercialRulesLoader;
  List<CommercialAdjustmentRule> _commercialRules =
      const <CommercialAdjustmentRule>[];
  bool _orderDiscountPolicyLoaded = false;
  Future<void>? _orderDiscountPolicyLoader;
  OrderDiscountPolicy _orderDiscountPolicy = const OrderDiscountPolicy();
  SalePurpose _selectedSalePurpose = SalePurpose.revenda;
  ClienteReference? _clienteReferenciaSelecionada;
  String? _customerInputError;
  String? _boundOrderId;
  String _searchQuery = '';
  final WorkspaceProfileService _workspaceProfileService =
      WorkspaceProfileService(FirebaseFirestore.instance);
  final CatalogSnapshotStore _catalogSnapshotStore = CatalogSnapshotStore();
  late final PedidoClienteLookupService _clienteLookupService =
      PedidoClienteLookupService(
        clienteRepository: widget.clienteRepository,
        catalogSnapshotStore: _catalogSnapshotStore,
      );
  late final PedidoItemPricingService _itemPricingService =
      PedidoItemPricingService(
        clienteRepository: widget.clienteRepository,
        customerPriceTableAssignmentRepository:
            widget.customerPriceTableAssignmentRepository,
        taxEngineService: widget.taxEngineService,
      );

  String? _effectiveRepresentedCompanyIdForWidget(_PedidoInlineEditor source) {
    final fromOrder = (source.pedido?.representedCompanyId ?? '').trim();
    if (fromOrder.isNotEmpty) {
      return fromOrder;
    }

    final fromSelection = (source.representedCompanyId ?? '').trim();
    if (fromSelection.isNotEmpty) {
      return fromSelection;
    }

    return null;
  }

  String? get _effectiveRepresentedCompanyId =>
      _effectiveRepresentedCompanyIdForWidget(widget);

  void _resetScopedPoliciesState() {
    _commercialRulesLoaded = false;
    _commercialRulesLoader = null;
    _commercialRules = const <CommercialAdjustmentRule>[];
    _orderDiscountPolicyLoaded = false;
    _orderDiscountPolicyLoader = null;
    _orderDiscountPolicy = const OrderDiscountPolicy();
    _paymentConditionRulesLoaded = false;
    _paymentConditionRulesLoader = null;
    _paymentConditionRules = const <PaymentConditionRule>[];
  }

  @override
  void initState() {
    super.initState();
    _syncFromPedidoIfNeeded();
    _loadClientes();
    _loadCommercialRules();
    _loadOrderDiscountPolicy();
    _loadPaymentConditionRules();
  }

  @override
  void didUpdateWidget(covariant _PedidoInlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldScope = _effectiveRepresentedCompanyIdForWidget(oldWidget);
    final newScope = _effectiveRepresentedCompanyId;

    if (oldWidget.tenantId != widget.tenantId) {
      _itemPricingService.invalidateAssignmentsCache();
      _loadClientes();
      _resetScopedPoliciesState();
      _loadCommercialRules();
      _loadOrderDiscountPolicy();
      _loadPaymentConditionRules();
    }
    if (oldScope != newScope) {
      _resetScopedPoliciesState();
      _loadCommercialRules();
      _loadOrderDiscountPolicy();
      _loadPaymentConditionRules();
    }
    _syncFromPedidoIfNeeded();
  }

  Future<void> _loadCommercialRules() async {
    final tenantId = widget.tenantId.trim();
    if (tenantId.isEmpty) {
      _commercialRules = const <CommercialAdjustmentRule>[];
      _commercialRulesLoaded = true;
      return;
    }

    try {
      final rules = await _workspaceProfileService
          .watchCommercialAdjustmentRules(
            tenantId: tenantId,
            representedCompanyId: _effectiveRepresentedCompanyId,
          )
          .first;
      _commercialRules = rules;
      _commercialRulesLoaded = true;
    } catch (_) {
      _commercialRules = const <CommercialAdjustmentRule>[];
      _commercialRulesLoaded = true;
    }
  }

  Future<void> _ensureCommercialRulesLoaded() async {
    if (_commercialRulesLoaded) {
      return;
    }

    final inFlight = _commercialRulesLoader;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _loadCommercialRules();
    _commercialRulesLoader = future;
    await future;
    if (identical(_commercialRulesLoader, future)) {
      _commercialRulesLoader = null;
    }
  }

  Future<void> _loadOrderDiscountPolicy() async {
    final tenantId = widget.tenantId.trim();
    if (tenantId.isEmpty) {
      _orderDiscountPolicy = const OrderDiscountPolicy();
      _orderDiscountPolicyLoaded = true;
      return;
    }

    try {
      final policy = await _workspaceProfileService
          .watchOrderDiscountPolicy(
            tenantId: tenantId,
            representedCompanyId: _effectiveRepresentedCompanyId,
          )
          .first;
      _orderDiscountPolicy = policy;
      _orderDiscountPolicyLoaded = true;
    } catch (_) {
      _orderDiscountPolicy = const OrderDiscountPolicy();
      _orderDiscountPolicyLoaded = true;
    }
  }

  Future<void> _loadPaymentConditionRules() async {
    final tenantId = widget.tenantId.trim();
    if (tenantId.isEmpty) {
      _paymentConditionRules = const <PaymentConditionRule>[];
      _paymentConditionRulesLoaded = true;
      return;
    }

    try {
      final rules = await _workspaceProfileService
          .watchPaymentConditionRules(
            tenantId: tenantId,
            representedCompanyId: _effectiveRepresentedCompanyId,
          )
          .first;
      _paymentConditionRules = rules;
      _paymentConditionRulesLoaded = true;
    } catch (_) {
      _paymentConditionRules = const <PaymentConditionRule>[];
      _paymentConditionRulesLoaded = true;
    }
  }

  Future<void> _ensurePaymentConditionRulesLoaded() async {
    if (_paymentConditionRulesLoaded) {
      return;
    }

    final inFlight = _paymentConditionRulesLoader;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _loadPaymentConditionRules();
    _paymentConditionRulesLoader = future;
    await future;
    if (identical(_paymentConditionRulesLoader, future)) {
      _paymentConditionRulesLoader = null;
    }
  }

  List<PaymentConditionRule> _eligiblePaymentConditionRules() {
    final total = _totalGross();
    return _workspaceProfileService.filterPaymentConditionsByOrderValue(
      rules: _paymentConditionRules,
      orderTotal: total,
    );
  }

  void _sanitizeSelectedPaymentConditionIfNeeded({
    bool forceClearWhenUnavailable = false,
  }) {
    final current = (_selectedPaymentConditionDescription ?? '').trim();
    if (current.isEmpty) {
      return;
    }

    final eligibleDescriptions = _eligiblePaymentConditionRules()
        .map((rule) => rule.description.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    if (!eligibleDescriptions.contains(current) || forceClearWhenUnavailable) {
      _selectedPaymentConditionDescription = null;
    }
  }

  Future<void> _ensureOrderDiscountPolicyLoaded() async {
    if (_orderDiscountPolicyLoaded) {
      return;
    }

    final inFlight = _orderDiscountPolicyLoader;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _loadOrderDiscountPolicy();
    _orderDiscountPolicyLoader = future;
    await future;
    if (identical(_orderDiscountPolicyLoader, future)) {
      _orderDiscountPolicyLoader = null;
    }
  }

  Future<void> _loadClientes() async {
    final tenantId = widget.tenantId.trim();
    if (tenantId.isEmpty) {
      if (mounted) {
        setState(() {
          _clientes = const [];
          _loadingClientes = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loadingClientes = true;
      });
    }

    try {
      final approved = await _clienteLookupService.resolveApprovedClientes(
        tenantId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _clientes = approved;
        _customerController.text = _selectedCustomerDisplayLabel();
        _customerReadDenied = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      if (error is FirebaseException && error.code == 'permission-denied') {
        final localRecords = await OfflineSyncQueue.readLocalClientes(
          tenantId: tenantId,
          includePersonalWorkspace: tenantId.startsWith('personal_'),
        );
        final localApproved =
            localRecords
                .map((record) => record.entity)
                .where((item) => item.status == CustomerStatus.approved)
                .toList()
              ..sort(
                (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
              );

        setState(() {
          _clientes = localApproved;
          _customerReadDenied = localApproved.isEmpty;
          _customerController.text = _selectedCustomerDisplayLabel();
        });
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao carregar clientes: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingClientes = false;
        });
      }
    }
  }

  void _syncFromPedidoIfNeeded() {
    final currentId = widget.pedido?.id;
    if (currentId == null || currentId.isEmpty) {
      if (_boundOrderId != null) {
        _discountControllerManager.disposeAll();
        _boundOrderId = null;
        _items = const [];
        _clienteReferenciaSelecionada = null;
        _customerController.clear();
        _searchController.clear();
        _searchQuery = '';
        _quantityController.text = '1';
      }
      return;
    }

    if (_boundOrderId == currentId) {
      _sanitizeSelectedPaymentConditionIfNeeded();
      return;
    }

    _discountControllerManager.disposeAll();
    _boundOrderId = currentId;
    _items = List<PedidoItem>.from(widget.pedido?.itens ?? const []);
    _clienteReferenciaSelecionada = widget.pedido?.clienteReferencia;
    _selectedSalePurpose = widget.pedido?.salePurpose ?? SalePurpose.revenda;
    _selectedPaymentConditionDescription =
        (widget.pedido?.formaPagamento ?? '').trim().isEmpty
        ? null
        : widget.pedido?.formaPagamento;
    _customerController.text = _selectedCustomerDisplayLabel();
    _customerInputError = null;
    _searchController.clear();
    _searchQuery = '';
    _quantityController.text = '1';
    _sanitizeSelectedPaymentConditionIfNeeded();
  }

  Cliente? _findClienteById(String customerId) {
    final normalizedId = customerId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }
    for (final cliente in _clientes) {
      if (cliente.id == normalizedId) {
        return cliente;
      }
    }
    return null;
  }

  String _selectedCustomerDisplayLabel() {
    final selected = _findClienteById(_clienteReferenciaSelecionada?.id ?? '');
    if (selected != null) {
      return _formatClienteLabel(selected);
    }

    final snapshotName = (_clienteReferenciaSelecionada?.nomeSnapshot ?? '')
        .trim();
    if (snapshotName.isNotEmpty) {
      return snapshotName;
    }
    return '';
  }

  Cliente? _findClienteByTypedText(String raw) {
    final normalizedInput = _normalizeSearch(raw);
    if (normalizedInput.isEmpty) {
      return null;
    }

    for (final cliente in _clientes) {
      final normalizedLabel = _normalizeSearch(_formatClienteLabel(cliente));
      final normalizedNome = _normalizeSearch(cliente.nome);
      final normalizedDocumento = _normalizeSearch(cliente.documento);
      if (normalizedInput == normalizedLabel ||
          normalizedInput == normalizedNome ||
          (normalizedDocumento.isNotEmpty &&
              normalizedInput == normalizedDocumento)) {
        return cliente;
      }
    }

    return null;
  }

  Future<bool> _validateCustomerSelectionForSave() async {
    final typed = _customerController.text.trim();
    if (typed.isEmpty) {
      if (_clienteReferenciaSelecionada != null) {
        await _selectCustomerById('');
      }
      _customerInputError = null;
      return true;
    }

    final selected = _findClienteById(_clienteReferenciaSelecionada?.id ?? '');
    if (selected != null) {
      final selectedLabel = _normalizeSearch(_formatClienteLabel(selected));
      final typedLabel = _normalizeSearch(typed);
      if (typedLabel == selectedLabel) {
        _customerInputError = null;
        return true;
      }
    }

    final matched = _findClienteByTypedText(typed);
    if (matched != null) {
      await _selectCustomerById(matched.id);
      _customerInputError = null;
      return true;
    }

    _customerInputError = 'Selecione um cliente existente da lista.';
    return false;
  }

  ClienteReference _toClienteReference(Cliente cliente) {
    return ClienteReference(
      id: cliente.id,
      type: CustomerReferenceType.official,
      documentoSnapshot: cliente.documento,
      nomeSnapshot: cliente.nome,
    );
  }

  String _formatClienteLabel(Cliente cliente) {
    final nome = cliente.nome.trim().isEmpty ? cliente.id : cliente.nome.trim();
    final documento = cliente.documento.trim();
    final estado = cliente.estado.trim().toUpperCase();
    final suffix = [
      if (documento.isNotEmpty) documento,
      if (estado.isNotEmpty) estado,
    ].join(' · ');
    if (suffix.isEmpty) {
      return nome;
    }
    return '$nome · $suffix';
  }

  Future<void> _selectCustomerById(String customerId) async {
    final normalizedId = customerId.trim();
    if (normalizedId.isEmpty) {
      if (mounted) {
        setState(() {
          _clienteReferenciaSelecionada = null;
          _customerController.clear();
          _customerInputError = null;
        });
      }
      await _recalculateAllItemsForCustomerContext();
      return;
    }

    Cliente? selected;
    for (final cliente in _clientes) {
      if (cliente.id == normalizedId) {
        selected = cliente;
        break;
      }
    }

    if (selected == null) {
      return;
    }

    if (mounted) {
      setState(() {
        _clienteReferenciaSelecionada = _toClienteReference(selected!);
        _customerController.text = _formatClienteLabel(selected);
        _selectedSalePurpose = selected.salePurpose;
        _customerInputError = null;
      });
    }

    await _recalculateAllItemsForCustomerContext();
  }

  @override
  void dispose() {
    _discountControllerManager.disposeAll();
    _customerFocusNode.dispose();
    _customerController.dispose();
    try {
      _searchFocusNode.dispose();
    } catch (_) {
      // Ignore hot-reload web edge where newly-added fields may be undefined.
    }
    try {
      _searchController.dispose();
    } catch (_) {
      // Ignore hot-reload web edge where newly-added fields may be undefined.
    }
    _quantityController.dispose();
    super.dispose();
  }

  void _disposeDiscountControllersForItem(String itemId) {
    _discountControllerManager.disposeForItem(itemId);
  }

  List<TextEditingController> _ensureDiscountControllersForItem(
    PedidoItem item,
    int slotCount,
  ) {
    return _discountControllerManager.ensureControllersForItem(item, slotCount);
  }

  InputDecoration _inputDecoration({required String label}) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: _bodyColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _borderColor, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _borderColor, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _focusedBorderColor, width: 1),
      ),
    );
  }

  String _normalizeSearch(String value) {
    return PedidoFormatUtils.normalizeSearch(value);
  }

  List<Produto> _buildProductResultsForQuery(String query) {
    return PedidoProductSearchService.buildProductResultsForQuery(
      widget.products,
      query,
    );
  }

  List<Produto> _buildProductResults() {
    return _buildProductResultsForQuery(_searchQuery);
  }

  void _showQuantityValidation() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Informe uma quantidade inteira maior que zero para adicionar.',
        ),
      ),
    );
  }

  double _roundCurrency(double value) {
    return PedidoFormatUtils.roundCurrency(value);
  }

  String _formatMoney(double value) {
    return PedidoFormatUtils.formatMoney(value);
  }

  String _formatQuantity(double value) {
    return PedidoFormatUtils.formatQuantity(value);
  }

  int _readIntegerQuantity(String raw) {
    return PedidoFormatUtils.readIntegerQuantity(raw);
  }

  String _formatPercent(double value) {
    return PedidoFormatUtils.formatPercent(value);
  }

  void _showItemTaxDetailsDialog(PedidoItem item) {
    showPedidoItemTaxDetailsDialog(context, item);
  }

  double? _parsePercentInput(String raw) {
    var normalized = raw.trim();
    if (normalized.isEmpty) {
      return null;
    }

    normalized = normalized.replaceAll(' ', '');
    if (normalized.contains(',') && normalized.contains('.')) {
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else if (normalized.contains(',')) {
      normalized = normalized.replaceAll(',', '.');
    }

    return double.tryParse(normalized);
  }

  String _formatPointDiscountSummary(List<double> discounts) {
    final effective = discounts.where((value) => value > 0).toList();
    if (effective.isEmpty) {
      return 'Sem descontos';
    }
    final values = effective.map(_formatPercent).join(' + ');
    return 'Descontos: $values';
  }

  Future<void> _addPointDiscountField(int index) async {
    if (index < 0 || index >= _items.length || widget.saving) {
      return;
    }

    await _ensureOrderDiscountPolicyLoaded();
    if (!mounted) {
      return;
    }
    final fields = _orderDiscountPolicy.fields;
    if (fields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum campo de desconto foi configurado para esta representada.',
          ),
        ),
      );
      return;
    }

    final item = _items[index];
    if (item.appliedDiscountPercents.length >= fields.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Limite máximo de ${fields.length} campo(s) atingido.'),
        ),
      );
      return;
    }

    setState(() {
      final refreshed = List<double>.from(item.appliedDiscountPercents)..add(0);
      _items[index] = item.copyWith(appliedDiscountPercents: refreshed);
      _ensureDiscountControllersForItem(item, refreshed.length);
    });
  }

  Future<bool> _applyInlineItemDiscounts(
    int index, {
    bool showErrors = true,
  }) async {
    if (index < 0 || index >= _items.length || widget.saving) {
      return false;
    }

    await _ensureOrderDiscountPolicyLoaded();
    if (!mounted) {
      return false;
    }

    final fields = _orderDiscountPolicy.fields;
    if (fields.isEmpty) {
      return true;
    }

    final item = _items[index];
    final activeSlots = item.appliedDiscountPercents.length;
    if (activeSlots <= 0) {
      return true;
    }

    final controllers = _ensureDiscountControllersForItem(item, activeSlots);
    final values = <double>[];
    for (var i = 0; i < activeSlots; i++) {
      final fieldLabel = i < fields.length
          ? fields[i].label
          : 'Desconto ${i + 1}';
      final raw = controllers[i].text.trim();
      if (raw.isEmpty) {
        values.add(0);
        continue;
      }

      final parsed = _parsePercentInput(raw);
      if (parsed == null) {
        if (showErrors) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Valor inválido em $fieldLabel.')),
          );
        }
        return false;
      }

      if (i < fields.length) {
        final min = fields[i].minPercent;
        final max = fields[i].maxPercent;
        if (parsed < min || parsed > max) {
          if (showErrors) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$fieldLabel deve estar entre ${_formatPercent(min)} e ${_formatPercent(max)}.',
                ),
              ),
            );
          }
          return false;
        }
      }

      values.add(parsed);
    }

    final product = _findProductById(item.productId);
    if (product == null) {
      setState(() {
        _items[index] = _items[index].copyWith(appliedDiscountPercents: values);
      });
      return true;
    }

    final itemId = item.id;
    final applyRevision = _discountControllerManager.bumpApplyRevision(itemId);

    final computed = await _resolveItemValues(
      product: product,
      quantity: item.quantity,
      previousSnapshot: item.taxSnapshot,
      previousQuantity: item.quantity,
      appliedDiscountPercents: values,
    );

    if (!mounted) {
      return false;
    }

    if (!_discountControllerManager.isApplyRevisionCurrent(
      itemId,
      applyRevision,
    )) {
      return false;
    }

    final refreshedIndex = _items.indexWhere((current) => current.id == itemId);
    if (refreshedIndex < 0) {
      return false;
    }

    setState(() {
      _items[refreshedIndex] = _items[refreshedIndex].copyWith(
        unitPrice: computed.unitPrice,
        totalPrice: computed.totalPrice,
        taxSnapshot: computed.taxSnapshot,
        appliedDiscountPercents: values,
      );
    });
    return true;
  }

  Future<bool> _validateAllInlineDiscountsBeforeSave() async {
    if (_items.isEmpty) {
      return true;
    }

    for (var index = 0; index < _items.length; index++) {
      final hasDiscounts = _items[index].appliedDiscountPercents.isNotEmpty;
      if (!hasDiscounts) {
        continue;
      }

      final valid = await _applyInlineItemDiscounts(index, showErrors: true);
      if (!valid) {
        return false;
      }
    }

    return true;
  }

  Future<void> _removeInlineItemDiscountField(
    int itemIndex,
    int discountIndex,
  ) async {
    if (itemIndex < 0 || itemIndex >= _items.length || widget.saving) {
      return;
    }

    final item = _items[itemIndex];
    final activeSlots = item.appliedDiscountPercents.length;
    if (discountIndex < 0 || discountIndex >= activeSlots) {
      return;
    }

    await _ensureOrderDiscountPolicyLoaded();
    if (!mounted) {
      return;
    }

    final controllers = _ensureDiscountControllersForItem(item, activeSlots);
    if (discountIndex < controllers.length) {
      controllers[discountIndex].dispose();
      controllers.removeAt(discountIndex);
      _discountControllerManager.setControllersForItem(item.id, controllers);
    }

    final values = <double>[];
    for (var i = 0; i < controllers.length; i++) {
      final raw = controllers[i].text.trim();
      if (raw.isEmpty) {
        values.add(0);
        continue;
      }

      final parsed = _parsePercentInput(raw);
      if (parsed == null) {
        values.add(0);
        continue;
      }
      values.add(parsed);
    }

    final product = _findProductById(item.productId);
    if (product == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _items[itemIndex] = _items[itemIndex].copyWith(
          appliedDiscountPercents: values,
        );
      });
      return;
    }

    final computed = await _resolveItemValues(
      product: product,
      quantity: item.quantity,
      previousSnapshot: item.taxSnapshot,
      previousQuantity: item.quantity,
      appliedDiscountPercents: values,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _items[itemIndex] = _items[itemIndex].copyWith(
        unitPrice: computed.unitPrice,
        totalPrice: computed.totalPrice,
        taxSnapshot: computed.taxSnapshot,
        appliedDiscountPercents: values,
      );
    });
  }

  String _resolveCommercialCode(Produto product) {
    return PedidoCommercialPricingService.resolveCommercialCode(product);
  }

  String _resolveItemDisplayCode(PedidoItem item, Produto? product) {
    if (product != null) {
      final commercialCode = _resolveCommercialCode(product);
      if (commercialCode.isNotEmpty) {
        return commercialCode;
      }
      return '-';
    }

    final fallback = item.productCode.trim();
    return fallback.isEmpty ? '-' : fallback;
  }

  ImageProvider<Object>? _buildProductImageProvider(Produto? product) {
    if (product == null) {
      return null;
    }

    final thumbnail = (product.thumbnailBase64 ?? '').trim();
    if (thumbnail.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(thumbnail));
      } catch (_) {
        // Ignore invalid base64 payload and fallback to URL/placeholder.
      }
    }

    final photoUrl = (product.fotoUrl ?? '').trim();
    if (photoUrl.isNotEmpty) {
      return NetworkImage(photoUrl);
    }
    return null;
  }

  Widget _buildItemThumbnail(Produto? product, String productName) {
    final imageProvider = _buildProductImageProvider(product);
    final fallbackText = productName.trim().isEmpty
        ? '?'
        : productName.trim()[0].toUpperCase();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 44,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: imageProvider == null
            ? Center(
                child: Text(
                  fallbackText,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              )
            : Image(
                image: imageProvider,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) {
                  return Center(
                    child: Text(
                      fallbackText,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  );
                },
              ),
      ),
    );
  }

  double _totalGross() {
    return _items.fold(0, (total, item) => total + item.totalPrice);
  }

  Produto? _findProductById(String productId) {
    for (final product in widget.products) {
      if (product.id == productId) {
        return product;
      }
    }
    return null;
  }

  Future<ComputedPedidoItemValues> _resolveItemValues({
    required Produto product,
    required double quantity,
    PedidoItemTaxSnapshot? previousSnapshot,
    double? previousQuantity,
    List<double> appliedDiscountPercents = const <double>[],
  }) async {
    await _ensureCommercialRulesLoaded();
    await _ensureOrderDiscountPolicyLoaded();

    final customerId =
        _clienteReferenciaSelecionada?.id ??
        widget.pedido?.clienteReferencia?.id;

    return _itemPricingService.resolveItemValues(
      tenantId: widget.tenantId.trim(),
      product: product,
      quantity: quantity,
      previousSnapshot: previousSnapshot,
      previousQuantity: previousQuantity,
      appliedDiscountPercents: appliedDiscountPercents,
      discountPolicyFields: _orderDiscountPolicy.fields,
      selectedCliente: _findClienteById(customerId ?? ''),
      customerId: customerId,
      representedCompanyId: _effectiveRepresentedCompanyId,
      originCompanyUf: _itemPricingService.normalizedOriginUf(
        originCompanyUfFromWidget: widget.originCompanyUf,
        originCompanyUfFromPedido: widget.pedido?.originCompanyUf,
      ),
      salePurpose: _selectedSalePurpose,
      commercialRules: _commercialRules,
    );
  }

  Future<void> _recalculateAllItemsForCustomerContext() async {
    if (_items.isEmpty) {
      return;
    }

    final currentItems = List<PedidoItem>.from(_items);
    final recalculatedItems = <PedidoItem>[];
    var usedFallback = false;

    for (final item in currentItems) {
      final product = _findProductById(item.productId);
      if (product == null) {
        recalculatedItems.add(item);
        continue;
      }

      final computed = await _resolveItemValues(
        product: product,
        quantity: item.quantity,
        previousSnapshot: item.taxSnapshot,
        previousQuantity: item.quantity,
        appliedDiscountPercents: item.appliedDiscountPercents,
      );

      usedFallback = usedFallback || computed.usedFallback;
      recalculatedItems.add(
        item.copyWith(
          unitPrice: computed.unitPrice,
          totalPrice: computed.totalPrice,
          taxSnapshot: computed.taxSnapshot,
          appliedDiscountPercents: item.appliedDiscountPercents,
        ),
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _items = recalculatedItems;
    });

    if (usedFallback) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alguns itens permaneceram com preço bruto por falta de tabela/regra fiscal aplicável.',
          ),
        ),
      );
    }
  }

  Future<void> _setItemQuantity(int index, int nextQuantity) async {
    if (index < 0 || index >= _items.length) {
      return;
    }

    if (nextQuantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade deve ser maior que zero.')),
      );
      return;
    }

    if (nextQuantity > 99999) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade maxima: 99999.')),
      );
      return;
    }

    final current = _items[index];
    final currentId = current.id;
    final product = _findProductById(current.productId);

    if (product == null) {
      setState(() {
        _items[index] = current.copyWith(
          quantity: nextQuantity.toDouble(),
          totalPrice: _roundCurrency(nextQuantity * current.unitPrice),
        );
      });
      return;
    }

    final computed = await _resolveItemValues(
      product: product,
      quantity: nextQuantity.toDouble(),
      previousSnapshot: current.taxSnapshot,
      previousQuantity: current.quantity,
      appliedDiscountPercents: current.appliedDiscountPercents,
    );

    if (!mounted) {
      return;
    }

    final refreshedIndex = _items.indexWhere((item) => item.id == currentId);
    if (refreshedIndex < 0) {
      return;
    }

    setState(() {
      _items[refreshedIndex] = _items[refreshedIndex].copyWith(
        quantity: nextQuantity.toDouble(),
        unitPrice: computed.unitPrice,
        totalPrice: computed.totalPrice,
        taxSnapshot: computed.taxSnapshot,
        appliedDiscountPercents: current.appliedDiscountPercents,
      );
    });

    if (computed.usedFallback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impostos não calculados para este item (sem tabela/regra aplicável). Valor mantido pelo preço bruto.',
          ),
        ),
      );
    }
  }

  Future<void> _incrementItemQuantity(int index) async {
    if (index < 0 || index >= _items.length) {
      return;
    }
    final current = _items[index].quantity.round();
    await _setItemQuantity(index, current + 1);
  }

  Future<void> _decrementItemQuantity(int index) async {
    if (index < 0 || index >= _items.length) {
      return;
    }
    final current = _items[index].quantity.round();
    if (current <= 1) {
      return;
    }
    await _setItemQuantity(index, current - 1);
  }

  Future<void> _addProduct(Produto product, {int? quantityOverride}) async {
    if (widget.pedido == null || widget.saving) {
      return;
    }

    // Guards against a double-tap (or an action firing twice in quick
    // succession) racing past the async tax computation below before the
    // previous call's setState has applied - without this, two concurrent
    // calls both see the product as "not yet in the cart" and each add a
    // separate line instead of merging into a single incremented item.
    if (_addingProductInFlight) {
      return;
    }
    _addingProductInFlight = true;

    try {
      final quantity =
          quantityOverride ?? _readIntegerQuantity(_quantityController.text);
      if (quantity <= 0) {
        _showQuantityValidation();
        return;
      }

      if (quantity > 99999) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quantidade maxima: 99999.')),
        );
        return;
      }

      final commercialCode = _resolveCommercialCode(product);
      final existingIndex = _items.indexWhere(
        (item) => item.productId == product.id,
      );

      final existing = existingIndex >= 0 ? _items[existingIndex] : null;
      final nextQty = (existing?.quantity.round() ?? 0) + quantity;
      final computed = await _resolveItemValues(
        product: product,
        quantity: nextQty.toDouble(),
        previousSnapshot: existing?.taxSnapshot,
        previousQuantity: existing?.quantity,
        appliedDiscountPercents:
            existing?.appliedDiscountPercents ?? const <double>[],
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (existingIndex >= 0) {
          final existingItem = _items[existingIndex];
          _items[existingIndex] = existingItem.copyWith(
            quantity: nextQty.toDouble(),
            unitPrice: computed.unitPrice,
            totalPrice: computed.totalPrice,
            taxSnapshot: computed.taxSnapshot,
            appliedDiscountPercents: existingItem.appliedDiscountPercents,
          );
        } else {
          _items.add(
            PedidoItem(
              id: 'itm_${DateTime.now().microsecondsSinceEpoch}_${product.id}',
              productId: product.id,
              productCode: commercialCode.isEmpty ? '-' : commercialCode,
              productName: product.descricao,
              quantity: quantity.toDouble(),
              unitPrice: computed.unitPrice,
              totalPrice: computed.totalPrice,
              appliedDiscountPercents: const <double>[],
              unit: product.unidade,
              ncm: product.ncm,
              taxSnapshot: computed.taxSnapshot,
            ),
          );
        }
        _quantityController.text = '1';
        _searchController.clear();
        _searchQuery = '';
      });

      if (computed.usedFallback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impostos não calculados para este item (sem tabela/regra aplicável). Valor mantido pelo preço bruto.',
            ),
          ),
        );
      }

      _searchFocusNode.requestFocus();
    } finally {
      _addingProductInFlight = false;
    }
  }

  Future<void> _openSearchResultsModal(List<Produto> searchResults) async {
    if (widget.saving || widget.pedido == null) {
      return;
    }

    final normalizedQuery = _normalizeSearch(_searchQuery);
    if (normalizedQuery.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite algo para iniciar a busca.')),
      );
      return;
    }

    if (searchResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum produto encontrado.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return PedidoSearchResultsDialog(
          searchResults: searchResults,
          saving: widget.saving,
          resolveCommercialCode: _resolveCommercialCode,
          formatMoneyBr: _formatMoneyBr,
          onAddProduct: _addProduct,
        );
      },
    );
  }

  Future<void> _openMobileAddItemSheet() async {
    if (widget.saving || widget.pedido == null) {
      return;
    }

    if (widget.products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum produto ativo disponível para este tenant.'),
        ),
      );
      return;
    }

    // Drop focus from the customer autocomplete field before opening the
    // sheet. Otherwise, when the sheet (whose search field has autofocus)
    // closes, Flutter can restore focus back onto the customer field, which
    // reopens its suggestions overlay and leaves it stuck open.
    _customerFocusNode.unfocus();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return PedidoMobileAddItemSheet(
          saving: widget.saving,
          normalizeSearch: _normalizeSearch,
          buildProductResultsForQuery: _buildProductResultsForQuery,
          readIntegerQuantity: _readIntegerQuantity,
          resolveCommercialCode: _resolveCommercialCode,
          formatMoneyBr: _formatMoneyBr,
          inputDecoration: _inputDecoration,
          onAddProduct: (product, {required quantityOverride}) =>
              _addProduct(product, quantityOverride: quantityOverride),
        );
      },
    );

    // Defensive: make sure the customer field stays unfocused after the
    // sheet is dismissed, regardless of how it was closed (X button, back
    // gesture, or after successfully adding an item).
    if (mounted) {
      _customerFocusNode.unfocus();
    }
  }

  void _setCustomerInputError(String? message) {
    setState(() {
      _customerInputError = message;
    });
  }

  void _clearSelectedClienteReference() {
    setState(() {
      _clienteReferenciaSelecionada = null;
    });
  }

  Future<void> _handleSalePurposeChanged(SalePurpose value) async {
    setState(() {
      _selectedSalePurpose = value;
    });
    await _recalculateAllItemsForCustomerContext();
  }

  Widget _buildCustomerSelectorSection({required bool compact}) {
    return PedidoCustomerSelectorSection(
      compact: compact,
      customerController: _customerController,
      customerFocusNode: _customerFocusNode,
      clientes: _clientes,
      loadingClientes: _loadingClientes,
      customerReadDenied: _customerReadDenied,
      customerInputError: _customerInputError,
      saving: widget.saving,
      selectedSalePurpose: _selectedSalePurpose,
      selectedClienteId: _clienteReferenciaSelecionada?.id ?? '',
      formatClienteLabel: _formatClienteLabel,
      normalizeSearch: _normalizeSearch,
      findClienteById: _findClienteById,
      findClienteByTypedText: _findClienteByTypedText,
      inputDecoration: _inputDecoration,
      onSelectCustomerById: _selectCustomerById,
      onCustomerInputErrorChanged: _setCustomerInputError,
      onClearSelectedClienteReference: _clearSelectedClienteReference,
      onSalePurposeChanged: _handleSalePurposeChanged,
    );
  }

  Future<void> _save() async {
    final pedido = widget.pedido;
    if (pedido == null || widget.saving) {
      return;
    }

    await _ensurePaymentConditionRulesLoaded();
    if (!mounted) {
      return;
    }

    _sanitizeSelectedPaymentConditionIfNeeded(forceClearWhenUnavailable: false);

    final eligiblePaymentRules = _eligiblePaymentConditionRules();
    if (eligiblePaymentRules.isNotEmpty) {
      final selected = (_selectedPaymentConditionDescription ?? '').trim();
      if (selected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione uma forma de pagamento.')),
        );
        return;
      }
    }

    if (!await _validateCustomerSelectionForSave()) {
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione um cliente válido da lista.'),
          ),
        );
      }
      _customerFocusNode.requestFocus();
      return;
    }

    final discountsValid = await _validateAllInlineDiscountsBeforeSave();
    if (!discountsValid) {
      return;
    }

    await widget.onSave(
      pedido,
      List<PedidoItem>.from(_items),
      _clienteReferenciaSelecionada,
      _selectedSalePurpose,
      _selectedPaymentConditionDescription,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;
    final hasSelection = pedido != null;
    final canClose = !widget.saving;
    final searchResults = hasSelection
        ? _buildProductResults()
        : const <Produto>[];
    final hasQuery = _normalizeSearch(_searchQuery).isNotEmpty;
    final visibleLimit = 8;
    final visibleResults = searchResults.take(visibleLimit).toList();
    final hasMoreResults = searchResults.length > visibleLimit;
    final productsById = <String, Produto>{
      for (final product in widget.products) product.id: product,
    };
    const itemTableColumnWidths = <int, TableColumnWidth>{
      0: FlexColumnWidth(5),
      1: FlexColumnWidth(4),
      2: FlexColumnWidth(2),
      3: FlexColumnWidth(2),
    };
    const itemRowHorizontalPadding = 10.0;
    const itemThumbnailSlotWidth = 54.0;
    const itemActionSlotWidth = 48.0;
    final isCompactItems = MediaQuery.sizeOf(context).shortestSide < 700;
    final bottomBarMinimum = isCompactItems
        ? const EdgeInsets.fromLTRB(8, 4, 8, 4)
        : const EdgeInsets.fromLTRB(10, 8, 10, 8);
    final editorHeight = widget.maxBodyHeight.clamp(260.0, 1000.0);

    return SizedBox(
      height: editorHeight,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: const BoxDecoration(color: _bodyColor),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              PedidoEditorTopBar(
                title: hasSelection
                    ? 'Pedido ${_pedidoDisplayNumber(pedido.id)}'
                    : 'Editor de pedido',
                compact: isCompactItems,
                canClose: canClose,
                chromeColor: _chromeColor,
                onClose: widget.onClose,
              ),
              if (hasSelection && !isCompactItems)
                _buildCustomerSelectorSection(compact: false),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: _bodyColor,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                  child: widget.loadingProducts
                      ? const Center(child: CircularProgressIndicator())
                      : !hasSelection
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            'Este pedido não está mais disponível. Volte para a lista e selecione outro.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isCompactItems) ...[
                              PedidoEditorDesktopSearchHeader(
                                searchController: _searchController,
                                searchFocusNode: _searchFocusNode,
                                quantityController: _quantityController,
                                saving: widget.saving,
                                hasQuery: hasQuery,
                                visibleResultsCount: visibleResults.length,
                                searchResultsCount: searchResults.length,
                                inputDecoration: _inputDecoration,
                                onSearchChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
                                onSubmitSearch: () =>
                                    _openSearchResultsModal(searchResults),
                                onOpenSearchModal: () =>
                                    _openSearchResultsModal(searchResults),
                                onAddFirstVisibleResult:
                                    visibleResults.isEmpty || widget.saving
                                    ? null
                                    : () => _addProduct(visibleResults.first),
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.add_shopping_cart_outlined,
                                    size: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Toque no botão para buscar e adicionar itens.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                            Expanded(
                              child: Stack(
                                children: [
                                  ListView(
                                    padding: EdgeInsets.only(
                                      bottom: isCompactItems ? 76 : 0,
                                    ),
                                    children: [
                                      if (isCompactItems && hasSelection) ...[
                                        _buildCustomerSelectorSection(
                                          compact: true,
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      if (widget.products.isEmpty)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .dividerColor,
                                            ),
                                          ),
                                          child: const Text(
                                            'Nenhum produto ativo disponível para este tenant.',
                                          ),
                                        )
                                      else if (!isCompactItems &&
                                          visibleResults.isNotEmpty)
                                        PedidoSearchResultsPreviewList(
                                          visibleResults: visibleResults,
                                          searchResultsCount:
                                              searchResults.length,
                                          hasMoreResults: hasMoreResults,
                                          saving: widget.saving,
                                          resolveCommercialCode:
                                              _resolveCommercialCode,
                                          formatMoneyBr: _formatMoneyBr,
                                          onAddProduct: _addProduct,
                                          onViewAllResults: () =>
                                              _openSearchResultsModal(
                                                searchResults,
                                              ),
                                        ),
                                      if (!isCompactItems)
                                        const SizedBox(height: 8),
                                      if (_items.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          child: const Text(
                                            'Nenhum item adicionado.',
                                          ),
                                        )
                                      else
                                        Column(
                                          children: [
                                            if (!isCompactItems)
                                              Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      itemRowHorizontalPadding,
                                                      8,
                                                      itemRowHorizontalPadding,
                                                      8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                                ),
                                                child: Row(
                                                  children: [
                                                    const SizedBox(
                                                      width:
                                                          itemThumbnailSlotWidth,
                                                    ),
                                                    Expanded(
                                                      child: Table(
                                                        columnWidths:
                                                            itemTableColumnWidths,
                                                        children: [
                                                          TableRow(
                                                            children: [
                                                              Align(
                                                                alignment: Alignment
                                                                    .centerLeft,
                                                                child: Text(
                                                                  'Produto',
                                                                  style: Theme.of(
                                                                    context,
                                                                  ).textTheme.labelMedium,
                                                                ),
                                                              ),
                                                              Align(
                                                                alignment:
                                                                    Alignment
                                                                        .center,
                                                                child: Text(
                                                                  'Qtd',
                                                                  style: Theme.of(
                                                                    context,
                                                                  ).textTheme.labelMedium,
                                                                ),
                                                              ),
                                                              Align(
                                                                alignment: Alignment
                                                                    .centerRight,
                                                                child: Text(
                                                                  'Preco',
                                                                  style: Theme.of(
                                                                    context,
                                                                  ).textTheme.labelMedium,
                                                                ),
                                                              ),
                                                              Align(
                                                                alignment: Alignment
                                                                    .centerRight,
                                                                child: Text(
                                                                  'Total',
                                                                  style: Theme.of(
                                                                    context,
                                                                  ).textTheme.labelMedium,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(
                                                      width:
                                                          itemActionSlotWidth,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (!isCompactItems)
                                              const SizedBox(height: 6),
                                            ListView.separated(
                                              shrinkWrap: true,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              itemCount: _items.length,
                                              separatorBuilder: (_, index) =>
                                                  const Divider(height: 1),
                                              itemBuilder: (context, index) {
                                                final item = _items[index];
                                                final product =
                                                    productsById[item
                                                        .productId];
                                                return PedidoItemRow(
                                                  item: item,
                                                  product: product,
                                                  index: index,
                                                  isCompactItems:
                                                      isCompactItems,
                                                  saving: widget.saving,
                                                  policyFields:
                                                      _orderDiscountPolicy
                                                          .fields,
                                                  columnWidths:
                                                      itemTableColumnWidths,
                                                  rowHorizontalPadding:
                                                      itemRowHorizontalPadding,
                                                  actionSlotWidth:
                                                      itemActionSlotWidth,
                                                  resolveItemDisplayCode:
                                                      _resolveItemDisplayCode,
                                                  formatPercent: _formatPercent,
                                                  formatMoney: _formatMoney,
                                                  formatQuantity:
                                                      _formatQuantity,
                                                  readIntegerQuantity:
                                                      _readIntegerQuantity,
                                                  formatPointDiscountSummary:
                                                      _formatPointDiscountSummary,
                                                  ensureDiscountControllersForItem:
                                                      _ensureDiscountControllersForItem,
                                                  buildItemThumbnail:
                                                      _buildItemThumbnail,
                                                  showItemTaxDetailsDialog:
                                                      _showItemTaxDetailsDialog,
                                                  onDecrementQuantity:
                                                      _decrementItemQuantity,
                                                  onIncrementQuantity:
                                                      _incrementItemQuantity,
                                                  onSetQuantity:
                                                      _setItemQuantity,
                                                  onApplyInlineDiscounts:
                                                      _applyInlineItemDiscounts,
                                                  onRemoveDiscountField:
                                                      _removeInlineItemDiscountField,
                                                  onAddDiscountField:
                                                      _addPointDiscountField,
                                                  onRemoveItem: () {
                                                    setState(() {
                                                      _disposeDiscountControllersForItem(
                                                        item.id,
                                                      );
                                                      _items.removeAt(index);
                                                    });
                                                  },
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 12),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                              ),
                                              child: Text(
                                                'Total de itens: ${_items.length} · Total com impostos: R\$ ${_formatMoney(_totalGross())}',
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            FutureBuilder<void>(
                                              future:
                                                  _ensurePaymentConditionRulesLoaded(),
                                              builder: (context, paymentSnapshot) {
                                                final loading =
                                                    paymentSnapshot
                                                        .connectionState ==
                                                    ConnectionState.waiting;
                                                final eligibleRules =
                                                    _eligiblePaymentConditionRules();
                                                final options =
                                                    eligibleRules
                                                        .map(
                                                          (rule) => rule
                                                              .description
                                                              .trim(),
                                                        )
                                                        .where(
                                                          (value) =>
                                                              value.isNotEmpty,
                                                        )
                                                        .toSet()
                                                        .toList(growable: false)
                                                      ..sort(
                                                        (a, b) => a
                                                            .toLowerCase()
                                                            .compareTo(
                                                              b.toLowerCase(),
                                                            ),
                                                      );

                                                final selected =
                                                    (_selectedPaymentConditionDescription ??
                                                            '')
                                                        .trim();
                                                final selectedInOptions =
                                                    selected.isNotEmpty &&
                                                    options.contains(selected);

                                                if (!selectedInOptions &&
                                                    selected.isNotEmpty) {
                                                  WidgetsBinding.instance
                                                      .addPostFrameCallback((
                                                        _,
                                                      ) {
                                                        if (!mounted) {
                                                          return;
                                                        }
                                                        setState(() {
                                                          _selectedPaymentConditionDescription =
                                                              null;
                                                        });
                                                      });
                                                }

                                                return Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .surface,
                                                    border: Border.all(
                                                      color: Theme.of(context)
                                                          .dividerColor,
                                                    ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Forma de Pagamento',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .labelLarge,
                                                      ),
                                                      const SizedBox(height: 6),
                                                      if (loading)
                                                        const LinearProgressIndicator(
                                                          minHeight: 2,
                                                        )
                                                      else if (options.isEmpty)
                                                        Text(
                                                          'Nenhuma condição disponível para o total atual.',
                                                          style: Theme.of(
                                                            context,
                                                          ).textTheme.bodySmall,
                                                        )
                                                      else
                                                        DropdownButtonFormField<
                                                          String
                                                        >(
                                                          initialValue:
                                                              selectedInOptions
                                                              ? selected
                                                              : null,
                                                          decoration:
                                                              _inputDecoration(
                                                                label: 'Selecione uma condição',
                                                              ),
                                                          isExpanded: true,
                                                          items: options
                                                              .map(
                                                                (
                                                                  description,
                                                                ) => DropdownMenuItem<String>(
                                                                  value:
                                                                      description,
                                                                  child: Text(
                                                                    description,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                              )
                                                              .toList(
                                                                growable: false,
                                                              ),
                                                          onChanged:
                                                              widget.saving
                                                              ? null
                                                              : (value) {
                                                                  setState(() {
                                                                    _selectedPaymentConditionDescription =
                                                                        (value ??
                                                                                '')
                                                                            .trim()
                                                                            .isEmpty
                                                                        ? null
                                                                        : value;
                                                                  });
                                                                },
                                                        ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  if (isCompactItems)
                                    Positioned(
                                      right: 6,
                                      bottom: 8,
                                      child: FloatingActionButton(
                                        heroTag: 'pedido_add_item_mobile_fab',
                                        tooltip: 'Adicionar item',
                                        onPressed:
                                            widget.saving ||
                                                widget.loadingProducts
                                            ? null
                                            : _openMobileAddItemSheet,
                                        child: const Icon(
                                          Icons.add_shopping_cart_outlined,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              Container(
                width: double.infinity,
                color: _chromeColor,
                child: SafeArea(
                  top: false,
                  minimum: bottomBarMinimum,
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: canClose ? widget.onClose : null,
                        style: isCompactItems
                            ? TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: const Size(0, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              )
                            : null,
                        child: const Text('Fechar'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: hasSelection && !widget.saving
                            ? _save
                            : null,
                        style: isCompactItems
                            ? FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                minimumSize: const Size(0, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              )
                            : null,
                        child: Text(
                          widget.saving ? 'Salvando...' : 'Salvar rascunho',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PedidoOfflineSaveMarker {
  const _PedidoOfflineSaveMarker();
}
