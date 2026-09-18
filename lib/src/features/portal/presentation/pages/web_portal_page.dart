import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_lib;

import '../../../../core/data/firestore/firestore_cliente_pre_cadastro_repository.dart';
import '../../../../core/data/firestore/firestore_cliente_repository.dart';
import '../../../../core/data/firestore/firestore_pedido_repository.dart';
import '../../../../core/data/firestore/firestore_produto_repository.dart';
import '../../../../core/data/firestore/firestore_tabela_preco_repository.dart';
import '../../../../core/models/app_identity.dart';
import '../../../../core/models/tenant_entry_decision.dart';
import '../../../auth/services/solo_workspace_service.dart';
import '../../../auth/services/tenant_membership_service.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../../../clientes/presentation/pages/clientes_page.dart';
import '../../../pedidos/presentation/pages/pedidos_page.dart';
import '../../../precos/presentation/pages/tabelas_preco_page.dart';
import '../../../produtos/presentation/pages/produtos_page.dart';

const String _planTierBase = 'base';
const String _planTierUpgrade = 'upgrade';
const String _featureAdvancedPricing = 'advancedPricingEnabled';

String _normalizeDefaultScopeKey(String? representedCompanyId) {
  final represented = (representedCompanyId ?? '').trim();
  if (represented.isEmpty) {
    return 'tenant_default';
  }
  return represented.replaceAll('.', '_').replaceAll('/', '_');
}

DateTime _readDateTime(Object? value) {
  if (value is Timestamp) {
    return value.toDate().toUtc();
  }
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toUtc();
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

const Map<String, Map<String, Set<String>>> _workspacePlanFeatureMatrix = {
  'seller_solo_workspace': {
    _planTierBase: <String>{},
    _planTierUpgrade: <String>{_featureAdvancedPricing},
  },
  'rep_workspace': {
    _planTierBase: <String>{},
    _planTierUpgrade: <String>{_featureAdvancedPricing},
  },
  'brand_owner_workspace': {
    _planTierBase: <String>{},
    _planTierUpgrade: <String>{_featureAdvancedPricing},
  },
};

class WebPortalPage extends StatelessWidget {
  const WebPortalPage({
    super.key,
    required this.identity,
    required this.onSignOut,
  });

  final AppIdentity identity;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return _WebPortalShell(identity: identity, onSignOut: onSignOut);
  }
}

class _WebPortalShell extends StatefulWidget {
  const _WebPortalShell({
    required this.identity,
    required this.onSignOut,
  });

  final AppIdentity identity;
  final VoidCallback onSignOut;

  @override
  State<_WebPortalShell> createState() => _WebPortalShellState();
}

class _WebPortalShellState extends State<_WebPortalShell> {
  int _selectedIndex = 0;
  String? _activeTenantId;
  bool _showWorkspaceSelection = true;
  bool _upgradingWorkspace = false;
  bool _settingFavoriteRepresented = false;
  final Map<String, String?> _activeRepresentedCompanyByTenant = {};
  final Map<String, String?> _activeRepresentedCompanyNameByTenant = {};

  Future<AccountContractLock> _loadAccountContractLock(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    return AccountContractLock.fromValue(
      (doc.data()?['accountContractLock'] ?? '').toString().trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Usuario nao autenticado.')),
      );
    }

    return StreamBuilder<List<TenantEntryOption>>(
      stream: TenantMembershipService(
        FirebaseFirestore.instance,
      ).watchTenantChoicesForUser(user.uid),
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
              child: Text('Nenhum tenant ativo encontrado para este usuario.'),
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
                    selectedTenantId: _activeTenantId ?? preferredTenant.tenantId,
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
            final representedRequired = _requiresRepresentedSelection(activeTenant);
            final representedSelected =
                (_activeRepresentedCompanyByTenant[activeTenant.tenantId] ?? '')
                    .trim()
                    .isNotEmpty;
            final tenantSectionLocked = representedRequired && !representedSelected;

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
                          _activeRepresentedCompanyNameByTenant[activeTenant.tenantId],
                      selectedRepresentedCompanyId:
                        _activeRepresentedCompanyByTenant[activeTenant.tenantId],
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
                            _activeRepresentedCompanyNameByTenant[activeTenant.tenantId],
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
                                _activeRepresentedCompanyNameByTenant[
                                  activeTenant.tenantId
                                ],
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
                                      _activeRepresentedCompanyByTenant[
                                        activeTenant.tenantId
                                      ],
                                  selectedRepresentedCompanyName:
                                      _activeRepresentedCompanyNameByTenant[
                                        activeTenant.tenantId
                                      ],
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
                                _activeRepresentedCompanyByTenant[
                                  activeTenant.tenantId
                                ],
                            selectedRepresentedCompanyName:
                                _activeRepresentedCompanyNameByTenant[
                                  activeTenant.tenantId
                                ],
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
                                  visibleItems[index].section == _PortalSection.tenant) {
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
                                    enabled: !(tenantSectionLocked &&
                                        item.section == _PortalSection.tenant),
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
    final defaultTenant = tenants.where((tenant) => tenant.defaultTenant).toList();
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
      text: '${activeTenant.tenantName} Representacoes',
    );
    final cnpjController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upgrade para Representacoes'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Este upgrade muda seu plano de Individual para Representacoes sem criar nova conta.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Seu contexto Individual sera substituido e os dados migrados para o novo workspace.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome do novo workspace de Representacoes',
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
            'Upgrade concluido. ${result.migratedScopedDocs + result.migratedTenantOnlyDocs} registros migrados para Representacoes.',
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro Firebase (${error.code}): ${error.message ?? 'falha no upgrade.'}'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha no upgrade: $error')),
      );
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
    final normalizedRole = activeTenant.role.trim().toLowerCase().replaceAll(' ', '_');
    final isTenantManager = normalizedRole == 'owner' ||
        normalizedRole == 'gerente' ||
        normalizedRole == 'platform_admin';
    final canAccessInvites = normalizedRole == 'owner' ||
      normalizedRole == 'gerente' ||
      normalizedRole == 'representante' ||
      normalizedRole == 'platform_admin';
    final isEnterpriseWorkspace = activeTenant.workspaceType == 'brand_owner_workspace';
    final supportsRepresentedCompanies = activeTenant.workspaceType == 'rep_workspace' ||
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
        builder: ({
          required activeTenant,
          required activeRepresentedCompanyName,
        }) => _AccountSection(
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
          label: 'Condicoes de pagamento',
          icon: Icons.receipt_long_outlined,
          section: _PortalSection.tenant,
          builder: _PaymentConditionsSection.new,
          tenantModule: true,
          hideFromNavigation: true,
        ),
        _PortalNavItem(
          label: 'Politicas',
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
          label: 'Condicoes de pagamento',
          icon: Icons.receipt_long_outlined,
          section: _PortalSection.tenant,
          builder: _PaymentConditionsSection.new,
          tenantModule: true,
          hideFromNavigation: true,
        ),
        _PortalNavItem(
          label: 'Politicas',
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

    final supportsRepresentedCompanies = activeTenant.workspaceType == 'rep_workspace' ||
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
      opensTenantModuleShell: opensTenantModuleShell ?? this.opensTenantModuleShell,
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
  State<_TenantWorkspaceModuleArea> createState() => _TenantWorkspaceModuleAreaState();
}

class _TenantWorkspaceModuleAreaState extends State<_TenantWorkspaceModuleArea> {
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
        final workspaceData = workspaceSnapshot.data ?? const <String, dynamic>{};
        final planTier = _workspacePlanTier(workspaceData);
        final canUseAdvancedPricing = _isFeatureAvailableByPlan(
          workspaceType: widget.activeTenant.workspaceType,
          planTier: planTier,
          featureKey: _featureAdvancedPricing,
        );
        final advancedPricingEnabled = _featureFlagEnabled(
          workspaceData,
          _featureAdvancedPricing,
          legacyField: 'advancedPricingEnabled',
        ) && canUseAdvancedPricing;
        final modules = _buildTenantCommercialModules(
          widget.tenantItems,
          advancedPricingEnabled: advancedPricingEnabled,
        );
        if (modules.isEmpty) {
          return const SizedBox.shrink();
        }

        if (_virtualSubmenuKey != null && !_hasSubmenuKey(modules, _virtualSubmenuKey!)) {
          _virtualSubmenuKey = null;
        }

        if (_virtualSubmenuKey == null) {
          final fallback = _findSubmenuByLabel(modules, widget.selectedItemLabel) ??
              _firstEnabledSubmenu(modules);
          _virtualSubmenuKey = fallback?.key;
        }

        final activeSubmenu = _findSubmenuByKey(modules, _virtualSubmenuKey);

        final activeModule = _findModuleBySubmenu(modules, activeSubmenu?.key);

