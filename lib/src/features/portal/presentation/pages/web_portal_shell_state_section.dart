part of 'web_portal_page.dart';

class _WebPortalShellState extends State<_WebPortalShell> {
  int _selectedIndex = 0;
  String? _activeTenantId;
  bool _showWorkspaceSelection = true;
  bool _upgradingWorkspace = false;
  bool _settingFavoriteRepresented = false;
  final Map<String, String?> _activeRepresentedCompanyByTenant = {};
  final Map<String, String?> _activeRepresentedCompanyNameByTenant = {};

  Future<AccountContractLock> _loadAccountContractLock(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    return AccountContractLock.fromValue(
      (doc.data()?['accountContractLock'] ?? '').toString().trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Usuário não autenticado.')),
      );
    }

    return StreamBuilder<List<TenantEntryOption>>(
      stream: TenantMembershipService(FirebaseFirestore.instance)
          .watchTenantChoicesForUser(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final tenants = snapshot.data ?? const [];
        if (tenants.isEmpty) {
          return const Scaffold(
            body: Center(
              child: Text('Nenhum tenant ativo encontrado para este usuário.'),
            ),
          );
        }

        return FutureBuilder<AccountContractLock>(
          future: _loadAccountContractLock(user.uid),
          builder: (context, lockSnapshot) {
            if (lockSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final accountContractLock =
                lockSnapshot.data ?? AccountContractLock.flexible;
            final preferredTenant = _resolvePreferredTenant(tenants);

            if (_showWorkspaceSelection || _activeTenantId == null) {
              return Scaffold(
                body: SafeArea(
                  child: _WorkspaceSelectionView(
                    identity: widget.identity,
                    tenants: tenants,
                    selectedTenantId:
                        _activeTenantId ?? preferredTenant.tenantId,
                    onSelectTenant: _enterWorkspace,
                    onSignOut: widget.onSignOut,
                  ),
                ),
              );
            }

            final activeTenant = _resolveActiveTenantOrFallback(
              tenants: tenants,
              preferredTenant: preferredTenant,
            );
            final allItems = _buildItemsForRole(
              activeTenant,
              accountContractLock,
            );
            final visibleItems = allItems
                .where((item) => !item.hideFromNavigation)
                .toList(growable: false);
            final tenantModuleItems = allItems
                .where((item) => item.tenantModule)
                .toList(growable: false);
            final representedRequired = _requiresRepresentedSelection(
              activeTenant,
            );
            final representedSelected =
                (_activeRepresentedCompanyByTenant[activeTenant.tenantId] ?? '')
                    .trim()
                    .isNotEmpty;
            final tenantSectionLocked =
                representedRequired && !representedSelected;

            final safeIndex = _selectedIndex.clamp(0, visibleItems.length - 1);
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

            final selectedItem = visibleItems[safeIndex];
            final groupedItems = _groupItems(visibleItems, activeTenant);
            final isWide = MediaQuery.sizeOf(context).width >= 1120;

            final content = selectedItem.opensTenantModuleShell
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: _TenantWorkspaceModuleArea(
                      activeTenant: activeTenant,
                      activeRepresentedCompanyName:
                          _activeRepresentedCompanyNameByTenant[activeTenant
                              .tenantId],
                      selectedRepresentedCompanyId:
                          _activeRepresentedCompanyByTenant[activeTenant
                              .tenantId],
                      tenantItems: tenantModuleItems,
                      selectedItemLabel: tenantModuleItems.isEmpty
                          ? selectedItem.label
                          : tenantModuleItems.first.label,
                      tenantSectionLocked: tenantSectionLocked,
                    ),
                  )
                : SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: selectedItem.builder(
                        activeTenant: activeTenant,
                        activeRepresentedCompanyName:
                            _activeRepresentedCompanyNameByTenant[activeTenant
                                .tenantId],
                      ),
                    ),
                  );

            return Scaffold(
              body: SafeArea(
                child: isWide
                    ? Row(
                        children: [
                          _WebPortalSidebar(
                            identity: widget.identity,
                            activeTenant: activeTenant,
                            accountContractLock: accountContractLock,
                            sections: groupedItems,
                            visibleItems: visibleItems,
                            selectedIndex: safeIndex,
                            onMenuSelected: _setSelectedIndex,
                            tenantSectionLocked: tenantSectionLocked,
                            selectedRepresentedCompanyName:
                                _activeRepresentedCompanyNameByTenant[activeTenant
                                    .tenantId],
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: Column(
                              children: [
                                _WebPortalTopBar(
                                  identity: widget.identity,
                                  activeTenant: activeTenant,
                                  accountContractLock: accountContractLock,
                                  selectedRepresentedCompanyId:
                                      _activeRepresentedCompanyByTenant[activeTenant
                                          .tenantId],
                                  selectedRepresentedCompanyName:
                                      _activeRepresentedCompanyNameByTenant[activeTenant
                                          .tenantId],
                                  onRepresentedCompanySelected:
                                      (companyId, companyName) {
                                        _setActiveRepresentedCompany(
                                          tenantId: activeTenant.tenantId,
                                          companyId: companyId,
                                          companyName: companyName,
                                        );
                                      },
                                  onToggleFavoriteRepresented:
                                      _toggleFavoriteRepresented,
                                  settingFavoriteRepresented:
                                      _settingFavoriteRepresented,
                                  onBackToWorkspaceSelection:
                                      _backToWorkspaceSelection,
                                  onSignOut: widget.onSignOut,
                                ),
                                Expanded(child: content),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _WebPortalTopBar(
                            identity: widget.identity,
                            activeTenant: activeTenant,
                            accountContractLock: accountContractLock,
                            selectedRepresentedCompanyId:
                                _activeRepresentedCompanyByTenant[activeTenant
                                    .tenantId],
                            selectedRepresentedCompanyName:
                                _activeRepresentedCompanyNameByTenant[activeTenant
                                    .tenantId],
                            onRepresentedCompanySelected:
                                (companyId, companyName) {
                                  _setActiveRepresentedCompany(
                                    tenantId: activeTenant.tenantId,
                                    companyId: companyId,
                                    companyName: companyName,
                                  );
                                },
                            onToggleFavoriteRepresented:
                                _toggleFavoriteRepresented,
                            settingFavoriteRepresented:
                                _settingFavoriteRepresented,
                            onBackToWorkspaceSelection:
                                _backToWorkspaceSelection,
                            onSignOut: widget.onSignOut,
                          ),
                          Expanded(child: content),
                          NavigationBar(
                            selectedIndex: safeIndex,
                            onDestinationSelected: (index) {
                              if (tenantSectionLocked &&
                                  visibleItems[index].section ==
                                      _PortalSection.tenant) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Selecione uma representada ativa para acessar este modulo.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              _setSelectedIndex(index);
                            },
                            destinations: visibleItems
                                .map(
                                  (item) => NavigationDestination(
                                    icon: Icon(item.icon),
                                    label: item.label,
                                    enabled:
                                        !(tenantSectionLocked &&
                                            item.section ==
                                                _PortalSection.tenant),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }

  TenantEntryOption _resolvePreferredTenant(List<TenantEntryOption> tenants) {
    final defaultTenant = tenants
        .where((tenant) => tenant.defaultTenant)
        .toList();
    return defaultTenant.isNotEmpty ? defaultTenant.first : tenants.first;
  }

  TenantEntryOption _resolveActiveTenantOrFallback({
    required List<TenantEntryOption> tenants,
    required TenantEntryOption preferredTenant,
  }) {
    final current = _activeTenantId;
    if (current != null) {
      for (final tenant in tenants) {
        if (tenant.tenantId == current) {
          return tenant;
        }
      }
    }
    return preferredTenant;
  }

  void _enterWorkspace(String tenantId) {
    setState(() {
      _activeTenantId = tenantId;
      _showWorkspaceSelection = false;
      _selectedIndex = 0;
    });
  }

  void _backToWorkspaceSelection() {
    setState(() {
      _showWorkspaceSelection = true;
      _selectedIndex = 0;
    });
  }

  void _setActiveRepresentedCompany({
    required String tenantId,
    required String? companyId,
    String? companyName,
  }) {
    setState(() {
      _activeRepresentedCompanyByTenant[tenantId] = companyId;
      _activeRepresentedCompanyNameByTenant[tenantId] = companyName;
    });
  }

  void _setSelectedIndex(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  bool _requiresRepresentedSelection(TenantEntryOption tenant) {
    return tenant.workspaceType == 'seller_solo_workspace' ||
        tenant.workspaceType == 'rep_workspace';
  }

  Future<void> _toggleFavoriteRepresented({
    required TenantEntryOption activeTenant,
    required String? selectedRepresentedCompanyId,
    required String? favoriteRepresentedCompanyId,
  }) async {
    final selectedId = (selectedRepresentedCompanyId ?? '').trim();
    if (selectedId.isEmpty) {
      return;
    }

    final isFavorite = favoriteRepresentedCompanyId == selectedId;
    if (isFavorite) {
      return;
    }

    setState(() {
      _settingFavoriteRepresented = true;
    });

    try {
      await WorkspaceProfileService(FirebaseFirestore.instance)
          .setFavoriteRepresentedCompany(
            tenantId: activeTenant.tenantId,
            companyId: selectedId,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Representada favorita atualizada.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao favoritar representada: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _settingFavoriteRepresented = false;
        });
      }
    }
  }

  Future<void> _openUpgradeToRepDialog(TenantEntryOption activeTenant) async {
    if (activeTenant.workspaceType != 'seller_solo_workspace') {
      return;
    }

    final nameController = TextEditingController(
      text: '${activeTenant.tenantName} Representações',
    );
    final cnpjController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upgrade para Representações'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Este upgrade muda seu plano de Individual para Representações sem criar nova conta.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Seu contexto Individual sera substituido e os dados migrados para o novo workspace.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome do novo workspace de Representações',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cnpjController,
                decoration: const InputDecoration(
                  labelText: 'CNPJ de referencia (informativo)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Fazer upgrade'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    final workspaceName = nameController.text.trim();
    if (workspaceName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do workspace.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    setState(() {
      _upgradingWorkspace = true;
    });

    try {
      final result = await SoloWorkspaceService(FirebaseFirestore.instance)
          .upgradeIndividualToRepWorkspace(
            user: user,
            workspaceName: workspaceName,
            representedCompanyDocument: cnpjController.text.trim(),
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _activeTenantId = result.targetTenantId;
        _selectedIndex = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Upgrade concluido. ${result.migratedScopedDocs + result.migratedTenantOnlyDocs} registros migrados para Representações.',
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro Firebase (${error.code}): ${error.message ?? 'falha no upgrade.'}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Falha no upgrade: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _upgradingWorkspace = false;
        });
      }
    }
  }

  List<_PortalNavItem> _buildItemsForRole(
    TenantEntryOption activeTenant,
    AccountContractLock accountContractLock,
  ) {
    final normalizedRole = activeTenant.role.trim().toLowerCase().replaceAll(
      ' ',
      '_',
    );
    final isTenantManager =
        normalizedRole == 'owner' ||
        normalizedRole == 'gerente' ||
        normalizedRole == 'platform_admin';
    final canAccessInvites =
        normalizedRole == 'owner' ||
        normalizedRole == 'gerente' ||
        normalizedRole == 'representante' ||
        normalizedRole == 'platform_admin';
    final isEnterpriseWorkspace =
        activeTenant.workspaceType == 'brand_owner_workspace';
    final supportsRepresentedCompanies =
        activeTenant.workspaceType == 'rep_workspace' ||
        activeTenant.workspaceType == 'seller_solo_workspace';

    final items = <_PortalNavItem>[
      const _PortalNavItem(
        label: 'Resumo',
        icon: Icons.dashboard_outlined,
        section: _PortalSection.global,
        builder: _PortalLandingSection.new,
      ),
      _PortalNavItem(
        label: 'Conta',
        icon: Icons.manage_accounts_outlined,
        section: _PortalSection.global,
        builder:
            ({required activeTenant, required activeRepresentedCompanyName}) =>
                _AccountSection(
                  activeTenant: activeTenant,
                  accountContractLock: accountContractLock,
                  upgradingWorkspace: _upgradingWorkspace,
                  onUpgradeToRep: () => _openUpgradeToRepDialog(activeTenant),
                ),
      ),
      if (supportsRepresentedCompanies)
        const _PortalNavItem(
          label: 'Representadas',
          icon: Icons.apartment_outlined,
          section: _PortalSection.global,
          builder: _RepresentedCompaniesSection.new,
        )
      else
        const _PortalNavItem(
          label: 'Parceiros',
          icon: Icons.handshake_outlined,
          section: _PortalSection.global,
          builder: _PartnersSection.new,
        ),
    ];

    if (supportsRepresentedCompanies) {
      items.addAll(const [
        _PortalNavItem(
          label: 'Clientes',
          icon: Icons.groups_outlined,
          section: _PortalSection.global,
          builder: _CustomersSection.new,
        ),
        _PortalNavItem(
          label: 'Pedidos',
          icon: Icons.receipt_long_outlined,
          section: _PortalSection.global,
          builder: _OrdersSection.new,
        ),
        _PortalNavItem(
          label: 'Tarefas',
          icon: Icons.task_alt_outlined,
          section: _PortalSection.global,
          builder: _TasksSection.new,
        ),
        _PortalNavItem(
          label: 'Representada',
          icon: Icons.flag_outlined,
          section: _PortalSection.tenant,
          builder: _TenantWorkspaceHubSection.new,
          opensTenantModuleShell: true,
        ),
      ]);
    }

    if (isTenantManager) {
      items.add(
        const _PortalNavItem(
          label: 'Billing',
          icon: Icons.payments_outlined,
          section: _PortalSection.global,
          builder: _BillingSection.new,
        ),
      );

      if (isEnterpriseWorkspace) {
        items.add(
          const _PortalNavItem(
            label: 'Clientes',
            icon: Icons.groups_outlined,
            section: _PortalSection.tenant,
            builder: _CustomersSection.new,
          ),
        );
      }

      items.addAll(const [
        _PortalNavItem(
          label: 'Produtos',
          icon: Icons.inventory_2_outlined,
          section: _PortalSection.tenant,
          builder: _ProductsCatalogSection.new,
          tenantModule: true,
          hideFromNavigation: true,
        ),
        _PortalNavItem(
          label: 'Tabelas de preço',
          icon: Icons.price_change_outlined,
          section: _PortalSection.tenant,
          builder: _PricingCatalogSection.new,
          tenantModule: true,
          hideFromNavigation: true,
        ),
        _PortalNavItem(
          label: 'Condições de pagamento',
          icon: Icons.receipt_long_outlined,
          section: _PortalSection.tenant,
          builder: _PaymentConditionsSection.new,
          tenantModule: true,
          hideFromNavigation: true,
        ),
        _PortalNavItem(
          label: 'Políticas',
          icon: Icons.policy_outlined,
          section: _PortalSection.tenant,
          builder: _SimpleSectionPage.politicas,
          tenantModule: true,
          hideFromNavigation: true,
        ),
        _PortalNavItem(
          label: 'ERP',
          icon: Icons.integration_instructions_outlined,
          section: _PortalSection.tenant,
          builder: _SimpleSectionPage.erp,
          tenantModule: true,
          hideFromNavigation: true,
        ),
        _PortalNavItem(
          label: 'Auditoria',
          icon: Icons.fact_check_outlined,
          section: _PortalSection.tenant,
          builder: _SimpleSectionPage.auditoria,
          tenantModule: true,
          hideFromNavigation: true,
        ),
      ]);
    } else {
      items.addAll(const [
        _PortalNavItem(
          label: 'Produtos',
          icon: Icons.inventory_2_outlined,
          section: _PortalSection.tenant,
          builder: _ProductsCatalogSection.new,
          tenantModule: true,
          hideFromNavigation: true,
        ),
        _PortalNavItem(
          label: 'Tabelas de preço',
          icon: Icons.price_change_outlined,
          section: _PortalSection.tenant,
          builder: _PricingCatalogSection.new,
          tenantModule: true,
          hideFromNavigation: true,
        ),
        _PortalNavItem(
          label: 'Condições de pagamento',
          icon: Icons.receipt_long_outlined,
          section: _PortalSection.tenant,
          builder: _PaymentConditionsSection.new,
          tenantModule: true,
          hideFromNavigation: true,
        ),
        _PortalNavItem(
          label: 'Políticas',
          icon: Icons.policy_outlined,
          section: _PortalSection.tenant,
          builder: _SimpleSectionPage.politicas,
          tenantModule: true,
          hideFromNavigation: true,
        ),
      ]);
    }

    if (canAccessInvites) {
      items.add(
        const _PortalNavItem(
          label: 'Convites',
          icon: Icons.badge_outlined,
          section: _PortalSection.tenant,
          builder: _SimpleSectionPage.convites,
          tenantModule: true,
          hideFromNavigation: true,
        ),
      );
    }

    if (isEnterpriseWorkspace) {
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        if (!item.tenantModule) {
          continue;
        }
        items[index] = item.copyWith(hideFromNavigation: false);
      }
    }

    return items;
  }

  List<_PortalMenuSection> _groupItems(
    List<_PortalNavItem> items,
    TenantEntryOption activeTenant,
  ) {
    final global = <_PortalNavItem>[];
    final tenant = <_PortalNavItem>[];

    for (final item in items) {
      if (item.section == _PortalSection.global) {
        global.add(item);
      } else {
        tenant.add(item);
      }
    }

    final supportsRepresentedCompanies =
        activeTenant.workspaceType == 'rep_workspace' ||
        activeTenant.workspaceType == 'seller_solo_workspace';

    return [
      _PortalMenuSection(title: 'Global da conta SaaS', items: global),
      _PortalMenuSection(
        title: supportsRepresentedCompanies ? 'Representada' : 'Empresa ativa',
        items: tenant,
      ),
    ];
  }
}

enum _PortalSection { global, tenant }

class _PortalNavItem {
  const _PortalNavItem({
    required this.label,
    required this.icon,
    required this.section,
    required this.builder,
    this.hideFromNavigation = false,
    this.tenantModule = false,
    this.opensTenantModuleShell = false,
  });

  final String label;
  final IconData icon;
  final _PortalSection section;
  final _PortalSectionBuilder builder;
  final bool hideFromNavigation;
  final bool tenantModule;
  final bool opensTenantModuleShell;

  _PortalNavItem copyWith({
    bool? hideFromNavigation,
    bool? tenantModule,
    bool? opensTenantModuleShell,
  }) {
    return _PortalNavItem(
      label: label,
      icon: icon,
      section: section,
      builder: builder,
      hideFromNavigation: hideFromNavigation ?? this.hideFromNavigation,
      tenantModule: tenantModule ?? this.tenantModule,
      opensTenantModuleShell:
          opensTenantModuleShell ?? this.opensTenantModuleShell,
    );
  }
}

typedef _PortalSectionBuilder = Widget Function({
  required TenantEntryOption activeTenant,
  required String? activeRepresentedCompanyName,
});

class _PortalMenuSection {
  const _PortalMenuSection({required this.title, required this.items});

  final String title;
  final List<_PortalNavItem> items;
}
