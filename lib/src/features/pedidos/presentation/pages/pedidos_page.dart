import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/data/firestore/catalog_snapshot_tax_rule_repository.dart';
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
import '../../../../core/services/enterprise_represented_scope.dart';
import '../../../../core/services/offline_sync_queue.dart';
import '../../../../core/models/produto.dart';
import '../../../auth/services/tenant_membership_service.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../../../precos/services/product_tax_engine_service.dart';
import '../services/pedido_format_utils.dart';
import '../services/pedido_pdf_service.dart';
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
  final PedidoPdfService _pedidoPdfService = const PedidoPdfService();
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
      // Offline-first: le o snapshot local ja sincronizado (mesmo padrao de
      // produtos no editor) antes de depender de uma consulta ao vivo no
      // Firestore para calcular o imposto do item.
      taxRuleRepository: CatalogSnapshotTaxRuleRepository(
        remote: FirestoreTaxRuleRepository(firestore),
      ),
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
    final raw = fromWidget.isNotEmpty
        ? fromWidget
        : (_selectedRepresentedCompanyId ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    // Ver `EnterpriseRepresentedScope`: contas enterprise usam um id
    // sintetico que nunca deve chegar "cru" em consumidores escopados (motor
    // fiscal, descontos de pedido/comerciais) - normaliza aqui, na origem,
    // para que todo consumidor downstream receba o mesmo valor ja guardado.
    return EnterpriseRepresentedScope.effectiveRepresentedCompanyId(
      tenantId: widget.identity.tenantId,
      representedCompanyId: raw,
    );
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

  bool _canEditOrder(Pedido pedido) {
    return pedido.statusFila != OrderStatus.sent;
  }

  bool _canDeleteOrder(Pedido pedido) {
    return pedido.statusFila == OrderStatus.draft ||
        pedido.statusFila == OrderStatus.pendingCustomer;
  }

  bool _canApproveOrder(Pedido pedido) {
    return pedido.statusFila == OrderStatus.pendingCustomer;
  }

  bool _canSendOrder(Pedido pedido) {
    return pedido.statusFila == OrderStatus.pendingSend;
  }

  Future<void> _selectOrderForEditing(Pedido pedido) async {
    if (!_canEditOrder(pedido)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido enviado nao pode mais ser editado.'),
        ),
      );
      return;
    }

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
      final hasAnyItem = editedItems.isNotEmpty;
      final nextStatus = pedido.statusFila == OrderStatus.draft && hasAnyItem
          ? OrderStatus.pendingCustomer
          : pedido.statusFila;
      final updatedOrder = pedido.copyWith(
        clienteReferencia: editedClienteReferencia,
        clearClienteReferencia: editedClienteReferencia == null,
        salePurpose: editedSalePurpose,
        formaPagamento: (editedFormaPagamento ?? '').trim().isEmpty
            ? null
            : editedFormaPagamento?.trim(),
        statusFila: nextStatus,
        itens: editedItems,
        totalItens: _roundCurrency(_totalQuantity(editedItems)),
        totalBruto: _roundCurrency(_totalGross(editedItems)),
        updatedAt: now,
      );

      final movedToPendingCustomer =
          pedido.statusFila == OrderStatus.draft &&
          nextStatus == OrderStatus.pendingCustomer;
      await _saveOrderLocalFirst(
        order: updatedOrder,
        syncedMessage: movedToPendingCustomer
            ? 'Pedido ${_pedidoDisplayNumber(pedido.id)} salvo e movido para pendente cliente.'
            : 'Pedido ${_pedidoDisplayNumber(pedido.id)} atualizado com ${editedItems.length} item(ns).',
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

  Future<void> _approveOrder(Pedido pedido) async {
    if (!_canApproveOrder(pedido)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aprovacao disponivel apenas para pendente cliente.'),
        ),
      );
      return;
    }

    final now = DateTime.now().toUtc();
    final updatedOrder = pedido.copyWith(
      statusFila: OrderStatus.pendingSend,
      updatedAt: now,
    );

    await _saveOrderLocalFirst(
      order: updatedOrder,
      syncedMessage:
          'Pedido ${_pedidoDisplayNumber(pedido.id)} aprovado e movido para pendente de envio.',
      pendingActionLabel: 'aprovado',
    );
  }

  Future<void> _sendOrder(Pedido pedido) async {
    if (!_canSendOrder(pedido)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Envio disponivel apenas para pendente envio.'),
        ),
      );
      return;
    }

    final hasErpIntegration = await _hasErpIntegrationConfigured(
      pedido.tenantId,
    );
    if (hasErpIntegration) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Envio ERP ainda sera conectado nesta acao. Enquanto isso, use o fluxo sem integracao para gerar o PDF.',
          ),
        ),
      );
      return;
    }

    try {
      final headerContext = await _buildPdfHeaderContext(pedido);

      await _pedidoPdfService.openOrderPdfWithDefaultApp(
        pedido: pedido,
        headerContext: headerContext,
      );

      final shouldMarkAsSent = await _confirmMarkAsSent(pedido);
      if (!shouldMarkAsSent) {
        return;
      }

      final now = DateTime.now().toUtc();
      final sentOrder = pedido.copyWith(
        statusFila: OrderStatus.sent,
        updatedAt: now,
      );
      await _saveOrderLocalFirst(
        order: sentOrder,
        syncedMessage:
            'Pedido ${_pedidoDisplayNumber(pedido.id)} marcado como enviado.',
        pendingActionLabel: 'enviado',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao abrir PDF do pedido: $error')),
      );
    }
  }

  Future<void> _openOrderPdfPreview(Pedido pedido) async {
    if (!mounted) {
      return;
    }

    try {
      final headerContext = await _buildPdfHeaderContext(pedido);
      await _pedidoPdfService.openOrderPdfWithDefaultApp(
        pedido: pedido,
        headerContext: headerContext,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Falha ao abrir PDF: $error')));
    }
  }

  Future<PedidoPdfHeaderContext> _buildPdfHeaderContext(Pedido pedido) async {
    final cliente = await _resolveClienteForPdf(pedido);
    final represented = await _resolveRepresentedForPdf(pedido);
    final userLogoDataUrl = await _resolveUserLogoDataUrlForPdf();

    final contractingCompanyName = (widget.identity.tenantName).trim();
    return PedidoPdfHeaderContext(
      contractingCompanyName: contractingCompanyName.isEmpty
          ? 'Empresa contratante'
          : contractingCompanyName,
      represented: represented,
      customer: _buildCustomerForPdf(pedido: pedido, cliente: cliente),
      sellerName: _buildSellerDisplayName(),
      userLogoDataUrl: userLogoDataUrl,
      transportadora: null,
      observacoes: null,
    );
  }

  Future<String?> _resolveUserLogoDataUrlForPdf() async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      return null;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      final primary = (data['logoDataUrl'] ?? '').toString().trim();
      if (primary.isNotEmpty) {
        return primary;
      }
      final legacy = (data['logoUrl'] ?? '').toString().trim();
      return legacy.isEmpty ? null : legacy;
    } catch (_) {
      return null;
    }
  }

  String _buildSellerDisplayName() {
    final sellerName = (widget.identity.userLabel).trim();
    final sellerEmail = (FirebaseAuth.instance.currentUser?.email ?? '')
        .trim()
        .toLowerCase();

    if (sellerName.isEmpty && sellerEmail.isEmpty) {
      return '-';
    }
    if (sellerName.isEmpty) {
      return sellerEmail;
    }
    if (sellerEmail.isEmpty) {
      return sellerName;
    }
    if (sellerName.toLowerCase() == sellerEmail) {
      return sellerName;
    }
    return '$sellerName - $sellerEmail';
  }

  Future<Cliente?> _resolveClienteForPdf(Pedido pedido) async {
    final clienteId = (pedido.clienteReferencia?.id ?? '').trim();
    if (clienteId.isEmpty) {
      return null;
    }

    try {
      return await _clienteRepository.fetchById(
        tenantId: pedido.tenantId,
        id: clienteId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<PedidoPdfRepresentedData?> _resolveRepresentedForPdf(
    Pedido pedido,
  ) async {
    final representedId = (pedido.representedCompanyId ?? '').trim();
    // Em contas enterprise o representedCompanyId efetivo e vazio (id
    // sintetico e normalizado fora), entao omitimos essa secao.
    if (representedId.isEmpty) {
      return null;
    }

    final fallbackName = (pedido.originCompanyUnitLabel ?? '').trim();
    String name = fallbackName;
    String? phone;
    String? email;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('tenant_represented_companies')
          .doc('${pedido.tenantId}_$representedId')
          .get();
      final data = doc.data();
      if (data != null) {
        final mappedName = (data['nomeFantasia'] ?? '').toString().trim();
        if (mappedName.isNotEmpty) {
          name = mappedName;
        }
        phone = (data['telefone'] ?? '').toString().trim();
        email = (data['email'] ?? '').toString().trim();
      }
    } catch (_) {
      // Best-effort: segue com snapshot do pedido.
    }

    if (name.isEmpty) {
      name = representedId;
    }

    return PedidoPdfRepresentedData(name: name, phone: phone, email: email);
  }

  PedidoPdfCustomerData _buildCustomerForPdf({
    required Pedido pedido,
    required Cliente? cliente,
  }) {
    final snapshotName = (pedido.clienteReferencia?.nomeSnapshot ?? '').trim();
    final snapshotDoc = (pedido.clienteReferencia?.documentoSnapshot ?? '')
        .trim();

    return PedidoPdfCustomerData(
      cliente: _firstNonEmpty([cliente?.nome, snapshotName]),
      nomeFantasia: _firstNonEmpty([cliente?.nomeFantasia]),
      cnpj: _firstNonEmpty([cliente?.documento, snapshotDoc]),
      ie: _firstNonEmpty([cliente?.inscricaoEstadual]),
      endereco: _buildCustomerAddress(cliente),
      bairro: _firstNonEmpty([cliente?.bairro]),
      cep: _firstNonEmpty([cliente?.cep]),
      cidade: _firstNonEmpty([cliente?.cidade]),
      estado: _firstNonEmpty([cliente?.estado]),
      telefone: _firstNonEmpty([cliente?.telefone, cliente?.celular]),
      email: _firstNonEmpty([cliente?.email]),
    );
  }

  String _buildCustomerAddress(Cliente? cliente) {
    if (cliente == null) {
      return '-';
    }

    final parts = <String>[];
    final logradouro = cliente.logradouro.trim();
    final numero = cliente.numero.trim();
    final complemento = cliente.complemento.trim();

    if (logradouro.isNotEmpty) {
      parts.add(logradouro);
    }
    if (numero.isNotEmpty) {
      parts.add(numero);
    }
    if (complemento.isNotEmpty) {
      parts.add(complemento);
    }

    if (parts.isEmpty) {
      return '-';
    }
    return parts.join(', ');
  }

  String _firstNonEmpty(List<String?> values, {String fallback = '-'}) {
    for (final raw in values) {
      final normalized = (raw ?? '').trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return fallback;
  }

  Future<void> _showOrderReadOnlyDialog(Pedido pedido) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Pedido ${_pedidoDisplayNumber(pedido.id)}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Status: ${pedido.statusFila.label}'),
                const SizedBox(height: 6),
                Text(
                  'Cliente: ${pedido.clienteReferencia?.nomeSnapshot ?? '-'}',
                ),
                Text('Itens: ${pedido.itens.length}'),
                Text(
                  'Quantidade total: ${pedido.totalItens.toStringAsFixed(2)}',
                ),
                Text(
                  'Total bruto: R\$ ${PedidoFormatUtils.formatMoneyBr(pedido.totalBruto)}',
                ),
                const SizedBox(height: 10),
                Text(
                  'Forma de pagamento: ${((pedido.formaPagamento ?? '').trim().isEmpty ? '-' : pedido.formaPagamento)}',
                ),
                Text('Finalidade: ${pedido.salePurpose.label}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmMarkAsSent(Pedido pedido) async {
    if (!mounted) {
      return false;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Marcar como enviado'),
              content: Text(
                'Voce concluiu o compartilhamento do PDF do pedido ${_pedidoDisplayNumber(pedido.id)}?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Ainda nao'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Sim, enviado'),
                ),
              ],
            );
          },
        ) ??
        false;
    return confirmed;
  }

  Future<bool> _hasErpIntegrationConfigured(String tenantId) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return false;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tenants')
          .doc(normalizedTenantId)
          .get();
      final data = snapshot.data();
      if (data == null) {
        return false;
      }

      final rootProvider = (data['erpProvider'] ?? '').toString().trim();
      final integrationRaw = data['erpIntegration'];
      String nestedProvider = '';
      if (integrationRaw is Map) {
        nestedProvider = (integrationRaw['provider'] ?? '').toString().trim();
      }

      final effectiveProvider = nestedProvider.isNotEmpty
          ? nestedProvider
          : rootProvider;
      final normalizedProvider = effectiveProvider.toLowerCase();
      return normalizedProvider == 'sankhya' || normalizedProvider == 'custom';
    } catch (_) {
      return false;
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
    if (!_canDeleteOrder(order)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Exclusao permitida apenas antes de pendente envio.'),
        ),
      );
      return;
    }

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

                return Stack(
                  children: [
                    SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 16, 10, 88),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pedidos',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            const Text('Lista de pedidos.'),
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
                              ...pedidos.map((entry) {
                                final canSend = _canSendOrder(entry.pedido);
                                final canApprove = _canApproveOrder(
                                  entry.pedido,
                                );
                                final isSentOrder =
                                    entry.pedido.statusFila == OrderStatus.sent;
                                final primaryTooltip = canSend
                                    ? 'Enviar pedido'
                                    : (canApprove
                                          ? 'Aprovar pedido'
                                          : (isSentOrder
                                                ? 'Pedido enviado'
                                                : 'Ação indisponível'));
                                final primaryIcon = canSend
                                    ? Icons.send_outlined
                                    : (canApprove
                                          ? Icons.check_circle_outline
                                          : (isSentOrder
                                                ? Icons.task_alt_outlined
                                                : Icons.block_outlined));
                                final primaryAction = canSend
                                    ? () => _sendOrder(entry.pedido)
                                    : (canApprove
                                          ? () => _approveOrder(entry.pedido)
                                          : null);

                                return PedidoCard(
                                  entry.pedido,
                                  syncedRemotely: entry.syncedRemotely,
                                  selected: false,
                                  onTap: () {
                                    if (_canEditOrder(entry.pedido)) {
                                      _selectOrderForEditing(entry.pedido);
                                      return;
                                    }
                                    _showOrderReadOnlyDialog(entry.pedido);
                                  },
                                  onPrimaryAction: primaryAction,
                                  primaryActionTooltip: primaryTooltip,
                                  primaryActionIcon: primaryIcon,
                                  onEdit: _canEditOrder(entry.pedido)
                                      ? () =>
                                            _selectOrderForEditing(entry.pedido)
                                      : null,
                                  onPreviewPdf: () =>
                                      _openOrderPdfPreview(entry.pedido),
                                  onDelete: _canDeleteOrder(entry.pedido)
                                      ? () =>
                                            _deleteOrderLocalFirst(entry.pedido)
                                      : null,
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: SafeArea(
                        child: FloatingActionButton.extended(
                          heroTag: 'pedidos-novo-fab',
                          onPressed: _creatingDraft ? null : _createDraftOrder,
                          icon: const Icon(Icons.add_shopping_cart_outlined),
                          label: Text(
                            _creatingDraft ? 'Criando...' : 'Novo pedido',
                          ),
                        ),
                      ),
                    ),
                  ],
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
