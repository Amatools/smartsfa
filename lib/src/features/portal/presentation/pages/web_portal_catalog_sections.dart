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
      productRepository: FirestoreProdutoRepository(FirebaseFirestore.instance),
      basePriceRepository: FirestoreProductBasePriceRepository(
        FirebaseFirestore.instance,
      ),
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

  static Widget enterprisePoliticas({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
  }) {
    return _EnterprisePoliciesSection(
      activeTenant: activeTenant,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
    );
  }

  static Widget erp({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
  }) {
    return EnterpriseErpIntegrationSection(activeTenant: activeTenant);
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

enum _EnterprisePolicySubmenu {
  tributacoes,
  condicoesPagamento,
  descontosPontuais,
  acrescimosDescontos,
}

class _EnterprisePoliciesSection extends StatefulWidget {
  const _EnterprisePoliciesSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  State<_EnterprisePoliciesSection> createState() =>
      _EnterprisePoliciesSectionState();
}

class _EnterprisePoliciesSectionState
    extends State<_EnterprisePoliciesSection> {
  static final Map<String, _EnterprisePolicySubmenu> _submenuByTenantId =
      <String, _EnterprisePolicySubmenu>{};

  _EnterprisePolicySubmenu _activeSubmenu =
      _EnterprisePolicySubmenu.tributacoes;

  String get _tenantId => widget.activeTenant.tenantId;

  @override
  void initState() {
    super.initState();
    _activeSubmenu =
        _submenuByTenantId[_tenantId] ?? _EnterprisePolicySubmenu.tributacoes;
  }

  @override
  void didUpdateWidget(covariant _EnterprisePoliciesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTenant.tenantId != widget.activeTenant.tenantId) {
      _activeSubmenu =
          _submenuByTenantId[_tenantId] ?? _EnterprisePolicySubmenu.tributacoes;
    }
  }

  String get _representedCompanyId {
    return _enterpriseDefaultRepresentedCompanyId(widget.activeTenant);
  }

  String get _representedCompanyName {
    final name = (widget.activeRepresentedCompanyName ?? '').trim();
    if (name.isNotEmpty) {
      return name;
    }
    final tenantName = widget.activeTenant.tenantName.trim();
    return tenantName.isEmpty ? 'Empresa ativa' : tenantName;
  }

  @override
  Widget build(BuildContext context) {
    final canAccessPolicies = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );

    if (!canAccessPolicies) {
      return const _SimpleCardSection(
        title: 'Políticas comerciais',
        subtitle:
            'Acesso restrito ao owner da empresa no workspace enterprise.',
        items: [
          'Tributações',
          'Condições de pagamento',
          'Descontos pontuais',
          'Acréscimos ou descontos',
        ],
      );
    }

    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Políticas comerciais', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Configure as políticas da empresa ativa. Escopo: $_representedCompanyName.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.45),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildSubmenuChip(
                  context,
                  submenu: _EnterprisePolicySubmenu.tributacoes,
                  label: 'Tributações',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterprisePolicySubmenu.condicoesPagamento,
                  label: 'Condições de pagamento',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterprisePolicySubmenu.descontosPontuais,
                  label: 'Descontos pontuais',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterprisePolicySubmenu.acrescimosDescontos,
                  label: 'Acréscimos ou descontos',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildSubmenuContent(),
      ],
    );
  }

  Widget _buildSubmenuChip(
    BuildContext context, {
    required _EnterprisePolicySubmenu submenu,
    required String label,
  }) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      selectedColor: Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: 0.8),
      backgroundColor: Colors.white,
      selected: _activeSubmenu == submenu,
      onSelected: (_) {
        setState(() {
          _activeSubmenu = submenu;
          _submenuByTenantId[_tenantId] = submenu;
        });
      },
    );
  }

  Widget _buildSubmenuContent() {
    switch (_activeSubmenu) {
      case _EnterprisePolicySubmenu.tributacoes:
        return _TaxationSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: _representedCompanyId,
          activeRepresentedCompanyName: _representedCompanyName,
        );
      case _EnterprisePolicySubmenu.condicoesPagamento:
        return _PaymentConditionsSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: null,
          activeRepresentedCompanyName: null,
        );
      case _EnterprisePolicySubmenu.descontosPontuais:
        return _OrderDiscountPoliciesSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: null,
          activeRepresentedCompanyName: null,
        );
      case _EnterprisePolicySubmenu.acrescimosDescontos:
        return _CommercialAdjustmentsSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: null,
          activeRepresentedCompanyName: null,
        );
    }
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
