import 'package:flutter/material.dart';

import '../../core/models/app_identity.dart';
import '../../core/repositories/cliente_pre_cadastro_repository.dart';
import '../../core/repositories/cliente_repository.dart';
import '../../core/repositories/pedido_repository.dart';
import '../../core/repositories/produto_repository.dart';
import '../../features/auth/presentation/pages/account_settings_page.dart';
import '../../features/clientes/presentation/pages/clientes_page.dart';
import '../../features/notificacoes/presentation/pages/notificacoes_page.dart';
import '../../features/pedidos/presentation/pages/pedidos_page.dart';
import '../../features/produtos/presentation/pages/produtos_page.dart';
import '../../features/tenant/presentation/pages/tenant_admin_page.dart';
import '../models/app_shell_item.dart';
import '../widgets/app_shell_pages.dart';

class AppShellNavigationFactory {
  const AppShellNavigationFactory();

  List<AppShellItem> buildItems({
    required String role,
    required bool usingLocalFallback,
    required ClienteRepository clienteRepository,
    required ClientePreCadastroRepository preCadastroRepository,
    required ProdutoRepository produtoRepository,
    required PedidoRepository pedidoRepository,
    required VoidCallback? onAccessUpdated,
  }) {
    final normalizedRole = role.toLowerCase().replaceAll(' ', '_');
    final items = <AppShellItem>[
      AppShellItem(
        label: 'Dashboard',
        icon: Icons.space_dashboard_outlined,
        builder: (context, identity) => AppShellDashboardPage(
          identity: identity,
          usingLocalFallback: usingLocalFallback,
        ),
      ),
      AppShellItem(
        label: 'Clientes',
        icon: Icons.people_outline,
        builder: (context, identity) => ClientesPage(
          identity: identity,
          repository: clienteRepository,
          preCadastroRepository: preCadastroRepository,
        ),
      ),
      AppShellItem(
        label: 'Produtos',
        icon: Icons.inventory_2_outlined,
        builder: (context, identity) =>
            ProdutosPage(identity: identity, repository: produtoRepository),
      ),
      AppShellItem(
        label: 'Pedidos',
        icon: Icons.receipt_long_outlined,
        builder: (context, identity) =>
            PedidosPage(identity: identity, repository: pedidoRepository),
      ),
      AppShellItem(
        label: 'Avisos',
        icon: Icons.notifications_none,
        builder: (context, identity) => NotificacoesPage(
          identity: identity,
          onAccessUpdated: onAccessUpdated,
        ),
      ),
      AppShellItem(
        label: 'Conta',
        icon: Icons.manage_accounts_outlined,
        builder: (context, identity) => AccountSettingsPage(
          identity: identity,
          onAccessUpdated: onAccessUpdated,
        ),
      ),
    ];

    if (normalizedRole == 'platform_admin' ||
        normalizedRole == 'owner' ||
        normalizedRole == 'gerente' ||
        normalizedRole == 'representante') {
      items.add(
        AppShellItem(
          label: 'Tenant',
          icon: Icons.business_outlined,
          builder: (context, identity) => TenantAdminPage(identity: identity),
        ),
      );
    }

    if (normalizedRole == 'platform_admin') {
      items.add(
        const AppShellItem(
          label: 'Plataforma',
          icon: Icons.admin_panel_settings_outlined,
          builder: _platformPageBuilder,
        ),
      );
    }

    return items;
  }

  static Widget _platformPageBuilder(
    BuildContext context,
    AppIdentity identity,
  ) {
    return const AppShellModulePage(
      title: 'Plataforma',
      subtitle: 'Visao global do SaaS para onboarding, governanca e suporte.',
      bullets: [
        'Gestao de tenants',
        'Ambientes e recursos',
        'Observabilidade e suporte',
      ],
    );
  }
}
