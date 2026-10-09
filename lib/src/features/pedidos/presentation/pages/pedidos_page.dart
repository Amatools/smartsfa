import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/data/firestore/firestore_cliente_repository.dart';
import '../../../../core/data/firestore/firestore_customer_price_table_assignment_repository.dart';
import '../../../../core/data/firestore/firestore_product_base_price_repository.dart';
import '../../../../core/data/firestore/firestore_tax_rule_repository.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/cliente.dart';
import '../../../../core/models/cliente_reference.dart';
import '../../../../core/models/pedido.dart';
import '../../../../core/repositories/cliente_repository.dart';
import '../../../../core/repositories/customer_price_table_assignment_repository.dart';
import '../../../../core/repositories/pedido_repository.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../../core/services/offline_sync_queue.dart';
import '../../../../core/models/produto.dart';
import '../../../auth/services/tenant_membership_service.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../../../precos/presentation/services/default_price_table_guard.dart';
import '../../../precos/services/product_tax_engine_service.dart';

String _pedidoDisplayNumber(String id) {
  final normalized = id.trim();
  if (normalized.isEmpty) {
    return '-';
  }

  final parts = normalized.split('_');
  final candidate = parts.isNotEmpty ? parts.last.trim() : normalized;
  if (candidate.isNotEmpty && RegExp(r'^\d+$').hasMatch(candidate)) {
    return candidate;
  }

  final digits = RegExp(r'\d+')
      .allMatches(normalized)
      .map((m) => m.group(0))
      .whereType<String>()
      .join();
  if (digits.isNotEmpty) {
    return digits;
  }

  return normalized;
}

