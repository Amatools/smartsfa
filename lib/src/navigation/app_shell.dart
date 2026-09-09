import 'package:flutter/material.dart';

import '../core/data/in_memory/demo_workspace.dart';
import '../core/models/app_identity.dart';
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
  int _selectedIndex = 0;
  late final DemoWorkspace _workspace;

  @override
  void initState() {
    super.initState();
    _workspace = DemoWorkspace.seeded(widget.identity);
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
          repository: _workspace.clientes,
        ),
      ),
      _ShellItem(
        label: 'Produtos',
        icon: Icons.inventory_2_outlined,
        builder: (context, identity) => ProdutosPage(
          identity: identity,
          repository: _workspace.produtos,
        ),
      ),
      _ShellItem(
        label: 'Pedidos',
        icon: Icons.receipt_long_outlined,
        builder: (context, identity) => PedidosPage(
          identity: identity,
          repository: _workspace.pedidos,
        ),
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
          builder: (context, identity) => TenantAdminPage(
            identity: identity,
          ),
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
            subtitle: 'Visao global do SaaS para onboarding, governanca e suporte.',
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
    final selected = items[_selectedIndex.clamp(0, items.length - 1)];
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
                    selectedIndex: _selectedIndex,
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
                  Expanded(
                    child: selected.builder(context, widget.identity),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(
                    child: selected.builder(context, widget.identity),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
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
      ('Modo', identity.isMock ? 'Mock auth' : 'Firebase auth'),
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
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  entry.$2,
                                  textAlign: TextAlign.end,
                                ),
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
            ...lines.map((line) => Padding(
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
                )),
          ],
        ),
      ),
    );
  }
}
