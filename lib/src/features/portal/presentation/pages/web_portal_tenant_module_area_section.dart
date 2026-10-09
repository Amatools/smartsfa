part of 'web_portal_page.dart';

class _TenantWorkspaceModuleArea extends StatefulWidget {
  const _TenantWorkspaceModuleArea({
    required this.activeTenant,
    required this.activeRepresentedCompanyName,
    required this.selectedRepresentedCompanyId,
    required this.tenantItems,
    required this.selectedItemLabel,
    required this.tenantSectionLocked,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;
  final String? selectedRepresentedCompanyId;
  final List<_PortalNavItem> tenantItems;
  final String selectedItemLabel;
  final bool tenantSectionLocked;

  @override
  State<_TenantWorkspaceModuleArea> createState() =>
      _TenantWorkspaceModuleAreaState();
}

class _TenantWorkspaceModuleAreaState
    extends State<_TenantWorkspaceModuleArea> {
  String? _virtualSubmenuKey;

  @override
  void didUpdateWidget(covariant _TenantWorkspaceModuleArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTenant.tenantId != widget.activeTenant.tenantId) {
      _virtualSubmenuKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: WorkspaceProfileService(FirebaseFirestore.instance)
          .watchWorkspace(widget.activeTenant.tenantId),
      builder: (context, workspaceSnapshot) {
        final workspaceData =
            workspaceSnapshot.data ?? const <String, dynamic>{};
        final planTier = _workspacePlanTier(workspaceData);
        final canUseAdvancedPricing = _isFeatureAvailableByPlan(
          workspaceType: widget.activeTenant.workspaceType,
          planTier: planTier,
          featureKey: _featureAdvancedPricing,
        );
        final advancedPricingEnabled =
            _featureFlagEnabled(
              workspaceData,
              _featureAdvancedPricing,
              legacyField: 'advancedPricingEnabled',
            ) &&
            canUseAdvancedPricing;
        final modules = _buildTenantCommercialModules(
          widget.tenantItems,
          advancedPricingEnabled: advancedPricingEnabled,
        );
        if (modules.isEmpty) {
          return const SizedBox.shrink();
        }

        if (_virtualSubmenuKey != null &&
            !_hasSubmenuKey(modules, _virtualSubmenuKey!)) {
          _virtualSubmenuKey = null;
        }

        if (_virtualSubmenuKey == null) {
          final fallback =
              _findSubmenuByLabel(modules, widget.selectedItemLabel) ??
              _firstEnabledSubmenu(modules);
          _virtualSubmenuKey = fallback?.key;
        }

        final activeSubmenu = _findSubmenuByKey(modules, _virtualSubmenuKey);

        final activeModule = _findModuleBySubmenu(modules, activeSubmenu?.key);

        Widget content;
        if (widget.tenantSectionLocked) {
          content = const _SimpleCardSection(
            title: 'Selecione a representada',
            subtitle: 'Para editar os módulos comerciais, selecione uma representada ativa no topo do portal.',
            items: ['Contexto da empresa', 'Produtos', 'Políticas comerciais'],
          );
        } else if (activeSubmenu == null) {
          content = const SizedBox.shrink();
        } else if (activeSubmenu.key == 'detalhes_cadastro_representada') {
          content = _RepresentedDetailsSection(
            activeTenant: widget.activeTenant,
            selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
          );
        } else if (activeSubmenu.key == 'categorias') {
          content = _CategoriesSection(
            activeTenant: widget.activeTenant,
            selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
          );
        } else if (activeSubmenu.key == 'unidades') {
          content = _UnitsSection(
            activeTenant: widget.activeTenant,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
          );
        } else if (activeSubmenu.key == 'fotos') {
          content = _MediaLibrarySection(
            activeTenant: widget.activeTenant,
            selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
          );
        } else if (activeSubmenu.key == 'acrescimos_descontos') {
          content = _CommercialAdjustmentsSection(
            activeTenant: widget.activeTenant,
            selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
          );
        } else if (activeSubmenu.key == 'descontos_pontuais') {
          content = _OrderDiscountPoliciesSection(
            activeTenant: widget.activeTenant,
            selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
          );
        } else if (activeSubmenu.key == 'parametros_workspace') {
          content = _WorkspaceParametersSection(
            activeTenant: widget.activeTenant,
          );
        } else if (activeSubmenu.key == 'tributacoes') {
          content = _TaxRulesSection(
            activeTenant: widget.activeTenant,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
          );
        } else if (activeSubmenu.key == 'produtos_tabelas') {
          content = _ProductsCatalogSection(
            activeTenant: widget.activeTenant,
            selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
          );
        } else if (activeSubmenu.key == 'tabelas_preco_avancadas') {
          content = _PricingCatalogSection(
            activeTenant: widget.activeTenant,
            selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
          );
        } else if (activeSubmenu.linkedItemLabel == null) {
          content = _SimpleCardSection(
            title: activeSubmenu.label,
            subtitle: 'Submenu criado para evolução. A implementação detalhada entra no próximo ciclo.',
            items: const [
              'Estrutura de tela pronta',
              'Regras de permissão herdam o módulo',
              'Persistência será conectada quando iniciar o desenvolvimento',
            ],
          );
        } else {
          final linkedItem = widget.tenantItems.firstWhere(
            (item) => item.label == activeSubmenu.linkedItemLabel,
          );
          content = linkedItem.builder(
            activeTenant: widget.activeTenant,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    color: Colors.white,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final module in modules)
                            ChoiceChip(
                              avatar: Icon(module.icon, size: 16),
                              label: Text(
                                module.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              side: BorderSide.none,
                              shape: const StadiumBorder(),
                              selectedColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.85),
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.35),
                              selected: activeModule?.key == module.key,
                              onSelected: (_) {
                                final firstSubmenu = _firstEnabledSubmenu([
                                  module,
                                ]);
                                if (firstSubmenu == null) {
                                  return;
                                }
                                _navigateToSubmenu(firstSubmenu);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final submenu
                              in (activeModule?.submenus ??
                                  const <_TenantCommercialSubmenu>[]))
                            FilterChip(
                              label: Text(
                                submenu.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              side: BorderSide.none,
                              shape: const StadiumBorder(),
                              selectedColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.8),
                              backgroundColor: Colors.white,
                              selected: submenu.key == activeSubmenu?.key,
                              onSelected: (_) => _navigateToSubmenu(submenu),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: SingleChildScrollView(child: content)),
          ],
        );
      },
    );
  }

