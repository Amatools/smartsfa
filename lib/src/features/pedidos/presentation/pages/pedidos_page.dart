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
import '../services/pedido_format_utils.dart';
import '../widgets/pedido_inline_editor.dart';
import '../widgets/pedido_list_widgets.dart';

String _pedidoDisplayNumber(String id) {
  return PedidoFormatUtils.pedidoDisplayNumber(id);
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
                    child: PedidoInlineEditor(
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

class _PedidoOfflineSaveMarker {
  const _PedidoOfflineSaveMarker();
}