        Widget content;
        if (widget.tenantSectionLocked) {
          content = const _SimpleCardSection(
            title: 'Selecione a representada',
            subtitle:
                'Para editar os modulos comerciais, selecione uma representada ativa no topo do portal.',
            items: ['Contexto da empresa', 'Produtos', 'Politicas comerciais'],
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
        } else if (activeSubmenu.key == 'parametros_workspace') {
          content = _WorkspaceParametersSection(activeTenant: widget.activeTenant);
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
            subtitle:
                'Submenu criado para evolucao. A implementacao detalhada entra no proximo ciclo.',
            items: const [
              'Estrutura de tela pronta',
              'Regras de permissao herdam o modulo',
              'Persistencia sera conectada quando iniciar o desenvolvimento',
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
                                style: const TextStyle(fontWeight: FontWeight.w600),
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
                                final firstSubmenu = _firstEnabledSubmenu([module]);
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
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final submenu in (activeModule?.submenus ?? const <_TenantCommercialSubmenu>[]))
                            FilterChip(
                              label: Text(
                                submenu.label,
                                style: const TextStyle(fontWeight: FontWeight.w600),
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

  _TenantCommercialSubmenu? _firstEnabledSubmenu(List<_TenantCommercialModule> modules) {
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
}
) {
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
          label: 'Informacoes de cadastro',
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
      label: 'Promocoes',
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
      label: 'Politicas comerciais',
      icon: Icons.policy_outlined,
      submenus: [
        _TenantCommercialSubmenu(
          key: 'condicoes_pagamento',
          label: 'Condicoes de pagamento',
          linkedItemLabel: linkIfExists('Condicoes de pagamento'),
        ),
        const _TenantCommercialSubmenu(
          key: 'acrescimos_descontos',
          label: 'Acrescimos ou descontos',
        ),
        const _TenantCommercialSubmenu(
          key: 'rentabilidade',
          label: 'Rentabilidade',
        ),
      ],
    ),
    _TenantCommercialModule(
      key: 'configuracoes',
      label: 'Configuracoes',
      icon: Icons.settings_outlined,
      submenus: const [
        _TenantCommercialSubmenu(
          key: 'parametros_workspace',
          label: 'Parametros',
        ),
        _TenantCommercialSubmenu(
          key: 'categorias',
          label: 'Categorias',
        ),
        _TenantCommercialSubmenu(
          key: 'fotos',
          label: 'Fotos',
        ),
        _TenantCommercialSubmenu(
          key: 'variacoes_produto',
          label: 'Variacao de produtos',
        ),
        _TenantCommercialSubmenu(
          key: 'periodo_inatividade',
          label: 'Periodo de inatividade',
        ),
        _TenantCommercialSubmenu(
          key: 'tributacoes',
          label: 'Tributacoes',
        ),
      ],
    ),
  ];
}

class _WorkspaceSelectionView extends StatelessWidget {
  const _WorkspaceSelectionView({
    required this.identity,
    required this.tenants,
    required this.selectedTenantId,
    required this.onSelectTenant,
    required this.onSignOut,
  });

  final AppIdentity identity;
  final List<TenantEntryOption> tenants;
  final String selectedTenantId;
  final ValueChanged<String> onSelectTenant;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_tree_outlined, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Selecione o workspace para entrar no painel',
                          style: textTheme.headlineSmall,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: onSignOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sair da conta'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Conta autenticada: ${identity.userLabel}',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isWide ? 2 : 1,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: isWide ? 2.7 : 2.3,
                    ),
                    itemCount: tenants.length,
                    itemBuilder: (context, index) {
                      final tenant = tenants[index];
                      final selected = tenant.tenantId == selectedTenantId;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => onSelectTenant(tenant.tenantId),
                        child: Ink(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outlineVariant,
                              width: selected ? 2 : 1,
                            ),
                            color: selected
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withAlpha(70)
                                : Theme.of(context).colorScheme.surface,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.domain_outlined),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tenant.tenantName,
                                      style: textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_workspaceTypeLabel(tenant.workspaceType)} • ${_roleLabel(tenant.role, tenant.workspaceType, tenant.tenantName)}',
                                      style: textTheme.bodySmall,
                                    ),
                                    if (tenant.defaultTenant) ...[
                                      const SizedBox(height: 6),
                                      const Text('Padrao da conta'),
                                    ],
                                  ],
                                ),
                              ),
                              FilledButton(
                                onPressed: () => onSelectTenant(tenant.tenantId),
                                child: const Text('Entrar'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WebPortalSidebar extends StatelessWidget {
  const _WebPortalSidebar({
    required this.identity,
    required this.activeTenant,
    required this.accountContractLock,
    required this.sections,
    required this.visibleItems,
    required this.selectedIndex,
    required this.onMenuSelected,
    required this.tenantSectionLocked,
    this.selectedRepresentedCompanyName,
  });

  final AppIdentity identity;
  final TenantEntryOption activeTenant;
  final AccountContractLock accountContractLock;
  final List<_PortalMenuSection> sections;
  final List<_PortalNavItem> visibleItems;
  final int selectedIndex;
  final ValueChanged<int> onMenuSelected;
  final bool tenantSectionLocked;
  final String? selectedRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WebPortalBrandCard(
              identity: identity,
              activeTenant: activeTenant,
              accountContractLock: accountContractLock,
            ),
            if (activeTenant.workspaceType == 'seller_solo_workspace' ||
                activeTenant.workspaceType == 'rep_workspace') ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Representada ativa',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (selectedRepresentedCompanyName ?? '').trim().isEmpty
                            ? 'Nenhuma selecionada'
                            : selectedRepresentedCompanyName!.trim(),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  for (final section in sections) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        section.title.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    for (final item in section.items)
                      Builder(
                        builder: (context) {
                          final disabled = tenantSectionLocked &&
                              item.section == _PortalSection.tenant;
                          final isRepresentedHub = item.label == 'Representada';
                          final representedName =
                              (selectedRepresentedCompanyName ?? '').trim();
                          return ListTile(
                            selected: selectedIndex == _itemIndex(item),
                            enabled: !disabled,
                            leading: Icon(item.icon),
                            title: Text(item.label),
                            subtitle: isRepresentedHub
                                ? Text(
                                    representedName.isEmpty
                                        ? 'Nenhuma selecionada'
                                        : representedName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            onTap: disabled
                                ? null
                                : () => onMenuSelected(_itemIndex(item)),
                          );
                        },
                      ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _itemIndex(_PortalNavItem item) {
    return visibleItems.indexOf(item);
  }
}

class _WebPortalBrandCard extends StatelessWidget {
  const _WebPortalBrandCard({
    required this.identity,
    required this.activeTenant,
    required this.accountContractLock,
  });

  final AppIdentity identity;
  final TenantEntryOption activeTenant;
  final AccountContractLock accountContractLock;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    identity.tenantName.isNotEmpty
                        ? identity.tenantName[0].toUpperCase()
                        : 'S',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Smart SFA',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Painel da plataforma',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Workspace em uso', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(activeTenant.tenantName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              _workspaceTypeLabel(activeTenant.workspaceType),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_roleLabel(activeTenant.role, activeTenant.workspaceType, activeTenant.tenantName)} • ${_accountContractLockLabel(accountContractLock)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Tooltip(
                  message: 'Conta da Plataforma: ${identity.userLabel}\n'
                      'Workspace em uso: ${activeTenant.tenantName}\n'
                      'Workspace: ${_workspaceTypeLabel(activeTenant.workspaceType)}\n'
                      'Tipo de conta: ${_accountContractLockLabel(accountContractLock)}',
                  child: const Icon(
                    Icons.info_outline,
                    size: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WebPortalTopBar extends StatelessWidget {
  const _WebPortalTopBar({
    required this.identity,
    required this.activeTenant,
    required this.accountContractLock,
    required this.selectedRepresentedCompanyId,
    required this.selectedRepresentedCompanyName,
    required this.onRepresentedCompanySelected,
    required this.onToggleFavoriteRepresented,
    required this.settingFavoriteRepresented,
    required this.onBackToWorkspaceSelection,
    required this.onSignOut,
  });

  final AppIdentity identity;
  final TenantEntryOption activeTenant;
  final AccountContractLock accountContractLock;
  final String? selectedRepresentedCompanyId;
  final String? selectedRepresentedCompanyName;
  final void Function(String? companyId, String? companyName)
      onRepresentedCompanySelected;
  final Future<void> Function({
    required TenantEntryOption activeTenant,
    required String? selectedRepresentedCompanyId,
    required String? favoriteRepresentedCompanyId,
  }) onToggleFavoriteRepresented;
  final bool settingFavoriteRepresented;
  final VoidCallback onBackToWorkspaceSelection;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.web_asset_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Portal de Gestao',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${identity.tenantName} • ${_roleLabel(activeTenant.role, activeTenant.workspaceType, activeTenant.tenantName)} • ${_workspaceTypeLabel(activeTenant.workspaceType)} • ${_accountContractLockLabel(accountContractLock)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 320,
            child: StreamBuilder<Map<String, dynamic>?>(
              stream: WorkspaceProfileService(
                FirebaseFirestore.instance,
              ).watchWorkspace(activeTenant.tenantId),
              builder: (context, snapshot) {
                final workspaceData = snapshot.data ?? const <String, dynamic>{};
                final supportsRepresentedCompanies =
                    activeTenant.workspaceType == 'seller_solo_workspace' ||
                    activeTenant.workspaceType == 'rep_workspace';
                final favoriteRepresentedCompanyId =
                    (workspaceData['favoriteRepresentedCompanyId'] ?? '')
                        .toString()
                        .trim();
                return StreamBuilder<List<Map<String, Object?>>>(
                  stream: WorkspaceProfileService(
                    FirebaseFirestore.instance,
                  ).watchRepresentedCompanies(activeTenant.tenantId),
                  builder: (context, representedSnapshot) {
                    final representedCompanies = _representedCompaniesFromStorage(
                      representedSnapshot.data ?? const <Map<String, Object?>>[],
                    );
                    final selectedId = representedCompanies.any(
                      (company) => company.id == selectedRepresentedCompanyId,
                    )
                        ? selectedRepresentedCompanyId
                        : null;
                    final favoriteId = representedCompanies.any(
                      (company) => company.id == favoriteRepresentedCompanyId,
                    )
                        ? favoriteRepresentedCompanyId
                        : null;
                    final effectiveSelectedId = selectedId ?? favoriteId;
                    if (effectiveSelectedId != null &&
                        effectiveSelectedId != selectedRepresentedCompanyId) {
                      _RepresentedCompany? selectedCompany;
                      for (final company in representedCompanies) {
                        if (company.id == effectiveSelectedId) {
                          selectedCompany = company;
                          break;
                        }
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        onRepresentedCompanySelected(
                          effectiveSelectedId,
                          selectedCompany?.nomeFantasia,
                        );
                      });
                    }
                    final isFavoriteSelection =
                        effectiveSelectedId != null &&
                            effectiveSelectedId == favoriteRepresentedCompanyId;

                    return Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: effectiveSelectedId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Representada ativa',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Nenhuma selecionada'),
                              ),
                              ...representedCompanies.map(
                                (company) => DropdownMenuItem<String?>(
                                  value: company.id,
                                  child: Row(
                                    children: [
                                      _RepresentedCompanyAvatar(
                                        company: company,
                                        size: 40,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          company.nomeFantasia,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            onChanged: !supportsRepresentedCompanies
                                ? null
                                : (value) {
                                    _RepresentedCompany? selectedCompany;
                                    for (final company in representedCompanies) {
                                      if (company.id == value) {
                                        selectedCompany = company;
                                        break;
                                      }
                                    }
                                    onRepresentedCompanySelected(
                                      value,
                                      selectedCompany?.nomeFantasia,
                                    );
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: effectiveSelectedId == null
                              ? 'Selecione uma representada para favoritar'
                              : isFavoriteSelection
                              ? 'Representada favorita'
                              : 'Favoritar representada ativa',
                          child: IconButton.outlined(
                            onPressed: effectiveSelectedId == null ||
                                    settingFavoriteRepresented ||
                                    !supportsRepresentedCompanies
                                ? null
                                : () => onToggleFavoriteRepresented(
                                      activeTenant: activeTenant,
                                      selectedRepresentedCompanyId: effectiveSelectedId,
                                      favoriteRepresentedCompanyId:
                                          favoriteRepresentedCompanyId,
                                    ),
                            icon: Icon(
                              isFavoriteSelection ? Icons.star : Icons.star_outline,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Trocar workspace',
            child: IconButton.outlined(
              onPressed: onBackToWorkspaceSelection,
              icon: const Icon(Icons.u_turn_left),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Sair da conta',
            child: IconButton.outlined(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalLandingSection extends StatelessWidget {
  const _PortalLandingSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isWide = MediaQuery.sizeOf(context).width >= 1100;

    final modules = [
      _PortalModule(
        title: 'Tabelas de preço',
        subtitle: 'Regras por marca, segmento, cliente, produto e tags.',
        icon: Icons.price_change_outlined,
      ),
      _PortalModule(
        title: 'Politicas comerciais',
        subtitle: 'Limites, excecoes, descontos, acrescimos e travas.',
        icon: Icons.policy_outlined,
      ),
      _PortalModule(
        title: 'ERP e integracoes',
        subtitle: 'Parametros de conector, mapeamento e status.',
        icon: Icons.integration_instructions_outlined,
      ),
      _PortalModule(
        title: 'Convites e memberships',
        subtitle: 'Onboarding, aprovacoes e audicao de acesso.',
        icon: Icons.badge_outlined,
      ),
      _PortalModule(
        title: 'Auditoria',
        subtitle: 'Eventos criticos, trilha de mudancas e suporte.',
        icon: Icons.fact_check_outlined,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Visao geral da conta', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'A conta SaaS controla a visão global; cada tenant navega isoladamente em seu próprio contexto.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _SummaryCard(title: 'Workspace em uso', value: activeTenant.tenantName),
            _SummaryCard(
              title: 'Seu acesso atual',
              value: _roleLabel(
                activeTenant.role,
                activeTenant.workspaceType,
                activeTenant.tenantName,
              ),
            ),
            _SummaryCard(
              title: 'Workspace atual',
              value: _workspaceTypeLabel(activeTenant.workspaceType),
            ),
            const _SummaryCard(title: 'Canal de acesso', value: 'Portal web'),
          ],
        ),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: isWide ? 3 : 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: isWide ? 1.8 : 2.6,
          children: modules.map((module) => _PortalModuleCard(module: module)).toList(),
        ),
      ],
    );
  }
}

class _BillingSection extends StatelessWidget {
  const _BillingSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return _SimpleCardSection(
      title: 'Billing',
      subtitle: 'Conta SaaS e faturamento do tenant ativo.',
      items: [
        'Plano atual do tenant: ${activeTenant.tenantName}',
        'Histórico de upgrade e downgrade',
        'Limites por plano e uso',
        'Cobrança por tenant, não por login',
      ],
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.activeTenant,
    required this.accountContractLock,
    required this.upgradingWorkspace,
    required this.onUpgradeToRep,
  });

  final TenantEntryOption activeTenant;
  final AccountContractLock accountContractLock;
  final bool upgradingWorkspace;
  final VoidCallback onUpgradeToRep;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canEditWorkspaceProfile = _canEditWorkspaceProfile(
      role: activeTenant.role,
      workspaceType: activeTenant.workspaceType,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Conta', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Configurações globais da sua conta e gestão de empresas no mesmo lugar.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: StreamBuilder<Map<String, dynamic>?>(
              stream: WorkspaceProfileService(
                FirebaseFirestore.instance,
              ).watchWorkspace(activeTenant.tenantId),
              builder: (context, snapshot) {
                final workspaceData = snapshot.data ?? const <String, dynamic>{};

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Dados do workspace',
                                    style: textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Informacoes base da conta e do workspace em uso.',
                                    style: textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (canEditWorkspaceProfile)
                              Tooltip(
                                message: 'Editar dados do workspace',
                                child: IconButton.outlined(
                                  onPressed: () => _openWorkspaceProfileEditor(
                                    context,
                                    activeTenant,
                                    workspaceData,
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _WorkspaceInfoGrid(
                          items: _buildWorkspaceInfoItems(
                            activeTenant: activeTenant,
                            accountContractLock: accountContractLock,
                            workspaceData: workspaceData,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestao de workspaces',
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (accountContractLock == AccountContractLock.enterpriseOnly) ...[
                      const Text('• Esta Conta BrandOp controla apenas a propria empresa contratante.'),
                      const SizedBox(height: 6),
                      const Text('• Nao e permitido criar outras empresas ou operacoes paralelas neste login.'),
                      const SizedBox(height: 6),
                      const Text('• Mudancas de plano/tipo devem ocorrer por migracao controlada, sem criar novo workspace.'),
                    ] else ...[
                      const Text('• Esta conta esta vinculada ao tipo de workspace atual para fins de billing e governanca.'),
                      const SizedBox(height: 6),
                      const Text('• O contexto Individual nao adiciona usuarios e nao abre cadeia de representacoes.'),
                      const SizedBox(height: 6),
                      const Text('• Para mudar de Individual para Representacoes (ou outro plano), o caminho e upgrade de plano.'),
                      const SizedBox(height: 6),
                      const Text('• Nao criamos workspace paralelo por esta tela para evitar divergencia de billing.'),
                      if (activeTenant.workspaceType == 'seller_solo_workspace') ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: upgradingWorkspace ? null : onUpgradeToRep,
                          icon: const Icon(Icons.upgrade_outlined),
                          label: Text(
                            upgradingWorkspace
                                ? 'Aplicando upgrade...'
                                : 'Upgrade para Representacoes',
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RepresentedCompaniesSection extends StatelessWidget {
  const _RepresentedCompaniesSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final supportsRepresentedCompanies =
        activeTenant.workspaceType == 'seller_solo_workspace' ||
        activeTenant.workspaceType == 'rep_workspace';
    final canManageRepresentedCompanies = _canManageRepresentedCompanies(
      role: activeTenant.role,
      workspaceType: activeTenant.workspaceType,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Representadas', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Cadastro e gestao das empresas representadas no workspace atual.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: StreamBuilder<Map<String, dynamic>?>(
                  stream: WorkspaceProfileService(
                    FirebaseFirestore.instance,
                  ).watchWorkspace(activeTenant.tenantId),
                  builder: (context, workspaceSnapshot) {
                    final workspaceData = workspaceSnapshot.data ?? const <String, dynamic>{};
                    final favoriteRepresentedCompanyId =
                        (workspaceData['favoriteRepresentedCompanyId'] ?? '')
                            .toString()
                            .trim();

                    return StreamBuilder<List<Map<String, Object?>>>(
                      stream: WorkspaceProfileService(
                        FirebaseFirestore.instance,
                      ).watchRepresentedCompanies(activeTenant.tenantId),
                      builder: (context, snapshot) {
                        final representedCompanies = _representedCompaniesFromStorage(
                          snapshot.data ?? const <Map<String, Object?>>[],
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Empresas representadas',
                                    style: textTheme.titleMedium,
                                  ),
                                ),
                                if (supportsRepresentedCompanies && canManageRepresentedCompanies)
                                  FilledButton.icon(
                                    onPressed: () => _createRepresentedCompany(
                                      context,
                                      activeTenant,
                                    ),
                                    icon: const Icon(Icons.add_business_outlined),
                                    label: const Text('Adicionar'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (!supportsRepresentedCompanies) ...[
                              const Text(
                                'Disponivel apenas para workspaces Individual e Representacoes.',
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'No contexto Empresa (BrandOp), esta conta administra apenas a empresa contratante.',
                              ),
                            ] else if (representedCompanies.isEmpty) ...[
                              const Text('Nenhuma representada cadastrada ainda.'),
                              const SizedBox(height: 6),
                              const Text(
                                'Use esta lista para manter as empresas que voce representa neste workspace.',
                              ),
                            ] else ...[
                              for (final company in representedCompanies)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              company.nomeFantasia.isEmpty
                                                  ? 'Sem nome fantasia'
                                                  : company.nomeFantasia,
                                              style: textTheme.titleSmall,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'CNPJ: ${company.cnpj.isEmpty ? 'Nao informado' : company.cnpj}',
                                            ),
                                            if (company.logradouro.isNotEmpty ||
                                                company.numero.isNotEmpty)
                                              Text(
                                                'Endereco: ${company.logradouro.isEmpty ? 'Nao informado' : company.logradouro}${company.numero.isEmpty ? '' : ', ${company.numero}'}',
                                              ),
                                            Text(
                                              'CEP: ${company.cep.isEmpty ? 'Nao informado' : company.cep}',
                                            ),
                                            Text(
                                              'Cidade/UF: ${company.cidade.isEmpty ? 'Nao informado' : company.cidade}${company.uf.isEmpty ? '' : '/${company.uf}'}',
                                            ),
                                            if (company.segmento.isNotEmpty)
                                              Text('Segmento: ${company.segmento}'),
                                          ],
                                        ),
                                      ),
                                      if (supportsRepresentedCompanies && canManageRepresentedCompanies) ...[
                                        Tooltip(
                                          message: company.id == favoriteRepresentedCompanyId
                                              ? 'Representada favorita'
                                              : 'Definir como favorita',
                                          child: IconButton.outlined(
                                            onPressed: company.id == favoriteRepresentedCompanyId
                                                ? null
                                                : () => _setFavoriteRepresentedCompany(
                                                      context,
                                                      activeTenant,
                                                      company,
                                                    ),
                                            icon: Icon(
                                              company.id == favoriteRepresentedCompanyId
                                                  ? Icons.star
                                                  : Icons.star_outline,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Tooltip(
                                          message: 'Editar',
                                          child: IconButton.outlined(
                                            onPressed: () => _editRepresentedCompany(
                                              context,
                                              activeTenant,
                                              company,
                                            ),
                                            icon: const Icon(Icons.edit_outlined),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Tooltip(
                                          message: 'Excluir',
                                          child: IconButton.outlined(
                                            onPressed: () => _deleteRepresentedCompany(
                                              context,
                                              activeTenant,
                                              company,
                                            ),
                                            icon: const Icon(Icons.delete_outline),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant,
  ) async {
    final payload = await _openRepresentedCompanyEditor(context);
    if (payload == null || !context.mounted) {
      return;
    }

    try {
      await WorkspaceProfileService(FirebaseFirestore.instance).upsertRepresentedCompany(
        tenantId: activeTenant.tenantId,
        values: payload,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Representada cadastrada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao cadastrar representada: $error')),
      );
    }
  }

  Future<void> _editRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant,
    _RepresentedCompany company,
  ) async {
    final payload = await _openRepresentedCompanyEditor(context, initial: company);
    if (payload == null || !context.mounted) {
      return;
    }

    try {
      await WorkspaceProfileService(FirebaseFirestore.instance).upsertRepresentedCompany(
        tenantId: activeTenant.tenantId,
        companyId: company.id,
        values: payload,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Representada atualizada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar representada: $error')),
      );
    }
  }

  Future<void> _deleteRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant,
    _RepresentedCompany company,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir representada'),
        content: Text(
          'Deseja excluir ${company.nomeFantasia.isEmpty ? 'esta representada' : company.nomeFantasia}?',
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
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await WorkspaceProfileService(FirebaseFirestore.instance).deleteRepresentedCompany(
        tenantId: activeTenant.tenantId,
        companyId: company.id,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Representada excluida com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao excluir representada: $error')),
      );
    }
  }

  Future<void> _setFavoriteRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant,
    _RepresentedCompany company,
  ) async {
    try {
      await WorkspaceProfileService(FirebaseFirestore.instance)
          .setFavoriteRepresentedCompany(
        tenantId: activeTenant.tenantId,
        companyId: company.id,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Representada favorita: ${company.nomeFantasia.isEmpty ? company.id : company.nomeFantasia}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar favorita: $error')),
      );
    }
  }
}

class _PartnersSection extends StatelessWidget {
  const _PartnersSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return _SimpleCardSection(
      title: 'Parceiros',
      subtitle:
          'Contexto enterprise: o workspace e focado na propria empresa. Parceiros comerciais serao administrados aqui.',
      items: const [
        'Distribuidores e revendas homologadas',
        'Politicas por parceiro',
        'Status comercial e operacional',
      ],
    );
  }
}

class _CustomersSection extends StatelessWidget {
  const _CustomersSection({
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
      userLabel: (userLabel == null || userLabel.isEmpty) ? 'Portal' : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace: activeTenant.workspaceType == 'seller_solo_workspace',
    );

    return ClientesPage(
      identity: identity,
      repository: FirestoreClienteRepository(FirebaseFirestore.instance),
      preCadastroRepository: FirestoreClientePreCadastroRepository(FirebaseFirestore.instance),
    );
  }
}

class _TasksSection extends StatelessWidget {
  const _TasksSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return _SimpleCardSection(
      title: 'Tarefas',
      subtitle: 'Planejamento de visitas, follow-ups e rotas de campo por prioridade.',
      items: const [
        'Agenda semanal por vendedor',
        'Alertas de tarefas vencidas',
        'Roteiro de visitas e checkpoints',
      ],
    );
  }
}

class _TenantWorkspaceHubSection extends StatelessWidget {
  const _TenantWorkspaceHubSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return _SimpleCardSection(
      title: 'Menu da representada',
      subtitle:
          'Use os menus horizontais para acessar detalhes, produtos, promocoes, destaques, politicas e configuracoes da empresa ativa.',
      items: const [
        'Detalhes',
        'Produtos',
        'Promocoes',
        'Destaques',
        'Politicas comerciais',
        'Configuracoes',
      ],
    );
  }
}

class _RepresentedDetailsSection extends StatelessWidget {
  const _RepresentedDetailsSection({
    required this.activeTenant,
    required this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: activeTenant.role,
      workspaceType: activeTenant.workspaceType,
    );
    final selectedId = (selectedRepresentedCompanyId ?? '').trim();
    if (selectedId.isEmpty) {
      return _SimpleCardSection(
        title: 'Informacoes de cadastro',
        subtitle: 'Selecione uma representada no topo para editar os detalhes.',
        items: const [
          'Razao social e nome fantasia',
          'CNPJ, contato e endereco',
          'Segmento e status',
        ],
      );
    }

    return StreamBuilder<List<Map<String, Object?>>>(
      stream: WorkspaceProfileService(FirebaseFirestore.instance)
          .watchRepresentedCompanies(activeTenant.tenantId),
      builder: (context, snapshot) {
        final representedCompanies = _representedCompaniesFromStorage(
          snapshot.data ?? const <Map<String, Object?>>[],
        );

        _RepresentedCompany? selected;
        for (final company in representedCompanies) {
          if (company.id == selectedId) {
            selected = company;
            break;
          }
        }

        if (selected == null) {
          return _SimpleCardSection(
            title: 'Informacoes de cadastro',
            subtitle: 'A representada selecionada nao foi encontrada na base atual.',
            items: const [
              'Valide a representada ativa no topo',
              'Atualize a lista de representadas',
            ],
          );
        }

        final selectedCompany = selected;
        final displayName = selectedCompany.nomeFantasia.isEmpty
            ? (activeRepresentedCompanyName ?? selectedCompany.id)
            : selectedCompany.nomeFantasia;
        final cityUf = selectedCompany.cidade.isEmpty
            ? 'Nao informado'
            : '${selectedCompany.cidade}${selectedCompany.uf.isEmpty ? '' : '/${selectedCompany.uf}'}';

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    _RepresentedCompanyAvatar(company: selectedCompany, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            selectedCompany.cnpj.trim().isEmpty
                                ? 'CNPJ nao cadastrado'
                                : selectedCompany.cnpj,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: canEditSettings
                          ? () => _editRepresentedCompany(context, selectedCompany)
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(canEditSettings ? 'Alterar' : 'Somente leitura'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (!canEditSettings) ...[
                      _ownerOnlyReadOnlyNotice(
                        context,
                        message:
                            'Apenas o owner pode alterar os dados da representada. Este perfil pode apenas consultar.',
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _profileBlock(
                            context,
                            title: 'Contato',
                            rows: [
                              _profileRow(Icons.call_outlined, selectedCompany.telefone, 'Telefone nao cadastrado'),
                              _profileRow(Icons.mail_outline, selectedCompany.email, 'E-mail nao cadastrado'),
                              _profileRow(Icons.badge_outlined, selectedCompany.contato, 'Contato nao cadastrado'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _profileBlock(
                            context,
                            title: 'Cadastro',
                            rows: [
                              _profileLabelValue('Razao social', selectedCompany.razaoSocial),
                              _profileLabelValue('Nome fantasia', selectedCompany.nomeFantasia),
                              _profileLabelValue('CNPJ', selectedCompany.cnpj),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(color: Theme.of(context).dividerColor),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _profileBlock(
                            context,
                            title: 'Endereco',
                            rows: [
                              _profileLabelValue('CEP', selectedCompany.cep),
                              _profileLabelValue('Logradouro', selectedCompany.logradouro),
                              _profileLabelValue('Numero', selectedCompany.numero),
                              _profileLabelValue('Cidade/UF', cityUf),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _profileBlock(
                            context,
                            title: 'Comercial',
                            rows: [
                              _profileLabelValue('Segmento', selectedCompany.segmento),
                              _profileLabelValue('Status', selectedCompany.ativo ? 'Ativa' : 'Inativa'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _profileBlock(
    BuildContext context, {
    required String title,
    required List<Widget> rows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  Widget _profileRow(IconData icon, String value, String fallback) {
    final output = value.trim().isEmpty ? fallback : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(output)),
        ],
      ),
    );
  }

  Widget _profileLabelValue(String label, String value) {
    final output = value.trim().isEmpty ? 'Nao cadastrado' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(output),
        ],
      ),
    );
  }

  Future<void> _editRepresentedCompany(
    BuildContext context,
    _RepresentedCompany company,
  ) async {
    final payload = await _openRepresentedCompanyEditor(context, initial: company);
    if (payload == null || !context.mounted) {
      return;
    }

    try {
      await WorkspaceProfileService(FirebaseFirestore.instance).upsertRepresentedCompany(
        tenantId: activeTenant.tenantId,
        companyId: company.id,
        values: payload,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Representada atualizada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar representada: $error')),
      );
    }
  }
}

class _WorkspaceParametersSection extends StatefulWidget {
  const _WorkspaceParametersSection({required this.activeTenant});

  final TenantEntryOption activeTenant;

  @override
  State<_WorkspaceParametersSection> createState() => _WorkspaceParametersSectionState();
}

class _WorkspaceParametersSectionState extends State<_WorkspaceParametersSection> {
  final WorkspaceProfileService _service = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _service.watchWorkspace(widget.activeTenant.tenantId),
      builder: (context, snapshot) {
        final workspaceData = snapshot.data ?? const <String, dynamic>{};
        final workspaceType = widget.activeTenant.workspaceType;
        final planBaseLabel = _planBaseLabelFromWorkspaceType(workspaceType);
        final planTier = _workspacePlanTier(workspaceData);
        final canUseAdvancedPricing = _isFeatureAvailableByPlan(
          workspaceType: workspaceType,
          planTier: planTier,
          featureKey: _featureAdvancedPricing,
        );
        final advancedPricingEnabled = _featureFlagEnabled(
          workspaceData,
          _featureAdvancedPricing,
          legacyField: 'advancedPricingEnabled',
        ) && canUseAdvancedPricing;
        final showMinimumPriceForTeamEnabled = _featureFlagEnabled(
          workspaceData,
          'showMinimumPriceForTeamEnabled',
        );
        final allowDiscountApprovalOverrideEnabled = _featureFlagEnabled(
          workspaceData,
          'allowDiscountApprovalOverrideEnabled',
        );

        return Stack(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Parametros', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    const Text(
                      'Ajustes de comportamento do modulo comercial para este workspace.',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Plano: $planBaseLabel',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        Chip(
                          label: Text(
                            planTier == _planTierUpgrade ? 'Upgrade ativo' : 'Plano base',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: _planTierBase,
                          label: Text('Base'),
                        ),
                        ButtonSegment<String>(
                          value: _planTierUpgrade,
                          label: Text('Upgrade'),
                        ),
                      ],
                      selected: <String>{planTier},
                      onSelectionChanged: canEditSettings && !_updating
                          ? (values) {
                              if (values.isEmpty) {
                                return;
                              }
                              _setPlanTier(values.first);
                            }
                          : null,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Este seletor representa o nivel do plano e sera controlado pelo billing no futuro.',
                    ),
                    const SizedBox(height: 14),
                    if (!canEditSettings) ...[
                      _ownerOnlyReadOnlyNotice(
                        context,
                        message:
                            'Somente o owner pode alterar parametros deste workspace. Este perfil pode apenas consultar.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    SwitchListTile(
                      value: advancedPricingEnabled,
                      onChanged: canEditSettings && canUseAdvancedPricing && !_updating
                          ? _setAdvancedPricingEnabled
                          : null,
                      title: const Text('Precificacao avancada'),
                      subtitle: Text(
                        canUseAdvancedPricing
                            ? 'Habilita tabelas de preco adicionais para variacoes por estado, regiao, cliente ou campanha.'
                            : 'Disponivel apenas no plano Upgrade.',
                      ),
                    ),
                    const Divider(),
                    SwitchListTile(
                      value: showMinimumPriceForTeamEnabled,
                      onChanged: canEditSettings && !_updating
                          ? (value) => _setFeatureFlag(
                                key: 'showMinimumPriceForTeamEnabled',
                                value: value,
                                enabledMessage: 'Exibicao de preco minimo para equipe ativada.',
                                disabledMessage: 'Exibicao de preco minimo para equipe desativada.',
                              )
                          : null,
                      title: const Text('Exibir preco minimo para equipe'),
                      subtitle: const Text(
                        'Placeholder para politica futura. Sem efeito operacional neste momento.',
                      ),
                    ),
                    const Divider(),
                    SwitchListTile(
                      value: allowDiscountApprovalOverrideEnabled,
                      onChanged: canEditSettings && !_updating
                          ? (value) => _setFeatureFlag(
                                key: 'allowDiscountApprovalOverrideEnabled',
                                value: value,
                                enabledMessage: 'Aprovacao para desconto acima do limite ativada.',
                                disabledMessage: 'Aprovacao para desconto acima do limite desativada.',
                              )
                          : null,
                      title: const Text('Permitir desconto acima do limite com aprovacao'),
                      subtitle: const Text(
                        'Placeholder para fluxo futuro de aprovacao comercial.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      !canUseAdvancedPricing
                          ? 'Status: bloqueada pelo plano atual. Ative o Upgrade para liberar este recurso.'
                          : advancedPricingEnabled
                              ? 'Status: ativa. O submenu de Tabelas de preço fica disponivel em Produtos.'
                              : 'Status: inativa. O submenu de Tabelas de preço fica oculto.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            if (_updating)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          child: Text(
                            'S',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(height: 8),
                        const Text('Atualizando parametros...'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _setAdvancedPricingEnabled(bool enabled) async {
    setState(() {
      _updating = true;
    });

    try {
      await _service.setAdvancedPricingEnabled(
        tenantId: widget.activeTenant.tenantId,
        enabled: enabled,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Precificacao avancada ativada.'
                : 'Precificacao avancada desativada.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar parametro: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }

  Future<void> _setPlanTier(String tier) async {
    setState(() {
      _updating = true;
    });

    try {
      await _service.setWorkspacePlanTier(
        tenantId: widget.activeTenant.tenantId,
        tier: tier,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tier == _planTierUpgrade
                ? 'Nivel do plano atualizado para Upgrade.'
                : 'Nivel do plano atualizado para Base.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar nivel do plano: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }

  Future<void> _setFeatureFlag({
    required String key,
    required bool value,
    required String enabledMessage,
    required String disabledMessage,
  }) async {
    setState(() {
      _updating = true;
    });

    try {
      await _service.updateWorkspaceFeatureFlags(
        tenantId: widget.activeTenant.tenantId,
        flags: {key: value},
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? enabledMessage : disabledMessage)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar parametro: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }
}

class _MediaLibrarySection extends StatefulWidget {
  const _MediaLibrarySection({
    required this.activeTenant,
    required this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_MediaLibrarySection> createState() => _MediaLibrarySectionState();
}

class _MediaLibrarySectionState extends State<_MediaLibrarySection> {
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  bool _uploading = false;

  String get _scopeKey => _normalizeDefaultScopeKey(widget.selectedRepresentedCompanyId);
  String get _scopeLabel => (widget.activeRepresentedCompanyName ?? '').trim().isNotEmpty
      ? widget.activeRepresentedCompanyName!.trim()
      : 'Tenant principal';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _uploadNewAsset() async {
    if (_uploading) {
      return;
    }

    setState(() {
      _uploading = true;
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) {
        return;
      }

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Arquivo de imagem invalido.');
      }

      final decoded = image_lib.decodeImage(bytes);
      if (decoded == null) {
        throw StateError('Formato de imagem invalido.');
      }

      final square = _resizeAndCropToSquare(decoded, 500);
      final processedJpg = Uint8List.fromList(image_lib.encodeJpg(square, quality: 88));
      final id = 'pma_${DateTime.now().toUtc().microsecondsSinceEpoch}';
      final storagePath = 'tenants/${widget.activeTenant.tenantId}/product_media/$_scopeKey/$id.jpg';
      final ref = FirebaseStorage.instance.ref(storagePath);
      await ref.putData(
        processedJpg,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {'origin': 'media-library', 'scope-key': _scopeKey},
        ),
      );

      final downloadUrl = await ref.getDownloadURL();
      final asset = {
        'id': id,
        'tenantId': widget.activeTenant.tenantId,
        'representedCompanyId': widget.selectedRepresentedCompanyId,
        'scopeKey': _scopeKey,
        'fileName': file.name.trim().isEmpty ? '$id.jpg' : file.name.trim(),
        'downloadUrl': downloadUrl,
        'storagePath': storagePath,
        'thumbnailBase64': _buildThumbnailBase64(square),
        'width': 500,
        'height': 500,
        'createdAt': Timestamp.fromDate(DateTime.now().toUtc()),
        'updatedAt': Timestamp.fromDate(DateTime.now().toUtc()),
      };

      await FirebaseFirestore.instance
          .collection('product_media_assets')
          .doc(id)
          .set(asset, SetOptions(merge: true));

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagem enviada com sucesso.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao enviar imagem: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  Future<void> _deleteAsset(Map<String, dynamic> asset) async {
    final id = asset['id'] as String? ?? '';
    final storagePath = ((asset['storagePath'] as String?) ?? '').trim();
    final inUse = await _isAssetInUse(asset);
    if (inUse) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta imagem está em uso por um produto e não pode ser excluída.')),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir imagem?'),
        content: Text('Deseja remover ${asset['fileName']} da biblioteca de fotos?'),
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
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      if (storagePath.isNotEmpty) {
        await FirebaseStorage.instance.ref(storagePath).delete();
      }
      await FirebaseFirestore.instance.collection('product_media_assets').doc(id).delete();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagem removida da biblioteca.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao excluir imagem: $error')),
      );
    }
  }

  Future<bool> _isAssetInUse(Map<String, dynamic> asset) async {
    final tenantId = widget.activeTenant.tenantId;
    final downloadUrl = ((asset['downloadUrl'] as String?) ?? '').trim();
    final storagePath = ((asset['storagePath'] as String?) ?? '').trim();

    final checks = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    if (downloadUrl.isNotEmpty) {
      checks.add(
        FirebaseFirestore.instance
            .collection('produtos')
            .where('tenantId', isEqualTo: tenantId)
            .where('fotoUrl', isEqualTo: downloadUrl)
            .limit(1)
            .get(),
      );
    }
    if (storagePath.isNotEmpty) {
      checks.add(
        FirebaseFirestore.instance
            .collection('produtos')
            .where('tenantId', isEqualTo: tenantId)
            .where('fotoUrl', isEqualTo: storagePath)
            .limit(1)
            .get(),
      );
      checks.add(
        FirebaseFirestore.instance
            .collection('produtos')
            .where('tenantId', isEqualTo: tenantId)
            .where('storagePath', isEqualTo: storagePath)
            .limit(1)
            .get(),
      );
    }

    if (checks.isEmpty) {
      return false;
    }

    final snapshots = await Future.wait(checks);
    for (final snapshot in snapshots) {
      if (snapshot.docs.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  image_lib.Image _resizeAndCropToSquare(image_lib.Image source, int size) {
    final width = source.width;
    final height = source.height;
    final squareSize = width < height ? width : height;
    final offsetX = ((width - squareSize) / 2).round();
    final offsetY = ((height - squareSize) / 2).round();
    final cropped = image_lib.copyCrop(
      source,
      x: offsetX < 0 ? 0 : offsetX,
      y: offsetY < 0 ? 0 : offsetY,
      width: squareSize,
      height: squareSize,
    );
    if (cropped.width == size && cropped.height == size) {
      return cropped;
    }
    return image_lib.copyResize(
      cropped,
      width: size,
      height: size,
      interpolation: image_lib.Interpolation.cubic,
    );
  }

  String _buildThumbnailBase64(image_lib.Image source) {
    final thumb = image_lib.copyResize(
      source,
      width: 96,
      height: 96,
      interpolation: image_lib.Interpolation.average,
    );
    return base64Encode(image_lib.encodeJpg(thumb, quality: 70));
  }

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('product_media_assets')
          .where('tenantId', isEqualTo: widget.activeTenant.tenantId)
          .snapshots(),
      builder: (context, snapshot) {
        final allAssets = (snapshot.data?.docs ?? const [])
            .map((doc) => doc.data())
            .where((asset) {
              final representedCompanyId = (asset['representedCompanyId'] as String? ?? '').trim();
              final scopeKey = (asset['scopeKey'] as String? ?? '').trim();
              final normalizedRepresented = _normalizeDefaultScopeKey(representedCompanyId);
              final matchesScopedCompany = normalizedRepresented == _scopeKey;
              final matchesStoredScope = scopeKey == _scopeKey;
              final matchesLegacyTenantDefault = _scopeKey == 'tenant_default' &&
                  representedCompanyId.isEmpty &&
                  (scopeKey.isEmpty || scopeKey == 'tenant_default');
              final matchesLegacyNoScope = representedCompanyId.isEmpty &&
                  scopeKey.isEmpty &&
                  _scopeKey == 'tenant_default';
              return matchesScopedCompany || matchesStoredScope || matchesLegacyTenantDefault || matchesLegacyNoScope;
            })
            .toList(growable: false)
          ..sort((a, b) {
            final aDate = _readDateTime(a['createdAt']);
            final bDate = _readDateTime(b['createdAt']);
            return bDate.compareTo(aDate);
          });

        final assets = _searchTerm.trim().isEmpty
            ? allAssets
            : allAssets
                .where((asset) => ((asset['fileName'] as String?) ?? '').toLowerCase().contains(_searchTerm.toLowerCase()))
                .toList(growable: false);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Fotos', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text('Gestao de imagens do contexto $_scopeLabel.'),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: canEditSettings && !_uploading ? _uploadNewAsset : null,
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(_uploading ? 'Enviando...' : 'Enviar foto'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchTerm = value),
                  decoration: const InputDecoration(
                    labelText: 'Buscar por nome do arquivo',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                if (assets.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    ),
                    child: Text(
                      allAssets.isEmpty
                          ? 'Nenhuma foto cadastrada para este contexto.'
                          : 'Nenhuma foto encontrada para a busca atual.',
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: assets.length,
                    itemBuilder: (context, index) {
                      final asset = assets[index];
                      final downloadUrl = ((asset['downloadUrl'] as String?) ?? '').trim();
                      final storagePath = ((asset['storagePath'] as String?) ?? '').trim();
                      final fileName = ((asset['fileName'] as String?) ?? 'imagem').trim();
                      final thumbBase64 = (asset['thumbnailBase64'] as String?)?.trim();
                      final previewBytes = thumbBase64 != null && thumbBase64.isNotEmpty
                          ? base64Decode(thumbBase64)
                          : null;

                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: previewBytes != null && previewBytes.isNotEmpty
                                      ? Image.memory(previewBytes, fit: BoxFit.cover)
                                      : (downloadUrl.isNotEmpty
                                          ? Image.network(
                                              downloadUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) =>
                                                  const Icon(Icons.image_outlined, size: 32),
                                            )
                                          : (storagePath.isNotEmpty
                                              ? FutureBuilder<String>(
                                                  future: FirebaseStorage.instance.ref(storagePath).getDownloadURL(),
                                                  builder: (context, snapshot) {
                                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                                      return const Center(
                                                        child: SizedBox(
                                                          width: 18,
                                                          height: 18,
                                                          child: CircularProgressIndicator(strokeWidth: 2),
                                                        ),
                                                      );
                                                    }
                                                    final url = snapshot.data ?? '';
                                                    if (url.isEmpty) {
                                                      return const Icon(Icons.image_outlined, size: 32);
                                                    }
                                                    return Image.network(
                                                      url,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context, error, stackTrace) =>
                                                          const Icon(Icons.image_outlined, size: 32),
                                                    );
                                                  },
                                                )
                                              : const Icon(Icons.image_outlined, size: 32)))
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                tooltip: 'Excluir imagem',
                                onPressed: canEditSettings ? () => _deleteAsset(asset) : null,
                                icon: const Icon(Icons.delete_outline, color: Colors.white),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.42),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CategoriesSection extends StatefulWidget {
  const _CategoriesSection({
    required this.activeTenant,
    required this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_CategoriesSection> createState() => _CategoriesSectionState();
}

class _CategoriesSectionState extends State<_CategoriesSection> {
  final WorkspaceProfileService _service = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );
  final TextEditingController _newCategoryController = TextEditingController();
  List<String> _draftCategories = const [];
  String _loadedScope = '';
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );
    final representedName = (widget.activeRepresentedCompanyName ?? '').trim();
    final scopeLabel = representedName.isEmpty ? widget.activeTenant.tenantName : representedName;

    return StreamBuilder<List<String>>(
      stream: _service.watchRepresentedProductCategories(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: widget.selectedRepresentedCompanyId,
      ),
      builder: (context, snapshot) {
        final scopeKey = _scopeKey();
        final incoming = snapshot.data ?? const <String>[];
        if (_loadedScope != scopeKey || !_dirty) {
          _draftCategories = incoming;
          _loadedScope = scopeKey;
          _dirty = false;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Categorias', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Classificacao usada em filtros, catalogo e regras para $scopeLabel.'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newCategoryController,
                        enabled: canEditSettings && !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Nova categoria',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) {
                          if (!canEditSettings) {
                            return;
                          }
                          _addCategory();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: canEditSettings && !_saving ? _addCategory : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar'),
                    ),
                  ],
                ),
                if (!canEditSettings) ...[
                  const SizedBox(height: 10),
                  _ownerOnlyReadOnlyNotice(
                    context,
                    message:
                        'Categorias ficam em modo somente leitura para este perfil. Apenas o owner pode alterar.',
                  ),
                ],
                const SizedBox(height: 16),
                if (_draftCategories.isEmpty)
                  const Text('Nenhuma categoria criada ainda.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _draftCategories
                        .map(
                          (category) => InputChip(
                            label: Text(category),
                            onDeleted: canEditSettings && !_saving
                                ? () => _removeCategory(category)
                                : null,
                          ),
                        )
                        .toList(growable: false),
                  ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: canEditSettings && !_saving && _dirty ? _save : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Salvando...' : 'Salvar categorias'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _addCategory() {
    final value = _newCategoryController.text.trim();
    if (value.isEmpty) {
      return;
    }

    final exists = _draftCategories.any((item) => item.toLowerCase() == value.toLowerCase());
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Categoria ja existente.')),
      );
      return;
    }

    setState(() {
      _draftCategories = [..._draftCategories, value]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _dirty = true;
      _newCategoryController.clear();
    });
  }

  void _removeCategory(String category) {
    setState(() {
      _draftCategories = _draftCategories.where((item) => item != category).toList(growable: false);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });

    try {
      await _service.updateRepresentedProductCategories(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: widget.selectedRepresentedCompanyId,
        categories: _draftCategories,
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Categorias salvas.')),
      );
      setState(() {
        _dirty = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar categorias: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _scopeKey() {
    final raw = (widget.selectedRepresentedCompanyId ?? '').trim();
    return raw.isEmpty ? 'tenant_default' : raw;
  }
}

class _CommercialAdjustmentsSection extends StatefulWidget {
  const _CommercialAdjustmentsSection({
    required this.activeTenant,
    required this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_CommercialAdjustmentsSection> createState() => _CommercialAdjustmentsSectionState();
}

class _CommercialAdjustmentsSectionState extends State<_CommercialAdjustmentsSection> {
  final WorkspaceProfileService _service = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );
  final List<_CommercialAdjustmentDraftRow> _rows = [];
  String _loadedScope = '';
  bool _initialized = false;
  bool _dirty = false;
  bool _saving = false;

  static const List<String> _adjustmentTypes = <String>['discount', 'addition'];
  static const List<String> _valueTypes = <String>['percent', 'fixed'];
  static const List<String> _scopes = <String>['geral', 'categoria', 'marca', 'produto'];

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );
    final representedName = (widget.activeRepresentedCompanyName ?? '').trim();
    final scopeLabel = representedName.isEmpty ? widget.activeTenant.tenantName : representedName;

    return StreamBuilder<List<CommercialAdjustmentRule>>(
      stream: _service.watchCommercialAdjustmentRules(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: widget.selectedRepresentedCompanyId,
      ),
      builder: (context, snapshot) {
        final incoming = snapshot.data ?? const <CommercialAdjustmentRule>[];
        final scopeKey = _scopeKey();
        if (!_initialized || _loadedScope != scopeKey || !_dirty) {
          _resetRowsFromIncoming(incoming);
          _initialized = true;
          _loadedScope = scopeKey;
          _dirty = false;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Acrescimos e descontos', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Construtor inicial de regras comerciais para $scopeLabel.'),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: canEditSettings && !_saving ? _addRule : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar regra'),
                  ),
                ),
                if (!canEditSettings) ...[
                  const SizedBox(height: 10),
                  _ownerOnlyReadOnlyNotice(
                    context,
                    message:
                        'Regras em modo somente leitura para este perfil. Apenas o owner pode alterar.',
                  ),
                ],
                const SizedBox(height: 10),
                if (_rows.isEmpty)
                  const Text('Nenhuma regra cadastrada.')
                else
                  Column(
                    children: [
                      for (var index = 0; index < _rows.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildRuleRow(index, canEditSettings),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: canEditSettings && !_saving && _dirty ? _save : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Salvando...' : 'Salvar regras'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRuleRow(int index, bool canEditSettings) {
    final row = _rows[index];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.nameController,
                  enabled: canEditSettings && !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Nome da regra',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: canEditSettings && !_saving ? () => _removeRule(index) : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: row.adjustmentType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _adjustmentTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type == 'discount' ? 'Desconto' : 'Acrescimo'),
                        ),
                      )
                      .toList(growable: false),
                    onChanged: !canEditSettings || _saving
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            row.adjustmentType = value;
                            _dirty = true;
                          });
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: row.valueType,
                  decoration: const InputDecoration(
                    labelText: 'Aplicar como',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _valueTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type == 'percent' ? 'Percentual' : 'Valor fixo'),
                        ),
                      )
                      .toList(growable: false),
                    onChanged: !canEditSettings || _saving
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            row.valueType = value;
                            _dirty = true;
                          });
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.valueController,
                  enabled: canEditSettings && !_saving,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: row.valueType == 'percent' ? 'Valor (%)' : 'Valor (R\$)',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: row.scope,
                  decoration: const InputDecoration(
                    labelText: 'Escopo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _scopes
                      .map(
                        (scope) => DropdownMenuItem(
                          value: scope,
                          child: Text(scope[0].toUpperCase() + scope.substring(1)),
                        ),
                      )
                      .toList(growable: false),
                    onChanged: !canEditSettings || _saving
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            row.scope = value;
                            _dirty = true;
                          });
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: row.scopeTargetController,
                  enabled: canEditSettings && !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Alvo do escopo (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _markDirty() {
    if (_dirty) {
      return;
    }
    setState(() {
      _dirty = true;
    });
  }

  void _addRule() {
    setState(() {
      _rows.add(_CommercialAdjustmentDraftRow());
      _dirty = true;
    });
  }

  void _removeRule(int index) {
    setState(() {
      _rows.removeAt(index).dispose();
      _dirty = true;
    });
  }

  void _resetRowsFromIncoming(List<CommercialAdjustmentRule> incoming) {
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(
        incoming.map(
          (rule) => _CommercialAdjustmentDraftRow(
            name: rule.name,
            adjustmentType: rule.adjustmentType,
            valueType: rule.valueType,
            value: _formatValue(rule.value),
            scope: rule.scope,
            scopeTarget: rule.scopeTarget,
          ),
        ),
      );
  }

  String _formatValue(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _parseValue(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    final withDot = normalized.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(withDot) ?? double.tryParse(normalized.replaceAll(',', '.')) ?? 0;
  }

  Future<void> _save() async {
    final rules = _rows
        .map(
          (row) => CommercialAdjustmentRule(
            name: row.nameController.text.trim(),
            adjustmentType: row.adjustmentType,
            valueType: row.valueType,
            value: _parseValue(row.valueController.text),
            scope: row.scope,
            scopeTarget: row.scopeTargetController.text.trim(),
          ),
        )
        .where((rule) => rule.name.isNotEmpty)
        .toList(growable: false);

    setState(() {
      _saving = true;
    });

    try {
      await _service.updateCommercialAdjustmentRules(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: widget.selectedRepresentedCompanyId,
        rules: rules,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Regras de acrescimos e descontos salvas.')),
      );
      setState(() {
        _dirty = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar regras: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _scopeKey() {
    final raw = (widget.selectedRepresentedCompanyId ?? '').trim();
    return raw.isEmpty ? 'tenant_default' : raw;
  }
}

class _CommercialAdjustmentDraftRow {
  _CommercialAdjustmentDraftRow({
    String name = '',
    this.adjustmentType = 'discount',
    this.valueType = 'percent',
    String value = '',
    this.scope = 'geral',
    String scopeTarget = '',
  })  : nameController = TextEditingController(text: name),
        valueController = TextEditingController(text: value),
        scopeTargetController = TextEditingController(text: scopeTarget);

  final TextEditingController nameController;
  final TextEditingController valueController;
  final TextEditingController scopeTargetController;
  String adjustmentType;
  String valueType;
  String scope;

  void dispose() {
    nameController.dispose();
    valueController.dispose();
    scopeTargetController.dispose();
  }
}

class _RepresentedCompany {
  const _RepresentedCompany({
    required this.id,
    required this.nomeFantasia,
    required this.razaoSocial,
    required this.cnpj,
    required this.cep,
    required this.logradouro,
    required this.numero,
    required this.logoUrl,
    required this.contato,
    required this.telefone,
    required this.email,
    required this.cidade,
    required this.uf,
    required this.segmento,
    required this.ativo,
  });

  final String id;
  final String nomeFantasia;
  final String razaoSocial;
  final String cnpj;
  final String cep;
  final String logradouro;
  final String numero;
  final String logoUrl;
  final String contato;
  final String telefone;
  final String email;
  final String cidade;
  final String uf;
  final String segmento;
  final bool ativo;
}

List<_RepresentedCompany> _representedCompaniesFromStorage(
  List<Map<String, Object?>> storedCompanies,
) {
  final result = <_RepresentedCompany>[];

  for (final rawCompany in storedCompanies) {
    final company = _representedCompanyFromMap(rawCompany);
    if (company != null) {
      result.add(company);
    }
  }

  result.sort(
    (a, b) => a.nomeFantasia.toLowerCase().compareTo(b.nomeFantasia.toLowerCase()),
  );
  return result;
}

_RepresentedCompany? _representedCompanyFromMap(Map<String, Object?> map) {
  final id = (map['companyId'] ?? map['id'] ?? '').toString().trim();
  if (id.isEmpty) {
    return null;
  }

  return _RepresentedCompany(
    id: id,
    nomeFantasia: (map['nomeFantasia'] ?? '').toString(),
    razaoSocial: (map['razaoSocial'] ?? '').toString(),
    cnpj: (map['cnpj'] ?? '').toString(),
    cep: (map['cep'] ?? '').toString(),
    logradouro: (map['logradouro'] ?? '').toString(),
    numero: (map['numero'] ?? '').toString(),
    logoUrl: (map['logoUrl'] ?? '').toString(),
    contato: (map['contato'] ?? '').toString(),
    telefone: (map['telefone'] ?? '').toString(),
    email: (map['email'] ?? '').toString(),
    cidade: (map['cidade'] ?? '').toString(),
    uf: (map['uf'] ?? '').toString(),
    segmento: (map['segmento'] ?? '').toString(),
    ativo: map['ativo'] == true,
  );
}

class _RepresentedCompanyAvatar extends StatelessWidget {
  const _RepresentedCompanyAvatar({
    required this.company,
    this.size = 24,
  });

  final _RepresentedCompany company;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logoUrl = company.logoUrl.trim();
    final trimmedName = company.nomeFantasia.trim();
    final initial = trimmedName.isEmpty ? 'R' : trimmedName.substring(0, 1).toUpperCase();
    final dataBytes = _decodeDataUrlImageBytes(logoUrl);
    ImageProvider<Object>? imageProvider;

    if (dataBytes != null) {
      imageProvider = MemoryImage(dataBytes);
    } else if (logoUrl.isNotEmpty) {
      imageProvider = NetworkImage(logoUrl);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        image: imageProvider == null
            ? null
            : DecorationImage(image: imageProvider, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: imageProvider == null
          ? Text(
              initial,
              style: TextStyle(fontSize: size * 0.42),
            )
          : null,
    );
  }
}

Uint8List? _decodeDataUrlImageBytes(String value) {
  final normalized = value.trim();
  if (!normalized.startsWith('data:image/')) {
    return null;
  }

  final marker = ';base64,';
  final index = normalized.indexOf(marker);
  if (index == -1) {
    return null;
  }

  final encoded = normalized.substring(index + marker.length);
  try {
    return base64Decode(encoded);
  } catch (_) {
    return null;
  }
}

Future<String?> _pickAndResizeLogoDataUrl() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
    allowMultiple: false,
  );

  final files = result?.files;
  if (files == null || files.isEmpty) {
    return null;
  }

  final file = files.first;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    return null;
  }

  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) {
    return null;
  }

  var resized = decoded;
  if (decoded.width > 256 || decoded.height > 256) {
    final width = decoded.width;
    final height = decoded.height;
    if (width >= height) {
      resized = image_lib.copyResize(decoded, width: 256);
    } else {
      resized = image_lib.copyResize(decoded, height: 256);
    }
  }

  final pngBytes = image_lib.encodePng(resized);
  return 'data:image/png;base64,${base64Encode(pngBytes)}';
}

Future<Map<String, Object?>?> _openRepresentedCompanyEditor(
  BuildContext context, {
  _RepresentedCompany? initial,
}) async {
  final nomeFantasiaController = TextEditingController(
    text: initial?.nomeFantasia ?? '',
  );
  final razaoSocialController = TextEditingController(
    text: initial?.razaoSocial ?? '',
  );
  final cnpjController = TextEditingController(text: initial?.cnpj ?? '');
  final cepController = TextEditingController(text: initial?.cep ?? '');
  final logradouroController = TextEditingController(text: initial?.logradouro ?? '');
  final numeroController = TextEditingController(text: initial?.numero ?? '');
  final contatoController = TextEditingController(text: initial?.contato ?? '');
  final telefoneController = TextEditingController(text: initial?.telefone ?? '');
  final emailController = TextEditingController(text: initial?.email ?? '');
  final cidadeController = TextEditingController(text: initial?.cidade ?? '');
  final ufController = TextEditingController(text: initial?.uf ?? '');
  final segmentoController = TextEditingController(text: initial?.segmento ?? '');
  var ativo = initial?.ativo ?? true;
  var logoData = initial?.logoUrl ?? '';
  var buscandoCep = false;

  Future<void> buscarCep(StateSetter setDialogState) async {
    final cep = cepController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe um CEP valido com 8 digitos.')),
        );
      }
      return;
    }

    setDialogState(() {
      buscandoCep = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://brasilapi.com.br/api/cep/v2/$cep'),
      );
      if (response.statusCode != 200) {
        throw StateError('cep_lookup_error');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final city = (data['city'] ?? data['cidade'] ?? '').toString().trim();
      final state = (data['state'] ?? data['uf'] ?? '').toString().trim();
      final street = (data['street'] ?? data['logradouro'] ?? '').toString().trim();

      if (street.isNotEmpty) {
        logradouroController.text = street;
      }

      if (city.isNotEmpty) {
        cidadeController.text = city;
      }
      if (state.isNotEmpty) {
        ufController.text = state.toUpperCase();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Endereco localizado pelo CEP.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nao foi possivel consultar esse CEP agora.')),
        );
      }
    } finally {
      setDialogState(() {
        buscandoCep = false;
      });
    }
  }

  final shouldSave = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text(
              initial == null ? 'Nova empresa representada' : 'Editar representada',
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nomeFantasiaController,
                      decoration: const InputDecoration(
                        labelText: 'Nome fantasia',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: razaoSocialController,
                      decoration: const InputDecoration(
                        labelText: 'Razao social',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cnpjController,
                      decoration: const InputDecoration(
                        labelText: 'CNPJ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contatoController,
                      decoration: const InputDecoration(
                        labelText: 'Contato',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: telefoneController,
                      decoration: const InputDecoration(
                        labelText: 'Telefone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: logradouroController,
                            decoration: const InputDecoration(
                              labelText: 'Logradouro',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: numeroController,
                            decoration: const InputDecoration(
                              labelText: 'Numero',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: cepController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'CEP',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: buscandoCep
                              ? null
                              : () => buscarCep(setDialogState),
                          icon: buscandoCep
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search),
                          label: Text(buscandoCep ? 'Buscando...' : 'Buscar CEP'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: cidadeController,
                            decoration: const InputDecoration(
                              labelText: 'Cidade',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: ufController,
                            decoration: const InputDecoration(
                              labelText: 'UF',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: segmentoController,
                      decoration: const InputDecoration(
                        labelText: 'Segmento',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _RepresentedCompanyAvatar(
                          company: _RepresentedCompany(
                            id: initial?.id ?? 'preview',
                            nomeFantasia: nomeFantasiaController.text,
                            razaoSocial: razaoSocialController.text,
                            cnpj: cnpjController.text,
                            cep: cepController.text,
                            logradouro: logradouroController.text,
                            numero: numeroController.text,
                            logoUrl: logoData,
                            contato: contatoController.text,
                            telefone: telefoneController.text,
                            email: emailController.text,
                            cidade: cidadeController.text,
                            uf: ufController.text,
                            segmento: segmentoController.text,
                            ativo: ativo,
                          ),
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final pickedData = await _pickAndResizeLogoDataUrl();
                                  if (pickedData == null) {
                                    return;
                                  }
                                  setDialogState(() {
                                    logoData = pickedData;
                                  });
                                },
                                icon: const Icon(Icons.upload_file_outlined),
                                label: const Text('Enviar logo'),
                              ),
                              if (logoData.trim().isNotEmpty)
                                TextButton.icon(
                                  onPressed: () {
                                    setDialogState(() {
                                      logoData = '';
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Remover logo'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'A imagem e redimensionada automaticamente para uso no seletor.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ativa'),
                      value: ativo,
                      onChanged: (value) {
                        setDialogState(() {
                          ativo = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      );
    },
  );

  final nomeFantasia = nomeFantasiaController.text.trim();
  final razaoSocial = razaoSocialController.text.trim();
  final cnpj = cnpjController.text.trim();
  final cep = cepController.text.trim();
  final logradouro = logradouroController.text.trim();
  final numero = numeroController.text.trim();
  final logoUrl = logoData.trim();
  final contato = contatoController.text.trim();
  final telefone = telefoneController.text.trim();
  final email = emailController.text.trim();
  final cidade = cidadeController.text.trim();
  final uf = ufController.text.trim();
  final segmento = segmentoController.text.trim();

  nomeFantasiaController.dispose();
  razaoSocialController.dispose();
  cnpjController.dispose();
  cepController.dispose();
  logradouroController.dispose();
  numeroController.dispose();
  contatoController.dispose();
  telefoneController.dispose();
  emailController.dispose();
  cidadeController.dispose();
  ufController.dispose();
  segmentoController.dispose();

  if (shouldSave != true) {
    return null;
  }

  if (nomeFantasia.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe ao menos o nome fantasia.')),
      );
    }
    return null;
  }

  return {
    'nomeFantasia': nomeFantasia,
    'razaoSocial': razaoSocial,
    'cnpj': cnpj,
    'cep': cep,
    'logradouro': logradouro,
    'numero': numero,
    'logoUrl': logoUrl,
    'contato': contato,
    'telefone': telefone,
    'email': email,
    'cidade': cidade,
    'uf': uf,
    'segmento': segmento,
    'ativo': ativo,
  };
}

String _workspaceTypeLabel(String workspaceType) {
  switch (workspaceType.trim()) {
    case 'seller_solo_workspace':
      return 'Individual';
    case 'rep_workspace':
      return 'Representacoes';
    case 'brand_owner_workspace':
      return 'Empresa';
    default:
      return workspaceType;
  }
}

String _accountContractLockLabel(AccountContractLock accountContractLock) {
  switch (accountContractLock) {
    case AccountContractLock.enterpriseOnly:
      return 'Conta BrandOp';
    case AccountContractLock.flexible:
      return 'Conta MultiOp';
  }
}

String _roleLabel(String role, String workspaceType, String tenantName) {
  final normalizedRole = role.trim().toLowerCase();
  final normalizedWorkspaceType = workspaceType.trim();
  final labelTenantName = tenantName.trim();

  if (normalizedRole == 'platform_admin') {
    return 'Administrador da plataforma';
  }

  if (normalizedWorkspaceType == 'seller_solo_workspace') {
    switch (normalizedRole) {
      case 'vendedor':
        return 'Vendedor Individual';
      case 'representante':
        return 'Representante Individual';
      case 'gerente':
        return 'Gerente Individual';
      case 'owner':
        return 'Administrador Individual';
      default:
        return role;
    }
  }

  final suffix = labelTenantName.isEmpty ? '' : ' da $labelTenantName';
  switch (normalizedRole) {
    case 'owner':
      return 'Administrador$suffix';
    case 'gerente':
      return 'Gerente$suffix';
    case 'representante':
      return 'Representante$suffix';
    case 'vendedor':
      return 'Vendedor$suffix';
    default:
      return role;
  }
}

class _PaymentConditionsSection extends StatefulWidget {
  const _PaymentConditionsSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  State<_PaymentConditionsSection> createState() => _PaymentConditionsSectionState();
}

class _PaymentConditionsSectionState extends State<_PaymentConditionsSection> {
  final WorkspaceProfileService _service = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );
  final List<_PaymentConditionDraftRow> _rows = [];
  bool _initialized = false;
  bool _saving = false;
  String? _loadedTenantId;

  @override
  void didUpdateWidget(covariant _PaymentConditionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTenant.tenantId != widget.activeTenant.tenantId) {
      _clearControllers();
      _initialized = false;
      _loadedTenantId = null;
    }
  }

  @override
  void dispose() {
    _clearControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final representedName = widget.activeRepresentedCompanyName?.trim() ?? '';
    final canEditRules = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Condicoes de pagamento', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          representedName.isEmpty
              ? 'Cadastre as condicoes com descricao e valor minimo para elegibilidade no pedido.'
              : 'Cadastre as condicoes com descricao e valor minimo para a representada $representedName.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: StreamBuilder<List<PaymentConditionRule>>(
              stream: _service.watchPaymentConditionRules(
                tenantId: widget.activeTenant.tenantId,
              ),
              builder: (context, snapshot) {
                final rules = snapshot.data ?? const <PaymentConditionRule>[];
                if (!_initialized || _loadedTenantId != widget.activeTenant.tenantId) {
                  _syncControllers(rules);
                  _initialized = true;
                  _loadedTenantId = widget.activeTenant.tenantId;
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Condicoes de pagamento',
                                style: textTheme.titleMedium,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: canEditRules && !_saving ? _addRule : null,
                              icon: const Icon(Icons.add),
                              label: const Text('Nova condicao de pagamento'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Cada linha deve ter descricao e valor minimo para habilitar a condicao no pedido.',
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Descricao',
                                  style: textTheme.labelLarge,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 150,
                                child: Text(
                                  'Valor minimo',
                                  style: textTheme.labelLarge,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              const SizedBox(width: 44),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_rows.isEmpty)
                          const Text('Nenhuma condicao criada ainda.')
                        else
                          Column(
                            children: [
                              for (var index = 0; index < _rows.length; index++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final compact = constraints.maxWidth < 760;
                                      if (compact) {
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            TextField(
                                              controller: _rows[index].descriptionController,
                                              enabled: canEditRules && !_saving,
                                              decoration: const InputDecoration(
                                                labelText: 'Descricao *',
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller: _rows[index].minimumValueController,
                                                    enabled: canEditRules && !_saving,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    textAlign: TextAlign.right,
                                                    decoration: const InputDecoration(
                                                      labelText: 'Valor minimo',
                                                      prefixText: 'R\$ ',
                                                      isDense: true,
                                                      border: OutlineInputBorder(),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Tooltip(
                                                  message: 'Remover linha',
                                                  child: IconButton.outlined(
                                                    onPressed: canEditRules && !_saving
                                                        ? () => _removeRule(index)
                                                        : null,
                                                    icon: const Icon(Icons.delete_outline),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      }

                                      return Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _rows[index].descriptionController,
                                              enabled: canEditRules && !_saving,
                                              decoration: const InputDecoration(
                                                labelText: 'Descricao *',
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          SizedBox(
                                            width: 150,
                                            child: TextField(
                                              controller: _rows[index].minimumValueController,
                                              enabled: canEditRules && !_saving,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              textAlign: TextAlign.right,
                                              decoration: const InputDecoration(
                                                labelText: 'Valor minimo',
                                                prefixText: 'R\$ ',
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Tooltip(
                                            message: 'Remover linha',
                                            child: IconButton.outlined(
                                              onPressed: canEditRules && !_saving
                                                  ? () => _removeRule(index)
                                                  : null,
                                              icon: const Icon(Icons.delete_outline),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        if (!canEditRules)
                          const Text(
                            'Esta conta esta em modo somente leitura. Apenas o owner pode alterar condicoes de pagamento.',
                          ),
                        if (canEditRules) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _saveRules,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(_saving ? 'Salvando...' : 'Salvar condicoes'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _syncControllers(List<PaymentConditionRule> rules) {
    _clearControllers();
    if (rules.isEmpty) {
      _rows.add(_PaymentConditionDraftRow());
      return;
    }

    for (final rule in rules) {
      _rows.add(
        _PaymentConditionDraftRow(
          description: rule.description,
          minimumValue: _formatMoney(rule.minimumValue),
        ),
      );
    }
  }

  void _addRule() {
    setState(() {
      _rows.add(_PaymentConditionDraftRow());
    });
  }

  void _removeRule(int index) {
    if (_rows.length == 1) {
      _rows.first.descriptionController.clear();
      _rows.first.minimumValueController.text = '0,00';
      return;
    }

    setState(() {
      _rows.removeAt(index).dispose();
    });
  }

  Future<void> _saveRules() async {
    final values = _rows
        .map((row) => PaymentConditionRule(
              description: row.descriptionController.text.trim(),
              minimumValue: _parseMoney(row.minimumValueController.text),
            ))
        .where((rule) => rule.description.isNotEmpty)
        .toList(growable: false);

    if (values.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe ao menos uma condicao com descricao.')),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.updatePaymentConditionRules(
        tenantId: widget.activeTenant.tenantId,
        values: values,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Condicoes de pagamento salvas.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar condicoes: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _clearControllers() {
    for (final row in _rows) {
      row.dispose();
    }
    _rows.clear();
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _parseMoney(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return 0;
    }

    final withDotDecimal = normalized.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(withDotDecimal) ?? double.tryParse(normalized.replaceAll(',', '.')) ?? 0;
  }
}

class _PaymentConditionDraftRow {
  _PaymentConditionDraftRow({
    String description = '',
    String minimumValue = '0,00',
  })  : descriptionController = TextEditingController(text: description),
        minimumValueController = TextEditingController(text: minimumValue);

  final TextEditingController descriptionController;
  final TextEditingController minimumValueController;

  void dispose() {
    descriptionController.dispose();
    minimumValueController.dispose();
  }
}

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
      userLabel: (userLabel == null || userLabel.isEmpty) ? 'Portal' : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace: activeTenant.workspaceType == 'seller_solo_workspace',
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
      title: 'Politicas comerciais',
      subtitle: 'Limites, aprovacoes e travas da empresa ativa.',
      items: const [
        'Limites por perfil',
        'Aprovacoes fora da curva',
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
      title: 'ERP e integracoes',
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
        ? ' Representada ativa: nao selecionada.'
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
      userLabel: (userLabel == null || userLabel.isEmpty) ? 'Portal' : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace: activeTenant.workspaceType == 'seller_solo_workspace',
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
            Text(
              module.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
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

Future<void> _openWorkspaceProfileEditor(
  BuildContext context,
  TenantEntryOption activeTenant,
  Map<String, dynamic> workspaceData,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _WorkspaceProfileEditorDialog(
      activeTenant: activeTenant,
      workspaceData: workspaceData,
    ),
  );

  if (result != true || !context.mounted) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Dados do workspace atualizados com sucesso.')),
  );
}

bool _canEditWorkspaceProfile({
  required String role,
  required String workspaceType,
}) {
  final normalizedRole = role.trim().toLowerCase();
  final normalizedWorkspaceType = workspaceType.trim();

  if (normalizedWorkspaceType == 'brand_owner_workspace') {
    return normalizedRole == 'owner';
  }

  if (normalizedWorkspaceType == 'rep_workspace') {
    return normalizedRole == 'owner';
  }

  return normalizedRole == 'vendedor';
}

bool _canEditRepresentedModuleSettings({
  required String role,
  required String workspaceType,
}) {
  final normalizedRole = role.trim().toLowerCase();
  final normalizedWorkspaceType = workspaceType.trim();

  if (normalizedWorkspaceType == 'seller_solo_workspace' ||
      normalizedWorkspaceType == 'rep_workspace') {
    return normalizedRole == 'owner';
  }

  return false;
}

Widget _ownerOnlyReadOnlyNotice(
  BuildContext context, {
  required String message,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      border: Border.all(color: colorScheme.outlineVariant),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

bool _featureFlagEnabled(
  Map<String, dynamic> workspaceData,
  String key, {
  String? legacyField,
}) {
  final flags = workspaceData['featureFlags'];
  if (flags is Map) {
    final raw = flags[key];
    if (raw is bool) {
      return raw;
    }
  }

  if (legacyField != null) {
    return workspaceData[legacyField] == true;
  }

  return false;
}

String _workspacePlanTier(Map<String, dynamic> workspaceData) {
  final raw = (workspaceData['planTier'] ?? '').toString().trim().toLowerCase();
  if (raw == _planTierUpgrade) {
    return _planTierUpgrade;
  }
  return _planTierBase;
}

bool _isFeatureAvailableByPlan({
  required String workspaceType,
  required String planTier,
  required String featureKey,
}) {
  final byWorkspace = _workspacePlanFeatureMatrix[workspaceType.trim()];
  if (byWorkspace == null) {
    return false;
  }
  final byTier = byWorkspace[planTier.trim().toLowerCase()];
  if (byTier == null) {
    return false;
  }
  return byTier.contains(featureKey);
}

String _planBaseLabelFromWorkspaceType(String workspaceType) {
  switch (workspaceType.trim()) {
    case 'seller_solo_workspace':
      return 'Individual';
    case 'rep_workspace':
      return 'Representacoes';
    case 'brand_owner_workspace':
      return 'Enterprise';
    default:
      return 'Plano desconhecido';
  }
}

bool _canManageRepresentedCompanies({
  required String role,
  required String workspaceType,
}) {
  final normalizedRole = role.trim().toLowerCase();
  final normalizedWorkspaceType = workspaceType.trim();

  if (normalizedWorkspaceType == 'brand_owner_workspace') {
    return false;
  }

  if (normalizedWorkspaceType == 'seller_solo_workspace') {
    return normalizedRole == 'owner' ||
        normalizedRole == 'gerente' ||
        normalizedRole == 'representante' ||
        normalizedRole == 'vendedor';
  }

  if (normalizedWorkspaceType == 'rep_workspace') {
    return normalizedRole == 'owner';
  }

  return false;
}

List<_WorkspaceInfoItem> _buildWorkspaceInfoItems({
  required TenantEntryOption activeTenant,
  required AccountContractLock accountContractLock,
  required Map<String, dynamic> workspaceData,
}) {
  final items = <_WorkspaceInfoItem>[
    _WorkspaceInfoItem(
      label: 'Tipo de conta',
      value: _accountContractLockLabel(accountContractLock),
    ),
    _WorkspaceInfoItem(
      label: 'Workspace',
      value: _workspaceTypeLabel(activeTenant.workspaceType),
    ),
    _WorkspaceInfoItem(
      label: 'Seu acesso atual',
      value: _roleLabel(
        activeTenant.role,
        activeTenant.workspaceType,
        activeTenant.tenantName,
      ),
    ),
    _WorkspaceInfoItem(
      label: 'Identificador interno',
      value: activeTenant.tenantId,
    ),
  ];

  void addEditable(String label, String key) {
    items.add(
      _WorkspaceInfoItem(
        label: label,
        value: (workspaceData[key] ?? '').toString(),
      ),
    );
  }

  void addReadonly(String label, String value) {
    items.add(
      _WorkspaceInfoItem(
        label: label,
        value: value,
      ),
    );
  }

  if (activeTenant.workspaceType == 'brand_owner_workspace') {
    addReadonly('Razao social', (workspaceData['razaoSocial'] ?? '').toString());
    addReadonly('CNPJ', (workspaceData['cnpj'] ?? '').toString());
    addEditable('Nome exibido no SaaS', 'nomeFantasia');
    addEditable('Responsavel principal', 'contatoResponsavel');
    addEditable('Telefone comercial', 'telefoneComercial');
    addEditable('E-mail comercial', 'emailComercial');
    addEditable('Website', 'website');
    addEditable('Logradouro', 'logradouro');
    addEditable('Numero', 'numero');
    addEditable('Complemento', 'complemento');
    addEditable('Bairro', 'bairro');
    addEditable('CEP', 'cep');
    addEditable('Cidade', 'cidade');
    addEditable('UF', 'uf');
    return items;
  }

  if (activeTenant.workspaceType == 'rep_workspace') {
    addReadonly(
      'Documento informado no cadastro',
      (workspaceData['representedCompanyDocument'] ?? '').toString(),
    );
    addEditable('Nome exibido no SaaS', 'nomeFantasia');
    addEditable('Responsavel principal', 'contatoResponsavel');
    addEditable('Telefone comercial', 'telefoneComercial');
    addEditable('E-mail comercial', 'emailComercial');
    addEditable('Regiao de atuacao', 'regiaoAtuacao');
    addEditable('Marcas representadas', 'marcasRepresentadas');
    addEditable('Cidade', 'cidade');
    addEditable('UF', 'uf');
    return items;
  }

  addEditable('Nome exibido no SaaS', 'nomeFantasia');
  addEditable('Nome profissional', 'contatoResponsavel');
  addEditable('Telefone', 'telefoneComercial');
  addEditable('E-mail de contato', 'emailComercial');
  addEditable('Segmento', 'segmento');
  addEditable('Cidade', 'cidade');
  addEditable('UF', 'uf');
  return items;
}

class _WorkspaceInfoItem {
  const _WorkspaceInfoItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _WorkspaceInfoGrid extends StatelessWidget {
  const _WorkspaceInfoGrid({required this.items});

  final List<_WorkspaceInfoItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 2 : 1;
        final rows = <List<_WorkspaceInfoItem>>[];

        for (var index = 0; index < items.length; index += columns) {
          final end = (index + columns) > items.length
              ? items.length
              : (index + columns);
          rows.add(items.sublist(index, end));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows
              .map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < row.length; index++) ...[
                        Expanded(child: _WorkspaceInfoText(item: row[index])),
                        if (index < row.length - 1) const SizedBox(width: 24),
                      ],
                      if (row.length < columns) const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _WorkspaceInfoText extends StatelessWidget {
  const _WorkspaceInfoText({required this.item});

  final _WorkspaceInfoItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 4),
        Text(
          item.value.isEmpty ? 'Nao informado' : item.value,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _WorkspaceProfileEditorDialog extends StatefulWidget {
  const _WorkspaceProfileEditorDialog({
    required this.activeTenant,
    required this.workspaceData,
  });

  final TenantEntryOption activeTenant;
  final Map<String, dynamic> workspaceData;

  @override
  State<_WorkspaceProfileEditorDialog> createState() =>
      _WorkspaceProfileEditorDialogState();
}

class _WorkspaceProfileEditorDialogState
    extends State<_WorkspaceProfileEditorDialog> {
  late final TextEditingController _nomeFantasiaController;
  late final TextEditingController _contatoResponsavelController;
  late final TextEditingController _telefoneComercialController;
  late final TextEditingController _emailComercialController;
  late final TextEditingController _websiteController;
  late final TextEditingController _segmentoController;
  late final TextEditingController _regiaoAtuacaoController;
  late final TextEditingController _marcasRepresentadasController;
  late final TextEditingController _logradouroController;
  late final TextEditingController _numeroController;
  late final TextEditingController _complementoController;
  late final TextEditingController _bairroController;
  late final TextEditingController _cepController;
  late final TextEditingController _cidadeController;
  late final TextEditingController _ufController;
  bool _saving = false;
  bool _buscandoCep = false;

  @override
  void initState() {
    super.initState();
    final data = widget.workspaceData;
    _nomeFantasiaController = TextEditingController(text: (data['nomeFantasia'] ?? '').toString());
    _contatoResponsavelController = TextEditingController(text: (data['contatoResponsavel'] ?? '').toString());
    _telefoneComercialController = TextEditingController(text: (data['telefoneComercial'] ?? '').toString());
    _emailComercialController = TextEditingController(text: (data['emailComercial'] ?? '').toString());
    _websiteController = TextEditingController(text: (data['website'] ?? '').toString());
    _segmentoController = TextEditingController(text: (data['segmento'] ?? '').toString());
    _regiaoAtuacaoController = TextEditingController(text: (data['regiaoAtuacao'] ?? '').toString());
    _marcasRepresentadasController = TextEditingController(text: (data['marcasRepresentadas'] ?? '').toString());
    _logradouroController = TextEditingController(text: (data['logradouro'] ?? '').toString());
    _numeroController = TextEditingController(text: (data['numero'] ?? '').toString());
    _complementoController = TextEditingController(text: (data['complemento'] ?? '').toString());
    _bairroController = TextEditingController(text: (data['bairro'] ?? '').toString());
    _cepController = TextEditingController(text: (data['cep'] ?? '').toString());
    _cidadeController = TextEditingController(text: (data['cidade'] ?? '').toString());
    _ufController = TextEditingController(text: (data['uf'] ?? '').toString());
  }

  @override
  void dispose() {
    _nomeFantasiaController.dispose();
    _contatoResponsavelController.dispose();
    _telefoneComercialController.dispose();
    _emailComercialController.dispose();
    _websiteController.dispose();
    _segmentoController.dispose();
    _regiaoAtuacaoController.dispose();
    _marcasRepresentadasController.dispose();
    _logradouroController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cepController.dispose();
    _cidadeController.dispose();
    _ufController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnterprise = widget.activeTenant.workspaceType == 'brand_owner_workspace';
    final isRep = widget.activeTenant.workspaceType == 'rep_workspace';

    return AlertDialog(
      title: const Text('Editar dados do workspace'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nomeFantasiaController,
                decoration: const InputDecoration(
                  labelText: 'Nome exibido no SaaS',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contatoResponsavelController,
                decoration: const InputDecoration(
                  labelText: 'Responsavel principal',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _telefoneComercialController,
                decoration: const InputDecoration(
                  labelText: 'Telefone comercial',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailComercialController,
                decoration: const InputDecoration(
                  labelText: 'E-mail comercial',
                  border: OutlineInputBorder(),
                ),
              ),
              if (isEnterprise) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _websiteController,
                  decoration: const InputDecoration(
                    labelText: 'Website',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _logradouroController,
                  decoration: const InputDecoration(
                    labelText: 'Logradouro',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _numeroController,
                        decoration: const InputDecoration(
                          labelText: 'Numero',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _complementoController,
                        decoration: const InputDecoration(
                          labelText: 'Complemento',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bairroController,
                  decoration: const InputDecoration(
                    labelText: 'Bairro',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cepController,
                        decoration: const InputDecoration(
                          labelText: 'CEP',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: _buscandoCep ? 'Buscando CEP...' : 'Buscar CEP',
                      child: SizedBox(
                        height: 56,
                        width: 56,
                        child: FilledButton.tonal(
                          onPressed: _saving || _buscandoCep ? null : _buscarCep,
                          child: _buscandoCep
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cidadeController,
                        decoration: const InputDecoration(
                          labelText: 'Cidade',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _ufController,
                        decoration: const InputDecoration(
                          labelText: 'UF',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (isRep) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _regiaoAtuacaoController,
                  decoration: const InputDecoration(
                    labelText: 'Regiao de atuacao',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _marcasRepresentadasController,
                  decoration: const InputDecoration(
                    labelText: 'Marcas representadas',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cidadeController,
                        decoration: const InputDecoration(
                          labelText: 'Cidade',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _ufController,
                        decoration: const InputDecoration(
                          labelText: 'UF',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _segmentoController,
                  decoration: const InputDecoration(
                    labelText: 'Segmento',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cidadeController,
                        decoration: const InputDecoration(
                          labelText: 'Cidade',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _ufController,
                        decoration: const InputDecoration(
                          labelText: 'UF',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Salvando...' : 'Salvar'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });

    try {
      await WorkspaceProfileService(FirebaseFirestore.instance)
          .updateWorkspaceProfile(
        tenantId: widget.activeTenant.tenantId,
        workspaceType: widget.activeTenant.workspaceType,
        values: {
          'nomeFantasia': _nomeFantasiaController.text,
          'contatoResponsavel': _contatoResponsavelController.text,
          'telefoneComercial': _telefoneComercialController.text,
          'emailComercial': _emailComercialController.text,
          'website': _websiteController.text,
          'segmento': _segmentoController.text,
          'regiaoAtuacao': _regiaoAtuacaoController.text,
          'marcasRepresentadas': _marcasRepresentadasController.text,
          'logradouro': _logradouroController.text,
          'numero': _numeroController.text,
          'complemento': _complementoController.text,
          'bairro': _bairroController.text,
          'cep': _cepController.text,
          'cidade': _cidadeController.text,
          'uf': _ufController.text.toUpperCase(),
        },
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar dados do workspace: $error')),
      );
      setState(() {
        _saving = false;
      });
    }
  }

  Future<void> _buscarCep() async {
    final cep = _cepController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um CEP valido com 8 digitos.')),
      );
      return;
    }

    setState(() {
      _buscandoCep = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://brasilapi.com.br/api/cep/v2/$cep'),
      );

      if (response.statusCode != 200) {
        throw Exception('cep_error');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) {
        return;
      }

      _logradouroController.text = (data['street'] ?? '').toString();
      _bairroController.text = (data['neighborhood'] ?? '').toString();
      _cidadeController.text = (data['city'] ?? '').toString();
      _ufController.text = (data['state'] ?? '').toString();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Endereco preenchido automaticamente pelo CEP.'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel buscar esse CEP no momento.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _buscandoCep = false;
        });
      }
    }
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
      userLabel: (userLabel == null || userLabel.isEmpty) ? 'Portal' : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace: activeTenant.workspaceType == 'seller_solo_workspace',
    );

    return PedidosPage(
      identity: identity,
      repository: FirestorePedidoRepository(FirebaseFirestore.instance),
    );
  }
}