String _formatMoneyBr(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
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
  String? _editingOrderId;
  List<Produto> _editorProducts = const [];
  late final ClienteRepository _clienteRepository;
  late final CustomerPriceTableAssignmentRepository
  _customerPriceTableAssignmentRepository;
  late final ProductTaxEngineService _taxEngineService;

  @override
  void initState() {
    super.initState();
    final firestore = FirebaseFirestore.instance;
    _clienteRepository = FirestoreClienteRepository(firestore);
    _customerPriceTableAssignmentRepository =
        FirestoreCustomerPriceTableAssignmentRepository(firestore);
    _taxEngineService = ProductTaxEngineService(
      produtoRepository: widget.produtoRepository,
      basePriceRepository: FirestoreProductBasePriceRepository(firestore),
      taxRuleRepository: FirestoreTaxRuleRepository(firestore),
    );
  }

  double _roundCurrency(double value) {
    return (value * 100).roundToDouble() / 100;
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
    try {
      await widget.repository.save(order);
      await OfflineSyncQueue.markSynced(order.id);
      syncedRemotely = true;
    } catch (error) {
      remoteError = error;
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
      final reason = firebaseError == 'permission-denied'
          ? 'sem permissao no Firestore para este usuario'
          : 'sem sincronizar no servidor agora';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido ${_pedidoDisplayNumber(order.id)} $pendingActionLabel localmente ($reason). Ele sera sincronizado quando permitido/conectado.',
          ),
        ),
      );
    }

    setState(() {
      // Rebuild to refresh local queue merge and sync badges.
    });
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

  String _originSummary() {
    final label = (widget.originCompanyUnitLabel ?? '').trim();
    final uf = (widget.originCompanyUf ?? '').trim().toUpperCase();
    if (label.isEmpty && uf.isEmpty) {
      return 'Origem operacional pendente de seleção da representada.';
    }
    if (label.isNotEmpty && uf.isNotEmpty) {
      return 'Origem operacional atual: $label ($uf).';
    }
    if (label.isNotEmpty) {
      return 'Origem operacional atual: $label.';
    }
    return 'Origem operacional atual: UF $uf.';
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
      final products = await widget.produtoRepository.fetchAll(
        tenantId: tenantId,
      );
      final activeProducts =
          products.where((item) => item.status == ProductStatus.active).toList()
            ..sort(
              (a, b) => a.descricao.toLowerCase().compareTo(
                b.descricao.toLowerCase(),
              ),
            );

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
  ) async {
    setState(() {
      _savingDraftEdition = true;
    });

    try {
      final now = DateTime.now().toUtc();
      final updatedOrder = pedido.copyWith(
        clienteReferencia: editedClienteReferencia,
        clearClienteReferencia: editedClienteReferencia == null,
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

    final originLabel = (widget.originCompanyUnitLabel ?? '').trim();
    final originUf = (widget.originCompanyUf ?? '').trim().toUpperCase();
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
        representedCompanyId: (widget.representedCompanyId ?? '').trim().isEmpty
            ? null
            : widget.representedCompanyId!.trim(),
        originCompanyUnitId: (widget.originCompanyUnitId ?? '').trim().isEmpty
            ? null
            : widget.originCompanyUnitId!.trim(),
        originCompanyUnitLabel: originLabel,
        originCompanyUf: originUf,
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

                if (isEditing) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: _PedidoInlineEditor(
                      pedido: editingEntry?.pedido,
                      products: _editorProducts,
                      tenantId: widget.identity.tenantId,
                      representedCompanyId: widget.representedCompanyId,
                      originCompanyUf: widget.originCompanyUf,
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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeaderCard(
                          title: 'Pedidos',
                          subtitle:
                              'Fila offline-first com status de envio e visao por responsavel. ${_originSummary()}',
                          actionLabel: _creatingDraft
                              ? 'Criando...'
                              : 'Novo pedido',
                          onAction: _createDraftOrder,
                          actionEnabled: !_creatingDraft,
                        ),
                        const SizedBox(height: 16),
                        if (pedidos.isEmpty)
                          const _EmptyState(
                            title: 'Nenhum pedido carregado',
                            subtitle: 'Os pedidos locais aparecerão aqui assim que a fila for preenchida.',
                          )
                        else
                          ...pedidos.map(
                            (entry) => _PedidoCard(
                              entry.pedido,
                              syncedRemotely: entry.syncedRemotely,
                              selected: false,
                              onTap: () => _selectOrderForEditing(entry.pedido),
                              onDelete: () => _deleteOrderLocalFirst(entry.pedido),
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

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.actionEnabled = true,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final bool actionEnabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(subtitle),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: actionEnabled ? onAction : null,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _PedidoCard extends StatelessWidget {
  const _PedidoCard(
    this.pedido, {
    required this.syncedRemotely,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final Pedido pedido;
  final bool syncedRemotely;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).dividerColor;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: selected ? 1.2 : 1),
      ),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text('Pedido ${_pedidoDisplayNumber(pedido.id)}'),
        subtitle: Text(
          '${pedido.origemPedido.label} · ${pedido.statusFila.label} · ${pedido.clienteReferencia?.nomeSnapshot ?? '-'}\n'
          'Itens: ${pedido.itens.length} · Quantidade: ${pedido.totalItens.toStringAsFixed(2)} · Total: R\$ ${_formatMoneyBr(pedido.totalBruto)}\n'
          'Origem empresa: ${pedido.originCompanyUnitLabel ?? '-'}${(pedido.originCompanyUf ?? '').trim().isEmpty ? '' : ' (${pedido.originCompanyUf})'}\n'
          'Sync: ${syncedRemotely ? 'sincronizado' : 'pendente'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Excluir pedido',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
      ),
    );
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
  final Map<String, List<TextEditingController>>
  _discountControllersByItemId = <String, List<TextEditingController>>{};
  List<PedidoItem> _items = const [];
  List<Cliente> _clientes = const [];
  bool _loadingClientes = false;
  bool _customerReadDenied = false;
  bool _commercialRulesLoaded = false;
  Future<void>? _commercialRulesLoader;
  List<CommercialAdjustmentRule> _commercialRules =
      const <CommercialAdjustmentRule>[];
  bool _orderDiscountPolicyLoaded = false;
  Future<void>? _orderDiscountPolicyLoader;
  OrderDiscountPolicy _orderDiscountPolicy = const OrderDiscountPolicy();
  ClienteReference? _clienteReferenciaSelecionada;
  String? _customerInputError;
  String? _boundOrderId;
  String _searchQuery = '';
  final WorkspaceProfileService _workspaceProfileService =
      WorkspaceProfileService(FirebaseFirestore.instance);

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
  }

  @override
  void initState() {
    super.initState();
    _syncFromPedidoIfNeeded();
    _loadClientes();
    _loadCommercialRules();
    _loadOrderDiscountPolicy();
  }

  @override
  void didUpdateWidget(covariant _PedidoInlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldScope = _effectiveRepresentedCompanyIdForWidget(oldWidget);
    final newScope = _effectiveRepresentedCompanyId;

    if (oldWidget.tenantId != widget.tenantId) {
      _loadClientes();
      _resetScopedPoliciesState();
      _loadCommercialRules();
      _loadOrderDiscountPolicy();
    }
    if (oldScope != newScope) {
      _resetScopedPoliciesState();
      _loadCommercialRules();
      _loadOrderDiscountPolicy();
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
      final clientes = await widget.clienteRepository.fetchAll(
        tenantId: tenantId,
      );
      final approved =
          clientes
              .where((item) => item.status == CustomerStatus.approved)
              .toList()
            ..sort(
              (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
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
        _disposeAllDiscountControllers();
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
      return;
    }

    _disposeAllDiscountControllers();
    _boundOrderId = currentId;
    _items = List<PedidoItem>.from(widget.pedido?.itens ?? const []);
    _clienteReferenciaSelecionada = widget.pedido?.clienteReferencia;
    _customerController.text = _selectedCustomerDisplayLabel();
    _customerInputError = null;
    _searchController.clear();
    _searchQuery = '';
    _quantityController.text = '1';
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
        _customerInputError = null;
      });
    }

    await _recalculateAllItemsForCustomerContext();
  }

  @override
  void dispose() {
    _disposeAllDiscountControllers();
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

  void _disposeAllDiscountControllers() {
    for (final controllers in _discountControllersByItemId.values) {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
    _discountControllersByItemId.clear();
  }

  void _disposeDiscountControllersForItem(String itemId) {
    final controllers = _discountControllersByItemId.remove(itemId);
    if (controllers == null) {
      return;
    }
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  List<TextEditingController> _ensureDiscountControllersForItem(
    PedidoItem item,
    int slotCount,
  ) {
    final safeSlots = slotCount < 0 ? 0 : slotCount;
    final existing =
        _discountControllersByItemId[item.id] ?? <TextEditingController>[];

    if (safeSlots == 0) {
      for (final controller in existing) {
        controller.dispose();
      }
      _discountControllersByItemId[item.id] = <TextEditingController>[];
      return _discountControllersByItemId[item.id]!;
    }

    while (existing.length < safeSlots) {
      final index = existing.length;
      final initial = index < item.appliedDiscountPercents.length
          ? item.appliedDiscountPercents[index]
          : 0;
      existing.add(
        TextEditingController(
          text: initial <= 0
              ? ''
              : initial
                    .toStringAsFixed(initial % 1 == 0 ? 0 : 2)
                    .replaceAll('.', ','),
        ),
      );
    }

    while (existing.length > safeSlots) {
      existing.removeLast().dispose();
    }

    _discountControllersByItemId[item.id] = existing;
    return existing;
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
    var normalized = value.toLowerCase().trim();
    const replacements = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };
    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  bool _isSubsequence(String needle, String haystack) {
    if (needle.isEmpty) {
      return true;
    }
    var i = 0;
    for (var j = 0; j < haystack.length && i < needle.length; j++) {
      if (needle.codeUnitAt(i) == haystack.codeUnitAt(j)) {
        i++;
      }
    }
    return i == needle.length;
  }

  int _scoreProductMatch(
    Produto product,
    String normalizedQuery,
    List<String> tokens,
  ) {
    final name = _normalizeSearch(product.descricao);
    final code = _normalizeSearch(product.codigoInterno);
    final makerCode = _normalizeSearch(product.codigoFabricante ?? '');
    final sku = _normalizeSearch(product.sku ?? '');
    final ean = _normalizeSearch(product.ean ?? '');
    final brand = _normalizeSearch(product.marca ?? '');
    final ncm = _normalizeSearch(product.ncm ?? '');
    final haystack = '$code $makerCode $sku $ean $name $brand $ncm'.trim();
    if (haystack.isEmpty) {
      return -1;
    }

    var score = 0;
    if (normalizedQuery.isNotEmpty && haystack.contains(normalizedQuery)) {
      score += 260;
      final index = haystack.indexOf(normalizedQuery);
      if (index >= 0) {
        score += 40 - (index ~/ 4);
      }
    }

    for (final token in tokens) {
      if (token.isEmpty) {
        continue;
      }

      if (code.startsWith(token)) {
        score += 130;
      } else if (code.contains(token)) {
        score += 110;
      } else if (name.startsWith(token)) {
        score += 120;
      } else if (name.contains(token)) {
        score += 95;
      } else if (brand.contains(token) || ncm.contains(token)) {
        score += 55;
      } else if (_isSubsequence(token, name) ||
          _isSubsequence(token, haystack)) {
        score += 25;
      } else {
        return -1;
      }
    }

    if (score <= 0) {
      return -1;
    }
    return score;
  }

  List<Produto> _buildProductResults() {
    final normalizedQuery = _normalizeSearch(_searchQuery);
    if (widget.products.isEmpty) {
      return const [];
    }

    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final tokens = normalizedQuery
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();
    final scored = <({Produto product, int score})>[];
    for (final product in widget.products) {
      final score = _scoreProductMatch(product, normalizedQuery, tokens);
      if (score > 0) {
        scored.add((product: product, score: score));
      }
    }

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.product.descricao.toLowerCase().compareTo(
        b.product.descricao.toLowerCase(),
      );
    });

    return scored.map((entry) => entry.product).toList();
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
    return (value * 100).roundToDouble() / 100;
  }

  List<String> _splitRuleTargets(String raw) {
    final targets = <String>[];
    final seen = <String>{};
    for (final value in raw.split(RegExp(r'[,;|\n]+'))) {
      final normalized = _normalizeSearch(value);
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      targets.add(value.trim());
    }
    return targets;
  }

  List<String> _resolveRuleTargets(CommercialAdjustmentRule rule) {
    if (rule.scopeTargets.isNotEmpty) {
      final targets = <String>[];
      final seen = <String>{};
      for (final value in rule.scopeTargets) {
        final normalized = _normalizeSearch(value);
        if (normalized.isEmpty || !seen.add(normalized)) {
          continue;
        }
        targets.add(value.trim());
      }
      return targets;
    }
    return _splitRuleTargets(rule.scopeTarget);
  }

  bool _ruleTargetsContain(
    CommercialAdjustmentRule rule,
    Iterable<String> candidates,
  ) {
    final normalizedTargets = _resolveRuleTargets(rule)
        .map(_normalizeSearch)
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedTargets.isEmpty) {
      return false;
    }

    for (final candidate in candidates) {
      final normalizedCandidate = _normalizeSearch(candidate);
      if (normalizedCandidate.isEmpty) {
        continue;
      }
      if (normalizedTargets.contains(normalizedCandidate)) {
        return true;
      }
    }
    return false;
  }

  bool _ruleMatchesProduct(CommercialAdjustmentRule rule, Produto product) {
    final scope = rule.scope.trim().toLowerCase();
    if (scope == 'geral') {
      return true;
    }

    if (scope == 'marca') {
      return _ruleTargetsContain(rule, <String>[
        product.marca ?? '',
      ]);
    }

    if (scope == 'categoria') {
      return _ruleTargetsContain(rule, <String>[
        product.categoria ?? '',
      ]);
    }

    if (scope == 'produto') {
      final descricao = product.descricao.trim();
      final codigoInterno = product.codigoInterno.trim();
      final comercial = _resolveCommercialCode(product);
      return _ruleTargetsContain(rule, <String>[
        product.id,
        descricao,
        codigoInterno,
        comercial,
        if (codigoInterno.isNotEmpty && descricao.isNotEmpty)
          '$codigoInterno - $descricao',
      ]);
    }

    return false;
  }

  CommercialAdjustmentRule? _resolvePriorityRuleForProduct(Produto product) {
    for (final rule in _commercialRules) {
      if (_ruleMatchesProduct(rule, product)) {
        return rule;
      }
    }
    return null;
  }

  _ComputedPedidoItemValues _applyCommercialRule({
    required _ComputedPedidoItemValues baseValues,
    required Produto product,
    required double quantity,
  }) {
    final rule = _resolvePriorityRuleForProduct(product);
    if (rule == null) {
      return baseValues;
    }

    final safeQuantity = quantity <= 0 ? 1 : quantity;
    var unitPrice = baseValues.unitPrice;
    final valueType = rule.valueType.trim().toLowerCase();
    final adjustmentType = rule.adjustmentType.trim().toLowerCase();
    final amount = rule.value;

    if (valueType == 'percent') {
      final factor = adjustmentType == 'discount'
          ? (1 - (amount / 100))
          : (1 + (amount / 100));
      unitPrice = _roundCurrency(baseValues.unitPrice * factor);
    } else {
      final delta = adjustmentType == 'discount' ? -amount : amount;
      unitPrice = _roundCurrency(baseValues.unitPrice + delta);
    }

    if (unitPrice < 0) {
      unitPrice = 0;
    }

    final unitDiff = unitPrice - baseValues.unitPrice;
    var totalPrice = _roundCurrency(baseValues.totalPrice + (unitDiff * safeQuantity));
    if (totalPrice < 0) {
      totalPrice = 0;
    }

    final snapshot = baseValues.taxSnapshot.copyWith(
      valorTotalItem: totalPrice,
    );

    return _ComputedPedidoItemValues(
      unitPrice: unitPrice,
      totalPrice: totalPrice,
      taxSnapshot: snapshot,
      usedFallback: baseValues.usedFallback,
    );
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatQuantity(double value) {
    return value.round().toString();
  }

  int _readIntegerQuantity(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    return int.tryParse(trimmed) ?? 0;
  }

  String _formatPercent(double value) {
    final hasFraction = (value % 1).abs() > 0.00001;
    final formatted = hasFraction
        ? value.toStringAsFixed(2).replaceAll('.', ',')
        : value.toStringAsFixed(0);
    return '$formatted%';
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
      return 'Sem descontos pontuais';
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
            'Nenhum campo de desconto pontual foi configurado para esta representada.',
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
      final refreshed = List<double>.from(item.appliedDiscountPercents)
        ..add(0);
      _items[index] = item.copyWith(appliedDiscountPercents: refreshed);
      _ensureDiscountControllersForItem(item, refreshed.length);
    });
  }

  Future<void> _applyInlineItemDiscounts(
    int index, {
    bool showErrors = true,
  }) async {
    if (index < 0 || index >= _items.length || widget.saving) {
      return;
    }

    await _ensureOrderDiscountPolicyLoaded();
    if (!mounted) {
      return;
    }

    final fields = _orderDiscountPolicy.fields;
    if (fields.isEmpty) {
      return;
    }

    final item = _items[index];
    final activeSlots = item.appliedDiscountPercents.length;
    if (activeSlots <= 0) {
      return;
    }

    final controllers = _ensureDiscountControllersForItem(item, activeSlots);
    final values = <double>[];
    for (var i = 0; i < activeSlots; i++) {
      final raw = controllers[i].text.trim();
      if (raw.isEmpty) {
        values.add(0);
        continue;
      }

      final parsed = _parsePercentInput(raw);
      if (parsed == null) {
        if (showErrors) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Valor inválido em ${fields[i].label}.')),
          );
        }
        return;
      }

      if (parsed < fields[i].minPercent || parsed > fields[i].maxPercent) {
        if (showErrors) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${fields[i].label} deve estar entre ${_formatPercent(fields[i].minPercent)} e ${_formatPercent(fields[i].maxPercent)}.',
              ),
            ),
          );
        }
        return;
      }
      values.add(parsed);
    }

    final product = _findProductById(item.productId);
    if (product == null) {
      setState(() {
        _items[index] = _items[index].copyWith(appliedDiscountPercents: values);
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
      _items[index] = _items[index].copyWith(
        unitPrice: computed.unitPrice,
        totalPrice: computed.totalPrice,
        taxSnapshot: computed.taxSnapshot,
        appliedDiscountPercents: values,
      );
    });
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

    final fields = _orderDiscountPolicy.fields;
    final controllers = _ensureDiscountControllersForItem(item, activeSlots);
    if (discountIndex < controllers.length) {
      controllers[discountIndex].dispose();
      controllers.removeAt(discountIndex);
      _discountControllersByItemId[item.id] = controllers;
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

      if (i < fields.length) {
        final min = fields[i].minPercent;
        final max = fields[i].maxPercent;
        if (parsed < min || parsed > max) {
          values.add(0);
          continue;
        }
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

  _ComputedPedidoItemValues _applyPointDiscounts({
    required _ComputedPedidoItemValues baseValues,
    required List<double> discountPercents,
  }) {
    if (discountPercents.isEmpty) {
      return baseValues;
    }

    var unitPrice = baseValues.unitPrice;
    var totalPrice = baseValues.totalPrice;
    for (final discount in discountPercents) {
      final safeDiscount = discount < 0 ? 0 : discount;
      if (safeDiscount <= 0) {
        continue;
      }
      final factor = 1 - (safeDiscount / 100);
      unitPrice = _roundCurrency(unitPrice * factor);
      totalPrice = _roundCurrency(totalPrice * factor);
    }

    if (unitPrice < 0) {
      unitPrice = 0;
    }
    if (totalPrice < 0) {
      totalPrice = 0;
    }

    final snapshot = baseValues.taxSnapshot.copyWith(valorTotalItem: totalPrice);
    return _ComputedPedidoItemValues(
      unitPrice: unitPrice,
      totalPrice: totalPrice,
      taxSnapshot: snapshot,
      usedFallback: baseValues.usedFallback,
    );
  }

  String _resolveCommercialCode(Produto product) {
    final codeCandidates = [product.codigoFabricante, product.sku, product.ean];
    for (final candidate in codeCandidates) {
      final normalized = (candidate ?? '').trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
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

  String _normalizedOriginUf() {
    final fromWidget = (widget.originCompanyUf ?? '').trim().toUpperCase();
    if (fromWidget.isNotEmpty) {
      return fromWidget;
    }
    final fromPedido = (widget.pedido?.originCompanyUf ?? '')
        .trim()
        .toUpperCase();
    if (fromPedido.isNotEmpty) {
      return fromPedido;
    }
    return 'SP';
  }

  bool _isInDateWindow(
    DateTime? validFrom,
    DateTime? validUntil,
    DateTime now,
  ) {
    if (validFrom != null && now.isBefore(validFrom.toUtc())) {
      return false;
    }
    if (validUntil != null && now.isAfter(validUntil.toUtc())) {
      return false;
    }
    return true;
  }

  Future<String> _resolveDestinationUf() async {
    final fallback = _normalizedOriginUf();
    final customerId =
        (_clienteReferenciaSelecionada?.id ??
                widget.pedido?.clienteReferencia?.id ??
                '')
            .trim();
    final tenantId = widget.tenantId.trim();
    if (customerId.isEmpty || tenantId.isEmpty) {
      return fallback;
    }

    try {
      final cliente = await widget.clienteRepository.fetchById(
        tenantId: tenantId,
        id: customerId,
      );
      final clienteUf = (cliente?.estado ?? '').trim().toUpperCase();
      return clienteUf.isEmpty ? fallback : clienteUf;
    } catch (_) {
      return fallback;
    }
  }

  Future<String> _resolvePriceTableId(String destinationUf) async {
    final tenantId = widget.tenantId.trim();
    if (tenantId.isEmpty) {
      return '';
    }

    final customerId =
        (_clienteReferenciaSelecionada?.id ??
                widget.pedido?.clienteReferencia?.id ??
                '')
            .trim();
    final now = DateTime.now().toUtc();

    if (customerId.isNotEmpty) {
      try {
        final assignments = await widget.customerPriceTableAssignmentRepository
            .fetchAll(tenantId: tenantId);
        final eligible = assignments
            .where(
              (item) =>
                  item.customerId == customerId &&
                  item.isActive &&
                  _isInDateWindow(item.validFrom, item.validUntil, now),
            )
            .toList();

        eligible.sort((a, b) {
          final aRegion = (a.regionId ?? '').trim().toUpperCase();
          final bRegion = (b.regionId ?? '').trim().toUpperCase();
          final aExact = aRegion == destinationUf;
          final bExact = bRegion == destinationUf;
          if (aExact != bExact) {
            return bExact ? 1 : -1;
          }

          final aDefault = aRegion.isEmpty || a.isDefault;
          final bDefault = bRegion.isEmpty || b.isDefault;
          if (aDefault != bDefault) {
            return bDefault ? 1 : -1;
          }

          return b.priority.compareTo(a.priority);
        });

        final chosen = eligible.isEmpty ? null : eligible.first;
        final assignmentTableId = (chosen?.priceTableId ?? '').trim();
        if (assignmentTableId.isNotEmpty) {
          return assignmentTableId;
        }
      } catch (_) {
        // Falls back to default table id when customer assignment lookup fails.
      }
    }

    return DefaultPriceTableGuard.defaultPriceTableIdForScope(
      tenantId: tenantId,
      representedCompanyId: _effectiveRepresentedCompanyId,
    );
  }

  PedidoItemTaxSnapshot _buildFallbackSnapshotFromProduct({
    required Produto product,
    required double quantity,
    required double unitPrice,
    PedidoItemTaxSnapshot? previous,
    double? previousQuantity,
  }) {
    final baseValue = _roundCurrency(quantity * unitPrice);
    final aliquotaIpi = product.aliquotaIpiBase ?? previous?.aliquotaIpiPercent;
    final valorIpi = aliquotaIpi == null
        ? null
        : _roundCurrency(baseValue * (aliquotaIpi / 100));
    final oldQty = previousQuantity ?? quantity;
    final safeOldQty = oldQty <= 0 ? 1 : oldQty;
    final ratio = quantity / safeOldQty;
    final valorSt = previous?.valorSt == null
        ? 0
        : _roundCurrency(previous!.valorSt! * ratio);
    final valorDifal = previous?.valorDifal == null
        ? 0
        : _roundCurrency(previous!.valorDifal! * ratio);

    final normalizedNcm = (product.ncm ?? '').trim();
    final normalizedCest = (product.cest ?? '').trim();
    return PedidoItemTaxSnapshot(
      regraFiscalId: previous?.regraFiscalId,
      tabelaId: previous?.tabelaId,
      ufDestino: previous?.ufDestino,
      ncm: normalizedNcm.isEmpty ? previous?.ncm : normalizedNcm,
      cest: normalizedCest.isEmpty ? previous?.cest : normalizedCest,
      aliquotaIpiPercent: aliquotaIpi,
      aliquotaDestinoPercent: previous?.aliquotaDestinoPercent,
      aliquotaCreditoPercent: previous?.aliquotaCreditoPercent,
      aliquotaDifalPercent: previous?.aliquotaDifalPercent,
      valorIpi: valorIpi,
      valorSt: previous?.valorSt,
      valorDifal: previous?.valorDifal,
      valorTotalItem: _roundCurrency(
        baseValue + (valorIpi ?? 0) + valorSt + valorDifal,
      ),
    );
  }

  Future<_ComputedPedidoItemValues> _resolveItemValues({
    required Produto product,
    required double quantity,
    PedidoItemTaxSnapshot? previousSnapshot,
    double? previousQuantity,
    List<double> appliedDiscountPercents = const <double>[],
  }) async {
    await _ensureCommercialRulesLoaded();
    await _ensureOrderDiscountPolicyLoaded();

    final fallbackUnitPrice = _roundCurrency(product.valorBruto ?? 0);
    final fallbackSnapshot = _buildFallbackSnapshotFromProduct(
      product: product,
      quantity: quantity,
      unitPrice: fallbackUnitPrice,
      previous: previousSnapshot,
      previousQuantity: previousQuantity,
    );

    final fallback = _ComputedPedidoItemValues(
      unitPrice: fallbackUnitPrice,
      totalPrice: _roundCurrency(quantity * fallbackUnitPrice),
      taxSnapshot: fallbackSnapshot,
      usedFallback: true,
    );

    final tenantId = widget.tenantId.trim();
    if (tenantId.isEmpty) {
      final adjusted = _applyCommercialRule(
        baseValues: fallback,
        product: product,
        quantity: quantity,
      );
      return _applyPointDiscounts(
        baseValues: adjusted,
        discountPercents: appliedDiscountPercents,
      );
    }

    final destinationUf = await _resolveDestinationUf();
    final resolvedTableId = await _resolvePriceTableId(destinationUf);
    if (resolvedTableId.isEmpty) {
      final adjusted = _applyCommercialRule(
        baseValues: fallback,
        product: product,
        quantity: quantity,
      );
      return _applyPointDiscounts(
        baseValues: adjusted,
        discountPercents: appliedDiscountPercents,
      );
    }

    final originUf = _normalizedOriginUf();

    Future<_ComputedPedidoItemValues?> tryTable(String tableId) async {
      if (tableId.trim().isEmpty) {
        return null;
      }

      final result = await widget.taxEngineService.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: product.id,
        tabelaId: tableId,
        clienteUf: destinationUf,
        quantidade: quantity,
        ufOrigem: originUf,
      );

      final safeQty = quantity <= 0 ? 1 : quantity;
      final unitPrice = _roundCurrency(result.precoBase / safeQty);
      final snapshot = PedidoItemTaxSnapshot(
        regraFiscalId: result.regraFiscalId,
        tabelaId: result.tabelaId,
        ufDestino: result.ufDestino,
        ncm: (result.ncm ?? product.ncm)?.trim(),
        cest: (result.cest ?? product.cest)?.trim(),
        aliquotaIpiPercent: product.aliquotaIpiBase,
        aliquotaDestinoPercent: previousSnapshot?.aliquotaDestinoPercent,
        aliquotaCreditoPercent: previousSnapshot?.aliquotaCreditoPercent,
        aliquotaDifalPercent: previousSnapshot?.aliquotaDifalPercent,
        valorIpi: _roundCurrency(result.valorIpi),
        valorSt: _roundCurrency(result.valorSt),
        valorDifal: _roundCurrency(result.valorDifal),
        valorTotalItem: _roundCurrency(result.valorTotalItem),
      );

      return _ComputedPedidoItemValues(
        unitPrice: unitPrice,
        totalPrice: _roundCurrency(result.valorTotalItem),
        taxSnapshot: snapshot,
        usedFallback: false,
      );
    }

    try {
      final primary = await tryTable(resolvedTableId);
      if (primary != null) {
        final adjusted = _applyCommercialRule(
          baseValues: primary,
          product: product,
          quantity: quantity,
        );
        return _applyPointDiscounts(
          baseValues: adjusted,
          discountPercents: appliedDiscountPercents,
        );
      }
    } catch (_) {
      final legacyDefaultTableId =
          DefaultPriceTableGuard.legacyDefaultPriceTableIdForScope(
            tenantId: tenantId,
            representedCompanyId: _effectiveRepresentedCompanyId,
          );

      if (legacyDefaultTableId != resolvedTableId) {
        try {
          final legacy = await tryTable(legacyDefaultTableId);
          if (legacy != null) {
            final adjusted = _applyCommercialRule(
              baseValues: legacy,
              product: product,
              quantity: quantity,
            );
            return _applyPointDiscounts(
              baseValues: adjusted,
              discountPercents: appliedDiscountPercents,
            );
          }
        } catch (_) {
          // Keeps fallback below.
        }
      }
    }

    final adjusted = _applyCommercialRule(
      baseValues: fallback,
      product: product,
      quantity: quantity,
    );
    return _applyPointDiscounts(
      baseValues: adjusted,
      discountPercents: appliedDiscountPercents,
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
      appliedDiscountPercents: existing?.appliedDiscountPercents ?? const <double>[],
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

    final limitedResults = searchResults.take(200).toList();
    final hasTruncated = searchResults.length > limitedResults.length;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 860,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.84,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Resultados da busca (${searchResults.length})',
                          style: Theme.of(dialogContext).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar busca',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                if (hasTruncated)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      'Exibindo ${limitedResults.length} de ${searchResults.length}. Refine a busca para reduzir o volume.',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: limitedResults.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = limitedResults[index];
                      final displayCode = _resolveCommercialCode(product);
                      return Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          dense: true,
                          onTap: widget.saving ? null : () => _addProduct(product),
                          title: Text(product.descricao),
                          subtitle: Text(
                            '${displayCode.isEmpty ? '-' : displayCode} · ${product.marca?.trim().isEmpty ?? true ? '-' : product.marca} · NCM ${product.ncm?.trim().isEmpty ?? true ? '-' : product.ncm} · R\$ ${_formatMoneyBr(product.valorBruto ?? 0)}',
                          ),
                          trailing: IconButton.filledTonal(
                            tooltip: 'Adicionar ao pedido',
                            onPressed: widget.saving
                                ? null
                                : () => _addProduct(product),
                            icon: const Icon(Icons.add),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    final pedido = widget.pedido;
    if (pedido == null || widget.saving) {
      return;
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

    await widget.onSave(
      pedido,
      List<PedidoItem>.from(_items),
      _clienteReferenciaSelecionada,
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(color: _bodyColor),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: _chromeColor,
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar para pedidos',
                    onPressed: canClose ? widget.onClose : null,
                    icon: const Icon(Icons.arrow_back_outlined),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasSelection
                              ? 'Pedido ${_pedidoDisplayNumber(pedido.id)}'
                              : 'Editor de pedido',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar editor',
                    onPressed: canClose ? widget.onClose : null,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (hasSelection)
              Container(
                width: double.infinity,
                color: Color.alphaBlend(
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RawAutocomplete<Cliente>(
                      textEditingController: _customerController,
                      focusNode: _customerFocusNode,
                      displayStringForOption: _formatClienteLabel,
                      optionsBuilder: (textEditingValue) {
                        final query = _normalizeSearch(textEditingValue.text);
                        if (query.isEmpty) {
                          return _clientes.take(25);
                        }

                        final filtered = _clientes.where((cliente) {
                          final label = _normalizeSearch(
                            _formatClienteLabel(cliente),
                          );
                          final nome = _normalizeSearch(cliente.nome);
                          final documento = _normalizeSearch(cliente.documento);
                          return label.contains(query) ||
                              nome.contains(query) ||
                              documento.contains(query);
                        });
                        return filtered.take(25);
                      },
                      onSelected: (cliente) {
                        _selectCustomerById(cliente.id);
                      },
                      fieldViewBuilder:
                          (
                            context,
                            textEditingController,
                            focusNode,
                            onFieldSubmitted,
                          ) {
                            return TextField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              enabled:
                                  !widget.saving &&
                                  !_loadingClientes &&
                                  !_customerReadDenied,
                              decoration:
                                  _inputDecoration(label: 'Cliente').copyWith(
                                    hintText: 'Digite para buscar e selecione da lista',
                                    helperText: _customerReadDenied
                                        ? 'Sem permissão para listar clientes neste perfil.'
                                        : null,
                                    errorText: _customerInputError,
                                    suffixIcon: IconButton(
                                      tooltip: 'Limpar cliente',
                                      onPressed:
                                          widget.saving ||
                                              _loadingClientes ||
                                              _customerReadDenied
                                          ? null
                                          : () {
                                              _selectCustomerById('');
                                            },
                                      icon: const Icon(Icons.clear),
                                    ),
                                  ),
                              onSubmitted: (_) {
                                final typed = textEditingController.text.trim();
                                if (typed.isEmpty) {
                                  _selectCustomerById('');
                                  return;
                                }
                                final matched = _findClienteByTypedText(typed);
                                if (matched != null) {
                                  _selectCustomerById(matched.id);
                                  return;
                                }
                                setState(() {
                                  _customerInputError = 'Selecione um cliente existente da lista.';
                                });
                              },
                              onChanged: (value) {
                                if (_customerInputError != null) {
                                  setState(() {
                                    _customerInputError = null;
                                  });
                                }

                                final selected = _findClienteById(
                                  _clienteReferenciaSelecionada?.id ?? '',
                                );
                                if (selected == null) {
                                  return;
                                }

                                final selectedLabel = _normalizeSearch(
                                  _formatClienteLabel(selected),
                                );
                                if (_normalizeSearch(value) != selectedLabel) {
                                  setState(() {
                                    _clienteReferenciaSelecionada = null;
                                  });
                                }
                              },
                            );
                          },
                      optionsViewBuilder: (context, onSelected, options) {
                        final optionList = options.toList(growable: false);
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 680,
                                maxHeight: 240,
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: optionList.length,
                                itemBuilder: (context, index) {
                                  final cliente = optionList[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(cliente.nome),
                                    subtitle: Text(
                                      [
                                        if (cliente.documento.trim().isNotEmpty)
                                          cliente.documento.trim(),
                                        if (cliente.estado.trim().isNotEmpty)
                                          cliente.estado.trim().toUpperCase(),
                                      ].join(' · '),
                                    ),
                                    onTap: () => onSelected(cliente),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (_loadingClientes) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                  ],
                ),
              ),
            Container(
              width: double.infinity,
              color: _bodyColor,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: widget.loadingProducts
                  ? const Center(child: CircularProgressIndicator())
                  : !hasSelection
                  ? Text(
                      'Este pedido não está mais disponível. Volte para a lista e selecione outro.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: widget.maxBodyHeight,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocusNode,
                                    enabled: !widget.saving,
                                    textInputAction: TextInputAction.search,
                                    onChanged: (value) {
                                      setState(() {
                                        _searchQuery = value;
                                      });
                                    },
                                    onSubmitted: (_) {
                                      if (!widget.saving) {
                                        _openSearchResultsModal(searchResults);
                                      }
                                    },
                                    decoration:
                                        _inputDecoration(
                                          label: 'Pesquisar produto (descrição, código, marca, NCM)',
                                        ).copyWith(
                                          prefixIcon: const Icon(Icons.search),
                                          suffixIcon: IconButton(
                                            tooltip: 'Abrir busca completa',
                                            onPressed: widget.saving
                                                ? null
                                                : () => _openSearchResultsModal(
                                                    searchResults,
                                                  ),
                                            icon: const Icon(
                                              Icons.manage_search_outlined,
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 110,
                                  child: TextField(
                                    controller: _quantityController,
                                    enabled: !widget.saving,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(5),
                                    ],
                                    decoration: _inputDecoration(label: 'Qtd'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.icon(
                                  onPressed:
                                      visibleResults.isEmpty || widget.saving
                                      ? null
                                      : () => _addProduct(visibleResults.first),
                                  icon: const Icon(
                                    Icons.add_shopping_cart_outlined,
                                  ),
                                  label: const Text('Adicionar'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              !hasQuery
                                  ? 'Digite na busca para listar produtos.'
                                  : visibleResults.isEmpty
                                  ? 'Nenhum item compatível com essa busca.'
                                  : 'Resultados: ${searchResults.length} (exibindo ${visibleResults.length}).',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            if (widget.products.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: const Text(
                                  'Nenhum produto ativo disponível para este tenant.',
                                ),
                              )
                            else if (visibleResults.isNotEmpty)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 280,
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: visibleResults.length,
                                  separatorBuilder: (_, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final product = visibleResults[index];
                                    final displayCode = _resolveCommercialCode(
                                      product,
                                    );
                                    return Material(
                                      type: MaterialType.transparency,
                                      child: ListTile(
                                        dense: true,
                                        onTap: widget.saving
                                            ? null
                                            : () => _addProduct(product),
                                        title: Text(product.descricao),
                                        subtitle: Text(
                                          '${displayCode.isEmpty ? '-' : displayCode} · ${product.marca?.trim().isEmpty ?? true ? '-' : product.marca} · NCM ${product.ncm?.trim().isEmpty ?? true ? '-' : product.ncm} · R\$ ${_formatMoneyBr(product.valorBruto ?? 0)}',
                                        ),
                                        trailing: IconButton.filledTonal(
                                          tooltip: 'Adicionar ao pedido',
                                          onPressed: widget.saving
                                              ? null
                                              : () => _addProduct(product),
                                          icon: const Icon(Icons.add),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            if (hasMoreResults) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: widget.saving
                                      ? null
                                      : () => _openSearchResultsModal(
                                          searchResults,
                                        ),
                                  icon: const Icon(Icons.open_in_new),
                                  label: Text(
                                    'Ver todos os resultados (${searchResults.length})',
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (_items.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: const Text('Nenhum item adicionado.'),
                              )
                            else
                              Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      10,
                                      8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 54),
                                        Expanded(
                                          child: Table(
                                            columnWidths: itemTableColumnWidths,
                                            children: [
                                              TableRow(
                                                children: [
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Text(
                                                      'Produto',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelMedium,
                                                    ),
                                                  ),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: Text(
                                                      'Qtd',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelMedium,
                                                    ),
                                                  ),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: Text(
                                                      'Preco',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelMedium,
                                                    ),
                                                  ),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: Text(
                                                      'Total',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelMedium,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 36),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 320,
                                    ),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: _items.length,
                                      separatorBuilder: (_, index) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final item = _items[index];
                                        final product =
                                            productsById[item.productId];
                                        final snapshot = item.taxSnapshot;
                                        final displayCode =
                                            _resolveItemDisplayCode(
                                              item,
                                              product,
                                            );
                                        final ipi =
                                            snapshot?.aliquotaIpiPercent ??
                                            product?.aliquotaIpiBase;
                                        final ncm =
                                            (snapshot?.ncm ?? item.ncm ?? '')
                                                .trim();
                                        final cest = (snapshot?.cest ?? '')
                                            .trim();
                                        final ipiText = ipi == null
                                            ? 'IPI -'
                                            : 'IPI ${_formatPercent(ipi)}';
                                        final fiscalMetaText = [
                                          if (ncm.isNotEmpty) 'NCM $ncm',
                                          if (cest.isNotEmpty) 'CEST $cest',
                                        ].join(' · ');
                                        final discountSummary =
                                            _formatPointDiscountSummary(
                                              item.appliedDiscountPercents,
                                            );
                                        final policyFields =
                                          _orderDiscountPolicy.fields;
                                        final maxDiscountSlots =
                                          policyFields.length;
                                        final activeDiscountSlots =
                                          item
                                            .appliedDiscountPercents
                                            .length;
                                        final canAddDiscountSlot =
                                          maxDiscountSlots > 0 &&
                                          activeDiscountSlots <
                                            maxDiscountSlots;
                                        final inlineDiscountControllers =
                                          activeDiscountSlots > 0
                                          ? _ensureDiscountControllersForItem(
                                            item,
                                            activeDiscountSlots,
                                            )
                                          : const <TextEditingController>[];

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              _buildItemThumbnail(
                                                product,
                                                item.productName,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Table(
                                                  columnWidths:
                                                      itemTableColumnWidths,
                                                  defaultVerticalAlignment:
                                                      TableCellVerticalAlignment
                                                          .middle,
                                                  children: [
                                                    TableRow(
                                                      children: [
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                right: 8,
                                                              ),
                                                          child: Text(
                                                            '$displayCode · ${item.productName}',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        Align(
                                                          alignment: Alignment
                                                              .centerRight,
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              IconButton(
                                                                tooltip: 'Diminuir quantidade',
                                                                onPressed:
                                                                    widget
                                                                        .saving
                                                                    ? null
                                                                    : () => _decrementItemQuantity(
                                                                        index,
                                                                      ),
                                                                icon: const Icon(
                                                                  Icons
                                                                      .remove_circle_outline,
                                                                  size: 18,
                                                                ),
                                                                visualDensity:
                                                                    VisualDensity
                                                                        .compact,
                                                                constraints:
                                                                    const BoxConstraints(
                                                                      minWidth:
                                                                          26,
                                                                      minHeight:
                                                                          26,
                                                                    ),
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              SizedBox(
                                                                width: 52,
                                                                child: TextFormField(
                                                                  key: ValueKey(
                                                                    'qtd_${item.id}_${_formatQuantity(item.quantity)}',
                                                                  ),
                                                                  initialValue:
                                                                      _formatQuantity(
                                                                        item.quantity,
                                                                      ),
                                                                  enabled: !widget
                                                                      .saving,
                                                                  keyboardType:
                                                                      TextInputType
                                                                          .number,
                                                                  inputFormatters: [
                                                                    FilteringTextInputFormatter
                                                                        .digitsOnly,
                                                                    LengthLimitingTextInputFormatter(
                                                                      5,
                                                                    ),
                                                                  ],
                                                                  textAlign:
                                                                      TextAlign
                                                                          .center,
                                                                  decoration: const InputDecoration(
                                                                    isDense:
                                                                        true,
                                                                    contentPadding:
                                                                        EdgeInsets.symmetric(
                                                                          horizontal:
                                                                              6,
                                                                          vertical:
                                                                              6,
                                                                        ),
                                                                    border:
                                                                        OutlineInputBorder(),
                                                                  ),
                                                                  onFieldSubmitted: (value) {
                                                                    final parsed =
                                                                        _readIntegerQuantity(
                                                                          value,
                                                                        );
                                                                    _setItemQuantity(
                                                                      index,
                                                                      parsed,
                                                                    );
                                                                  },
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              IconButton(
                                                                tooltip: 'Aumentar quantidade',
                                                                onPressed:
                                                                    widget
                                                                        .saving
                                                                    ? null
                                                                    : () => _incrementItemQuantity(
                                                                        index,
                                                                      ),
                                                                icon: const Icon(
                                                                  Icons
                                                                      .add_circle_outline,
                                                                  size: 18,
                                                                ),
                                                                visualDensity:
                                                                    VisualDensity
                                                                        .compact,
                                                                constraints:
                                                                    const BoxConstraints(
                                                                      minWidth:
                                                                          26,
                                                                      minHeight:
                                                                          26,
                                                                    ),
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        Align(
                                                          alignment: Alignment
                                                              .centerRight,
                                                          child: Text(
                                                            _formatMoney(
                                                              item.unitPrice,
                                                            ),
                                                          ),
                                                        ),
                                                        Align(
                                                          alignment: Alignment
                                                              .centerRight,
                                                          child: Text(
                                                            _formatMoney(
                                                              item.totalPrice,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    TableRow(
                                                      children: [
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 3,
                                                              ),
                                                          child: Text(
                                                            fiscalMetaText
                                                                    .isEmpty
                                                                ? '$ipiText · ICMS-ST por regra fiscal'
                                                                : '$ipiText · $fiscalMetaText · ICMS-ST por regra fiscal',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .textTheme
                                                                    .bodySmall,
                                                          ),
                                                        ),
                                                        const SizedBox.shrink(),
                                                        const SizedBox.shrink(),
                                                        const SizedBox.shrink(),
                                                      ],
                                                    ),
                                                    TableRow(
                                                      children: [
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 2,
                                                              ),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                discountSummary,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .textTheme
                                                                        .bodySmall,
                                                              ),
                                                              const SizedBox(
                                                                height: 4,
                                                              ),
                                                              Wrap(
                                                                spacing: 8,
                                                                runSpacing: 6,
                                                                crossAxisAlignment:
                                                                    WrapCrossAlignment
                                                                        .center,
                                                                children: [
                                                                  if (activeDiscountSlots ==
                                                                      0)
                                                                    TextButton.icon(
                                                                      onPressed:
                                                                          widget.saving
                                                                          ? null
                                                                          : () =>
                                                                                _addPointDiscountField(
                                                                                  index,
                                                                                ),
                                                                      icon: const Icon(
                                                                        Icons
                                                                            .percent_outlined,
                                                                        size: 16,
                                                                      ),
                                                                      label: const Text(
                                                                        'Adicionar desconto',
                                                                      ),
                                                                      style: TextButton.styleFrom(
                                                                        padding:
                                                                            const EdgeInsets.symmetric(
                                                                              horizontal:
                                                                                  4,
                                                                              vertical:
                                                                                  0,
                                                                            ),
                                                                        minimumSize:
                                                                            const Size(
                                                                              0,
                                                                              30,
                                                                            ),
                                                                        tapTargetSize:
                                                                            MaterialTapTargetSize
                                                                                .shrinkWrap,
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                              if (activeDiscountSlots >
                                                                  0) ...[
                                                                const SizedBox(
                                                                  height: 6,
                                                                ),
                                                                Wrap(
                                                                  spacing: 8,
                                                                  runSpacing: 8,
                                                                  crossAxisAlignment:
                                                                      WrapCrossAlignment
                                                                          .center,
                                                                  children: [
                                                                    for (
                                                                      var i = 0;
                                                                      i <
                                                                          activeDiscountSlots;
                                                                      i++
                                                                    )
                                                                      Container(
                                                                        padding:
                                                                            const EdgeInsets.symmetric(
                                                                              horizontal:
                                                                                  6,
                                                                              vertical:
                                                                                  4,
                                                                            ),
                                                                        decoration: BoxDecoration(
                                                                          borderRadius:
                                                                              BorderRadius.circular(
                                                                                10,
                                                                              ),
                                                                          color: Theme.of(
                                                                                context,
                                                                              )
                                                                              .colorScheme
                                                                              .surfaceContainerHighest
                                                                              .withValues(
                                                                                alpha:
                                                                                    0.35,
                                                                              ),
                                                                          border: Border.all(
                                                                            color: Theme.of(context)
                                                                                .colorScheme
                                                                                .outlineVariant
                                                                                .withValues(
                                                                                  alpha:
                                                                                      0.55,
                                                                                ),
                                                                          ),
                                                                        ),
                                                                        child: Row(
                                                                          mainAxisSize:
                                                                              MainAxisSize
                                                                                  .min,
                                                                          children: [
                                                                            SizedBox(
                                                                              width:
                                                                                  96,
                                                                              child: TextField(
                                                                                controller:
                                                                                    inlineDiscountControllers[i],
                                                                                enabled:
                                                                                    !widget.saving,
                                                                                keyboardType: const TextInputType.numberWithOptions(
                                                                                  decimal:
                                                                                      true,
                                                                                ),
                                                                                decoration: InputDecoration(
                                                                                  labelText: i < policyFields.length
                                                                                      ? policyFields[i].label
                                                                                      : 'Desc ${i + 1}',
                                                                                  suffixText:
                                                                                      '%',
                                                                                  isDense:
                                                                                      true,
                                                                                  contentPadding:
                                                                                      const EdgeInsets.symmetric(
                                                                                        horizontal:
                                                                                            8,
                                                                                        vertical:
                                                                                            8,
                                                                                      ),
                                                                                  border:
                                                                                      const OutlineInputBorder(),
                                                                                ),
                                                                                onSubmitted:
                                                                                    (_) =>
                                                                                        _applyInlineItemDiscounts(
                                                                                          index,
                                                                                          showErrors:
                                                                                              true,
                                                                                        ),
                                                                                onChanged:
                                                                                    (_) =>
                                                                                        _applyInlineItemDiscounts(
                                                                                          index,
                                                                                          showErrors:
                                                                                              false,
                                                                                        ),
                                                                              ),
                                                                            ),
                                                                            const SizedBox(
                                                                              width:
                                                                                  4,
                                                                            ),
                                                                            IconButton(
                                                                              tooltip:
                                                                                  'Remover este desconto',
                                                                              onPressed:
                                                                                  widget.saving
                                                                                  ? null
                                                                                  : () =>
                                                                                        _removeInlineItemDiscountField(
                                                                                          index,
                                                                                          i,
                                                                                        ),
                                                                              icon: const Icon(
                                                                                Icons
                                                                                    .close,
                                                                                size:
                                                                                    16,
                                                                              ),
                                                                              visualDensity:
                                                                                  VisualDensity
                                                                                      .compact,
                                                                              constraints:
                                                                                  const BoxConstraints(
                                                                                    minWidth:
                                                                                        24,
                                                                                    minHeight:
                                                                                        24,
                                                                                  ),
                                                                              padding:
                                                                                  EdgeInsets
                                                                                      .zero,
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                    if (canAddDiscountSlot)
                                                                      Padding(
                                                                        padding:
                                                                            const EdgeInsets.only(
                                                                              top:
                                                                                  2,
                                                                            ),
                                                                        child: FloatingActionButton.small(
                                                                          heroTag:
                                                                              'item_discount_fab_${item.id}_$activeDiscountSlots',
                                                                          tooltip:
                                                                              'Adicionar próximo campo',
                                                                          onPressed:
                                                                              widget.saving
                                                                              ? null
                                                                              : () =>
                                                                                    _addPointDiscountField(
                                                                                      index,
                                                                                    ),
                                                                          child:
                                                                              const Icon(
                                                                                Icons
                                                                                    .add,
                                                                                size:
                                                                                    18,
                                                                              ),
                                                                        ),
                                                                      ),
                                                                  ],
                                                                ),
                                                              ],
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox.shrink(),
                                                        const SizedBox.shrink(),
                                                        const SizedBox.shrink(),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Column(
                                                children: [
                                                  IconButton(
                                                    tooltip: 'Remover item',
                                                    onPressed: widget.saving
                                                        ? null
                                                        : () {
                                                            setState(() {
                                                              _disposeDiscountControllersForItem(
                                                                item.id,
                                                              );
                                                              _items.removeAt(
                                                                index,
                                                              );
                                                            });
                                                          },
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
                              child: Text(
                                'Total de itens: ${_items.length} · Total com impostos: R\$ ${_formatMoney(_totalGross())}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            Container(
              width: double.infinity,
              color: _chromeColor,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: canClose ? widget.onClose : null,
                    child: const Text('Fechar'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: hasSelection && !widget.saving ? _save : null,
                    child: Text(
                      widget.saving ? 'Salvando...' : 'Salvar rascunho',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComputedPedidoItemValues {
  const _ComputedPedidoItemValues({
    required this.unitPrice,
    required this.totalPrice,
    required this.taxSnapshot,
    required this.usedFallback,
  });

  final double unitPrice;
  final double totalPrice;
  final PedidoItemTaxSnapshot taxSnapshot;
  final bool usedFallback;
}
