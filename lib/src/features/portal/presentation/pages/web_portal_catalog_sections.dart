part of 'web_portal_page.dart';

class _PricingCatalogSection extends StatelessWidget {
  const _PricingCatalogSection({
    required this.activeTenant,
    this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final userLabel = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final identity = AppIdentity(
      tenantId: activeTenant.tenantId,
      userLabel: (userLabel == null || userLabel.isEmpty)
          ? 'Portal'
          : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace:
          activeTenant.workspaceType == 'seller_solo_workspace',
    );

    return TabelasPrecoPage(
      identity: identity,
      activeTenant: activeTenant,
      selectedRepresentedCompanyId: selectedRepresentedCompanyId,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
      repository: FirestoreTabelaPrecoRepository(FirebaseFirestore.instance),
    );
  }
}

class _SimpleSectionPage extends StatelessWidget {
  const _SimpleSectionPage._({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  factory _SimpleSectionPage.politicas({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
  }) {
    return _SimpleSectionPage._(
      title: 'Políticas comerciais',
      subtitle: 'Limites, aprovações e travas da empresa ativa.',
      items: const [
        'Limites por perfil',
        'Aprovações fora da curva',
        'Regras por grupo de produto',
      ],
      activeTenant: activeTenant,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
    );
  }

  factory _SimpleSectionPage.erp({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
  }) {
    return _SimpleSectionPage._(
      title: 'ERP e integrações',
      subtitle: 'Conectores e status da empresa ativa.',
      items: const [
        'Conector por tenant',
        'Mapeamento de pedidos e cadastros',
        'Fila de erros e reprocessamento',
      ],
      activeTenant: activeTenant,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
    );
  }

  factory _SimpleSectionPage.convites({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
  }) {
    return _SimpleSectionPage._(
      title: 'Convites e memberships',
      subtitle: 'Entrada de novos usuários para o tenant ativo.',
      items: const [
        'Convites pendentes',
        'Revisão de memberships',
        'Aprovação e revogação',
      ],
      activeTenant: activeTenant,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
    );
  }

  factory _SimpleSectionPage.auditoria({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
  }) {
    return _SimpleSectionPage._(
      title: 'Auditoria',
      subtitle: 'Trilha do tenant ativo.',
      items: const [
        'Alterações sensíveis',
        'Eventos por usuário',
        'Suporte e rastreabilidade',
      ],
      activeTenant: activeTenant,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
    );
  }

  final String title;
  final String subtitle;
  final List<String> items;
  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final representedName = activeRepresentedCompanyName?.trim() ?? '';
    final representedSuffix = representedName.isEmpty
        ? ' Representada ativa: não selecionada.'
        : ' Representada ativa: $representedName.';

    return _SimpleCardSection(
      title: title,
      subtitle:
          '$subtitle Tenant ativo: ${activeTenant.tenantName}.$representedSuffix',
      items: items,
    );
  }
}

class _ProductsCatalogSection extends StatelessWidget {
  const _ProductsCatalogSection({
    required this.activeTenant,
    this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final userLabel = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final identity = AppIdentity(
      tenantId: activeTenant.tenantId,
      userLabel: (userLabel == null || userLabel.isEmpty)
          ? 'Portal'
          : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace:
          activeTenant.workspaceType == 'seller_solo_workspace',
    );

    return ProdutosPage(
      identity: identity,
      repository: FirestoreProdutoRepository(FirebaseFirestore.instance),
      selectedRepresentedCompanyId: selectedRepresentedCompanyId,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
    );
  }
}

class _SimpleCardSection extends StatelessWidget {
  const _SimpleCardSection({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String title;
  final String subtitle;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(subtitle, style: textTheme.bodyLarge),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Blocos previstos', style: textTheme.titleMedium),
                const SizedBox(height: 12),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Icon(Icons.check_circle_outline, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(item)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PortalModule {
  const _PortalModule({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

class _PortalModuleCard extends StatelessWidget {
  const _PortalModuleCard({required this.module});

  final _PortalModule module;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(module.icon, size: 28),
            const SizedBox(height: 12),
            Text(module.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(module.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersSection extends StatelessWidget {
  const _OrdersSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final userLabel = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final identity = AppIdentity(
      tenantId: activeTenant.tenantId,
      userLabel: (userLabel == null || userLabel.isEmpty)
          ? 'Portal'
          : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace:
          activeTenant.workspaceType == 'seller_solo_workspace',
    );

    final representedName = (activeRepresentedCompanyName ?? '').trim();
    if (representedName.isEmpty) {
      return PedidosPage(
        identity: identity,
        repository: FirestorePedidoRepository(FirebaseFirestore.instance),
        produtoRepository: FirestoreProdutoRepository(
          FirebaseFirestore.instance,
        ),
      );
    }

    return StreamBuilder<List<Map<String, Object?>>>(
      stream: WorkspaceProfileService(FirebaseFirestore.instance)
          .watchRepresentedCompanies(activeTenant.tenantId),
      builder: (context, snapshot) {
        final representedCompanies =
            snapshot.data ?? const <Map<String, Object?>>[];

        Map<String, Object?>? selectedCompany;
        for (final company in representedCompanies) {
          final companyName = (company['nomeFantasia'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (companyName == representedName.toLowerCase()) {
            selectedCompany = company;
            break;
          }
        }

        final originCompanyId = (selectedCompany?['companyId'] ?? '')
            .toString()
            .trim();
        final originCompanyLabel = (selectedCompany?['nomeFantasia'] ?? '')
            .toString()
            .trim();
        final originCompanyUf = (selectedCompany?['uf'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

        return PedidosPage(
          identity: identity,
          repository: FirestorePedidoRepository(FirebaseFirestore.instance),
          produtoRepository: FirestoreProdutoRepository(
            FirebaseFirestore.instance,
          ),
          representedCompanyId: originCompanyId.isEmpty
              ? null
              : originCompanyId,
          originCompanyUnitId: originCompanyId.isEmpty ? null : originCompanyId,
          originCompanyUnitLabel: originCompanyLabel.isEmpty
              ? null
              : originCompanyLabel,
          originCompanyUf: originCompanyUf.isEmpty ? null : originCompanyUf,
        );
      },
    );
  }
}