  void _navigateToSubmenu(_TenantCommercialSubmenu submenu) {
    final linkedLabel = submenu.linkedItemLabel;
    if (linkedLabel == null) {
      setState(() {
        _virtualSubmenuKey = submenu.key;
      });
      return;
    }

    var targetExists = false;
    for (final item in widget.tenantItems) {
      if (item.label == linkedLabel) {
        targetExists = true;
        break;
      }
    }
    if (!targetExists) {
      return;
    }

    setState(() {
      _virtualSubmenuKey = submenu.key;
    });
  }

  _TenantCommercialModule? _findModuleBySubmenu(
    List<_TenantCommercialModule> modules,
    String? submenuKey,
  ) {
    if (submenuKey == null) {
      return modules.isEmpty ? null : modules.first;
    }
    for (final module in modules) {
      if (module.submenus.any((submenu) => submenu.key == submenuKey)) {
        return module;
      }
    }
    return modules.isEmpty ? null : modules.first;
  }

  _TenantCommercialSubmenu? _findSubmenuByLabel(
    List<_TenantCommercialModule> modules,
    String label,
  ) {
    for (final module in modules) {
      for (final submenu in module.submenus) {
        if (submenu.linkedItemLabel == label) {
          return submenu;
        }
      }
    }
    return null;
  }

  _TenantCommercialSubmenu? _findSubmenuByKey(
    List<_TenantCommercialModule> modules,
    String? key,
  ) {
    if (key == null || key.isEmpty) {
      return null;
    }
    for (final module in modules) {
      for (final submenu in module.submenus) {
        if (submenu.key == key) {
          return submenu;
        }
      }
    }
    return null;
  }

  bool _hasSubmenuKey(List<_TenantCommercialModule> modules, String key) {
    return _findSubmenuByKey(modules, key) != null;
  }

