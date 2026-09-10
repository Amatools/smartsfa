import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/data/firestore/firestore_cliente_pre_cadastro_repository.dart';
import '../core/data/firestore/firestore_cliente_repository.dart';
import '../core/data/firestore/firestore_mock_seed_service.dart';
import '../core/data/firestore/firestore_pedido_repository.dart';
import '../core/data/firestore/firestore_produto_repository.dart';
import '../core/data/in_memory/demo_workspace.dart';
import '../core/diagnostics/app_diagnostics.dart';
import '../core/models/app_identity.dart';
import '../core/models/cliente.dart';
import '../core/models/cliente_pre_cadastro.dart';
import '../core/repositories/cliente_pre_cadastro_repository.dart';
import '../core/services/offline_sync_queue.dart';
import '../core/repositories/cliente_repository.dart';
import '../core/repositories/pedido_repository.dart';
import '../core/repositories/produto_repository.dart';
import '../features/auth/presentation/pages/account_settings_page.dart';
import '../features/clientes/presentation/pages/clientes_page.dart';
import '../features/notificacoes/presentation/pages/notificacoes_page.dart';
import '../features/pedidos/presentation/pages/pedidos_page.dart';
import '../features/produtos/presentation/pages/produtos_page.dart';
import '../features/tenant/presentation/pages/tenant_admin_page.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({
    super.key,
    required this.identity,
    required this.onSignOut,
    this.onAccessUpdated,
    this.onSwitchProfile,
  });

  final AppIdentity identity;
  final VoidCallback onSignOut;
  final VoidCallback? onAccessUpdated;
  final VoidCallback? onSwitchProfile;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  static const bool _enableFirestoreMockSeed = bool.fromEnvironment(
    'SEED_FIRESTORE_MOCKS',
    defaultValue: false,
  );

  int _selectedIndex = 0;
  DemoWorkspace? _workspace;
  late final ClienteRepository _clienteRepository;
  late final ClientePreCadastroRepository _preCadastroRepository;
  late final ProdutoRepository _produtoRepository;
  late final PedidoRepository _pedidoRepository;
  final Connectivity _connectivity = Connectivity();
  bool _syncInProgress = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        return;
      }

      _syncOfflineQueueIfOnline();
    });
    _initializeRepositories();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeRepositories() async {
    final shouldUseLocalFallback = widget.identity.isMock ||
        await _isOffline();

    if (shouldUseLocalFallback) {
      _workspace = DemoWorkspace.seeded(widget.identity);
      _clienteRepository = _workspace!.clientes;
      _preCadastroRepository = _workspace!.preCadastros;
      _produtoRepository = _workspace!.produtos;
      _pedidoRepository = _workspace!.pedidos;
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final firestore = FirebaseFirestore.instance;
    _clienteRepository = FirestoreClienteRepository(firestore);
    _preCadastroRepository = FirestoreClientePreCadastroRepository(firestore);
    _produtoRepository = FirestoreProdutoRepository(firestore);
    _pedidoRepository = FirestorePedidoRepository(firestore);
    _seedFirestoreMocksIfNeeded();
    _syncOfflineQueueIfOnline();
  }

  Future<bool> _isOffline() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      return connectivity.contains(ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<void> _syncOfflineQueueIfOnline() async {
    if (_syncInProgress) {
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    final hasConnection = connectivity.contains(ConnectivityResult.none) == false;
    if (!hasConnection) {
      return;
    }

    _syncInProgress = true;
    try {
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
          try {
            final payload = item.payloadMap;
            final entity = ClientePreCadastro.fromMap(payload);
            if (entity.tenantId == widget.identity.tenantId ||
                widget.identity.isPersonalWorkspace) {
              await _preCadastroRepository.save(entity);
              await OfflineSyncQueue.markSynced(item.id);
            }
          } catch (error, stackTrace) {
            AppDiagnostics.log(
              tag: 'app_shell.sync.pre_cadastro',
              message: 'Falha ao sincronizar pré-cadastro em segundo plano.',
              error: error,
              stackTrace: stackTrace,
            );
            // keep pending until the next sync pass.
          }
        } else if (item.type == 'cliente') {
          try {
            final payload = item.payloadMap;
            final entity = Cliente.fromMap(payload);
            if (entity.tenantId == widget.identity.tenantId ||
                widget.identity.isPersonalWorkspace) {
              await _clienteRepository.save(entity);
              await OfflineSyncQueue.markSynced(item.id);
            }
          } catch (error, stackTrace) {
            AppDiagnostics.log(
              tag: 'app_shell.sync.cliente',
              message: 'Falha ao sincronizar cliente em segundo plano.',
              error: error,
              stackTrace: stackTrace,
            );
            // keep pending until the next sync pass.
          }
        }
      }

      // Also retry any pending local deletes (tombstones): a delete that
      // failed remotely earlier (offline, transient error, permission
      // mismatch) must keep being retried in the background too, not only
      // when the user manually presses "Sincronizar agora" on the Clientes
      // screen — otherwise it stays excluded locally forever while still
      // existing on the server.
      for (final tombstone in pendingDeletesPreview) {
        final type = tombstone['type']?.toString();
        final id = tombstone['id']?.toString() ?? '';
        final tenantId = tombstone['tenantId']?.toString() ?? '';
        if (id.isEmpty) {
          continue;
        }
        if (tenantId != widget.identity.tenantId &&
            !widget.identity.isPersonalWorkspace) {
          continue;
        }

        try {
          if (type == 'cliente_pre_cadastro') {
            await _preCadastroRepository.delete(tenantId: tenantId, id: id);
            await OfflineSyncQueue.clearTombstone(id);
          } else if (type == 'cliente') {
            await _clienteRepository.delete(tenantId: tenantId, id: id);
            await OfflineSyncQueue.clearTombstone(id);
          }
        } catch (error, stackTrace) {
          AppDiagnostics.log(
            tag: 'app_shell.sync.delete_retry',
            message: 'Falha ao confirmar exclusão remota de $type/$id em segundo plano.',
            error: error,
            stackTrace: stackTrace,
          );
          // keep the tombstone until the next sync pass.
        }
      }
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> _seedFirestoreMocksIfNeeded() async {
    if (!kDebugMode || !_enableFirestoreMockSeed) {
      return;
    }

    final role = widget.identity.role.trim().toLowerCase();
    if (role != 'owner' && role != 'platform_admin') {
      return;
    }

    final actorUid = FirebaseAuth.instance.currentUser?.uid;
    if (actorUid == null || actorUid.isEmpty) {
      return;
    }

    try {
      final seedService = FirestoreMockSeedService(FirebaseFirestore.instance);
      final result = await seedService.seedIfEmpty(
        identity: widget.identity,
        actorUid: actorUid,
      );

      if (!mounted || !result.anySeeded) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Mock no banco carregado: ${result.seededClientes} clientes, '
              '${result.seededProdutos} produtos, ${result.seededPedidos} pedidos.',
            ),
          ),
        );
      });
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'app_shell.seed_mocks',
        message: 'Falha ao carregar dados de exemplo (mock) no Firestore.',
        error: error,
        stackTrace: stackTrace,
      );
      // Seeding is best-effort for dev bootstrap only.
    }
  }

  List<_ShellItem> _buildItems(String role) {
    final normalizedRole = role.toLowerCase().replaceAll(' ', '_');
    final items = <_ShellItem>[
      _ShellItem(
        label: 'Dashboard',
        icon: Icons.space_dashboard_outlined,
        builder: (context, identity) => _DashboardPage(identity: identity),
      ),
      _ShellItem(
        label: 'Clientes',
        icon: Icons.people_outline,
        builder: (context, identity) => ClientesPage(
          identity: identity,
          repository: _clienteRepository,
          preCadastroRepository: _preCadastroRepository,
        ),
      ),
      _ShellItem(
        label: 'Produtos',
        icon: Icons.inventory_2_outlined,
        builder: (context, identity) =>
            ProdutosPage(identity: identity, repository: _produtoRepository),
      ),
      _ShellItem(
        label: 'Pedidos',
        icon: Icons.receipt_long_outlined,
        builder: (context, identity) =>
            PedidosPage(identity: identity, repository: _pedidoRepository),
      ),
      _ShellItem(
        label: 'Avisos',
        icon: Icons.notifications_none,
        builder: (context, identity) => NotificacoesPage(
          identity: identity,
          onAccessUpdated: widget.onAccessUpdated,
        ),
      ),
      _ShellItem(
        label: 'Conta',
        icon: Icons.manage_accounts_outlined,
        builder: (context, identity) => AccountSettingsPage(
          identity: identity,
          onAccessUpdated: widget.onAccessUpdated,
        ),
      ),
    ];

    if (normalizedRole == 'platform_admin' ||
        normalizedRole == 'owner' ||
        normalizedRole == 'gerente' ||
        normalizedRole == 'representante') {
      items.add(
        _ShellItem(
          label: 'Tenant',
          icon: Icons.business_outlined,
          builder: (context, identity) => TenantAdminPage(identity: identity),
        ),
      );
    }

    if (normalizedRole == 'platform_admin') {
      items.add(
        _ShellItem(
          label: 'Plataforma',
          icon: Icons.admin_panel_settings_outlined,
          builder: (context, identity) => _ModulePage(
            title: 'Plataforma',
            subtitle:
                'Visao global do SaaS para onboarding, governanca e suporte.',
            bullets: const [
              'Gestao de tenants',
              'Ambientes e recursos',
              'Observabilidade e suporte',
            ],
          ),
        ),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(widget.identity.role);
    final safeIndex = _selectedIndex.clamp(0, items.length - 1);
    final selected = items[safeIndex];

    if (safeIndex != _selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedIndex = safeIndex;
        });
      });
    }

    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: Text(selected.label),
        actions: [
          if (widget.onSwitchProfile != null)
            IconButton(
              onPressed: widget.onSwitchProfile,
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Trocar perfil',
            ),
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
          ),
        ],
      ),
      body: SafeArea(
        child: isWide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: safeIndex,
                    onDestinationSelected: (index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    labelType: NavigationRailLabelType.all,
                    destinations: items
                        .map(
                          (item) => NavigationRailDestination(
                            icon: Icon(item.icon),
                            label: Text(item.label),
                          ),
                        )
                        .toList(),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: selected.builder(context, widget.identity)),
                ],
              )
            : Column(
                children: [
                  Expanded(child: selected.builder(context, widget.identity)),
                ],
              ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              destinations: items
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _ShellItem {
  const _ShellItem({
    required this.label,
    required this.icon,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final Widget Function(BuildContext context, AppIdentity identity) builder;
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({required this.identity});

  final AppIdentity identity;

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('Tenant', identity.tenantName),
      ('Usuario', identity.userLabel),
      ('Perfil', identity.role),
      (
        'Conexao',
        identity.isMock ? 'Local mock / fallback' : 'Firebase autenticado',
      ),
    ];

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Painel inicial',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Shell base do Smart SFA preparada para multi-tenant, navegacao por perfil e evolucao modular.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Column(
              children: cards
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  entry.$1,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Flexible(
                                child: Text(entry.$2, textAlign: TextAlign.end),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            const _StageCard(
              title: 'Proxima entrega',
              lines: [
                'Refatorar dados para tenants e memberships',
                'Criar navegacao funcional por modulo',
                'Mostrar listas reais de clientes, produtos e pedidos',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModulePage extends StatelessWidget {
  const _ModulePage({
    required this.title,
    required this.subtitle,
    required this.bullets,
  });

  final String title;
  final String subtitle;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            _StageCard(title: 'Escopo inicial', lines: bullets),
          ],
        ),
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle, size: 8),
                    ),
                    Expanded(child: Text(line)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