  _TenantCommercialSubmenu? _firstEnabledSubmenu(
    List<_TenantCommercialModule> modules,
  ) {
    for (final module in modules) {
      if (module.submenus.isNotEmpty) {
        return module.submenus.first;
      }
    }
    return null;
  }
}

class _TenantCommercialModule {
  const _TenantCommercialModule({
    required this.key,
    required this.label,
    required this.icon,
    required this.submenus,
  });

  final String key;
  final String label;
  final IconData icon;
  final List<_TenantCommercialSubmenu> submenus;
}

class _TenantCommercialSubmenu {
  const _TenantCommercialSubmenu({
    required this.key,
    required this.label,
    this.linkedItemLabel,
  });

  final String key;
  final String label;
  final String? linkedItemLabel;
}

List<_TenantCommercialModule> _buildTenantCommercialModules(
  List<_PortalNavItem> tenantItems, {
  required bool advancedPricingEnabled,
}) {
  bool hasItem(String label) => tenantItems.any((item) => item.label == label);

  String? linkIfExists(String label) => hasItem(label) ? label : null;

  return [
    _TenantCommercialModule(
      key: 'detalhes',
      label: 'Detalhes',
      icon: Icons.badge_outlined,
      submenus: const [
        _TenantCommercialSubmenu(
          key: 'detalhes_cadastro_representada',
          label: 'Informações de cadastro',
        ),
      ],
    ),
    _TenantCommercialModule(
      key: 'produtos',
      label: 'Produtos',
      icon: Icons.inventory_2_outlined,
      submenus: [
        _TenantCommercialSubmenu(
          key: 'produtos_tabelas',
          label: 'Produtos e tabelas',
          linkedItemLabel: linkIfExists('Produtos'),
        ),
        if (advancedPricingEnabled)
          _TenantCommercialSubmenu(
            key: 'tabelas_preco_avancadas',
            label: 'Tabelas de preço',
            linkedItemLabel: linkIfExists('Tabelas de preço'),
          ),
        const _TenantCommercialSubmenu(
          key: 'gerenciar_estoque',
          label: 'Gerenciar estoque',
        ),
      ],
    ),
    _TenantCommercialModule(
      key: 'promocoes',
      label: 'Promoções',
      icon: Icons.local_offer_outlined,
      submenus: const [
        _TenantCommercialSubmenu(
          key: 'listas_promocionais',
          label: 'Listas promocionais',
        ),
      ],
    ),
    _TenantCommercialModule(
      key: 'destaques',
      label: 'Destaques',
      icon: Icons.star_outline,
      submenus: const [
        _TenantCommercialSubmenu(
          key: 'listas_destaque',
          label: 'Listas de destaque',
        ),
      ],
    ),
    _TenantCommercialModule(
      key: 'politicas',
      label: 'Políticas comerciais',
      icon: Icons.policy_outlined,
      submenus: [
        _TenantCommercialSubmenu(
          key: 'condicoes_pagamento',
          label: 'Condições de pagamento',
          linkedItemLabel: linkIfExists('Condições de pagamento'),
        ),
        const _TenantCommercialSubmenu(
          key: 'acrescimos_descontos',
          label: 'Acréscimos ou descontos',
        ),
        const _TenantCommercialSubmenu(
          key: 'descontos_pontuais',
          label: 'Descontos pontuais',
        ),
        const _TenantCommercialSubmenu(
          key: 'rentabilidade',
          label: 'Rentabilidade',
        ),
      ],
    ),
    _TenantCommercialModule(
      key: 'configuracoes',
      label: 'Configurações',
      icon: Icons.settings_outlined,
      submenus: const [
        _TenantCommercialSubmenu(
          key: 'parametros_workspace',
          label: 'Parâmetros',
        ),
        _TenantCommercialSubmenu(key: 'categorias', label: 'Categorias'),
        _TenantCommercialSubmenu(key: 'unidades', label: 'Unidades'),
        _TenantCommercialSubmenu(key: 'fotos', label: 'Fotos'),
        _TenantCommercialSubmenu(
          key: 'variacoes_produto',
          label: 'Variação de produtos',
        ),
        _TenantCommercialSubmenu(
          key: 'periodo_inatividade',
          label: 'Período de inatividade',
        ),
        _TenantCommercialSubmenu(key: 'tributacoes', label: 'Tributações'),
      ],
    ),
  ];
}
