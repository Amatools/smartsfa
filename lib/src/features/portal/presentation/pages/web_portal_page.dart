import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_lib;

import '../../../../core/data/firestore/firestore_produto_repository.dart';
import '../../../../core/models/app_identity.dart';
import '../../../../core/models/tenant_entry_decision.dart';
import '../../../auth/services/solo_workspace_service.dart';
import '../../../auth/services/tenant_membership_service.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../../../produtos/presentation/pages/produtos_page.dart';

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
            final items = _buildItemsForRole(
              activeTenant.role,
              accountContractLock,
            );
            final representedRequired = _requiresRepresentedSelection(activeTenant);
            final representedSelected =
                (_activeRepresentedCompanyByTenant[activeTenant.tenantId] ?? '')
                    .trim()
                    .isNotEmpty;
            final tenantSectionLocked = representedRequired && !representedSelected;

            var safeIndex = _selectedIndex.clamp(0, items.length - 1);
            if (tenantSectionLocked && items[safeIndex].section == _PortalSection.tenant) {
              final firstGlobalIndex = items.indexWhere(
                (item) => item.section == _PortalSection.global,
              );
              safeIndex = firstGlobalIndex >= 0 ? firstGlobalIndex : 0;
            }
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

            final selectedItem = items[safeIndex];
            final groupedItems = _groupItems(items);
            final isWide = MediaQuery.sizeOf(context).width >= 1120;

            final content = SingleChildScrollView(
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
                            selectedIndex: safeIndex,
                            onMenuSelected: _setSelectedIndex,
                            tenantSectionLocked: tenantSectionLocked,
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
                                  items[index].section == _PortalSection.tenant) {
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
                            destinations: items
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
    String role,
    AccountContractLock accountContractLock,
  ) {
    final normalizedRole = role.trim().toLowerCase().replaceAll(' ', '_');
    final isTenantManager = normalizedRole == 'owner' ||
        normalizedRole == 'gerente' ||
        normalizedRole == 'platform_admin';
    final canAccessInvites = normalizedRole == 'owner' ||
      normalizedRole == 'gerente' ||
      normalizedRole == 'representante' ||
      normalizedRole == 'platform_admin';

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
      const _PortalNavItem(
        label: 'Representadas',
        icon: Icons.apartment_outlined,
        section: _PortalSection.global,
        builder: _RepresentedCompaniesSection.new,
      ),
    ];

    if (isTenantManager) {
      items.addAll(const [
        _PortalNavItem(
          label: 'Billing',
          icon: Icons.payments_outlined,
          section: _PortalSection.global,
          builder: _BillingSection.new,
        ),
        _PortalNavItem(
          label: 'Produtos',
          icon: Icons.inventory_2_outlined,
          section: _PortalSection.tenant,
          builder: _ProductsCatalogSection.new,
        ),
        _PortalNavItem(
          label: 'Tabelas de preço',
          icon: Icons.price_change_outlined,
          section: _PortalSection.tenant,
          builder: _PricingCatalogSection.new,
        ),
        _PortalNavItem(
          label: 'Condicoes de pagamento',
          icon: Icons.receipt_long_outlined,
          section: _PortalSection.tenant,
          builder: _PaymentConditionsSection.new,
        ),
        _PortalNavItem(
          label: 'Politicas',
          icon: Icons.policy_outlined,
          section: _PortalSection.tenant,
          builder: _SimpleSectionPage.politicas,
        ),
        _PortalNavItem(
          label: 'ERP',
          icon: Icons.integration_instructions_outlined,
          section: _PortalSection.tenant,
          builder: _SimpleSectionPage.erp,
        ),
        _PortalNavItem(
          label: 'Auditoria',
          icon: Icons.fact_check_outlined,
          section: _PortalSection.tenant,
          builder: _SimpleSectionPage.auditoria,
        ),
      ]);
    } else {
      items.addAll(const [
        _PortalNavItem(
          label: 'Produtos',
          icon: Icons.inventory_2_outlined,
          section: _PortalSection.tenant,
          builder: _ProductsCatalogSection.new,
        ),
        _PortalNavItem(
          label: 'Tabelas de preço',
          icon: Icons.price_change_outlined,
          section: _PortalSection.tenant,
          builder: _PricingCatalogSection.new,
        ),
        _PortalNavItem(
          label: 'Condicoes de pagamento',
          icon: Icons.receipt_long_outlined,
          section: _PortalSection.tenant,
          builder: _PaymentConditionsSection.new,
        ),
        _PortalNavItem(
          label: 'Politicas',
          icon: Icons.policy_outlined,
          section: _PortalSection.tenant,
          builder: _SimpleSectionPage.politicas,
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
        ),
      );
    }

    return items;
  }

  List<_PortalMenuSection> _groupItems(List<_PortalNavItem> items) {
    final global = <_PortalNavItem>[];
    final tenant = <_PortalNavItem>[];

    for (final item in items) {
      if (item.section == _PortalSection.global) {
        global.add(item);
      } else {
        tenant.add(item);
      }
    }

    return [
      _PortalMenuSection(title: 'Global da conta SaaS', items: global),
      _PortalMenuSection(title: 'Empresa ativa', items: tenant),
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
  });

  final String label;
  final IconData icon;
  final _PortalSection section;
  final _PortalSectionBuilder builder;
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
    required this.selectedIndex,
    required this.onMenuSelected,
    required this.tenantSectionLocked,
  });

  final AppIdentity identity;
  final TenantEntryOption activeTenant;
  final AccountContractLock accountContractLock;
  final List<_PortalMenuSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onMenuSelected;
  final bool tenantSectionLocked;

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
                          return ListTile(
                            selected: selectedIndex == _itemIndex(item),
                            enabled: !disabled,
                            leading: Icon(item.icon),
                            title: Text(item.label),
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
    final all = sections.expand((section) => section.items).toList();
    return all.indexOf(item);
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
                final representedCompanies =
                    _extractRepresentedCompanies(workspaceData);
                final supportsRepresentedCompanies =
                    activeTenant.workspaceType == 'seller_solo_workspace' ||
                    activeTenant.workspaceType == 'rep_workspace';

                final selectedId = representedCompanies.any(
                  (company) => company.id == selectedRepresentedCompanyId,
                )
                    ? selectedRepresentedCompanyId
                    : null;
                final favoriteRepresentedCompanyId =
                    (workspaceData['favoriteRepresentedCompanyId'] ?? '')
                        .toString()
                        .trim();
                final isFavoriteSelection =
                    selectedId != null && selectedId == favoriteRepresentedCompanyId;

                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: selectedId,
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
                      message: selectedId == null
                          ? 'Selecione uma representada para favoritar'
                          : isFavoriteSelection
                          ? 'Representada favorita'
                          : 'Favoritar representada ativa',
                      child: IconButton.outlined(
                        onPressed: selectedId == null ||
                                settingFavoriteRepresented ||
                                !supportsRepresentedCompanies
                            ? null
                            : () => onToggleFavoriteRepresented(
                                  activeTenant: activeTenant,
                                  selectedRepresentedCompanyId: selectedId,
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
    final canManageRepresentedCompanies = _canEditWorkspaceProfile(
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
                  builder: (context, snapshot) {
                    final workspaceData = snapshot.data ?? const <String, dynamic>{};
                    final representedCompanies = _extractRepresentedCompanies(workspaceData);

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
}

class _RepresentedCompany {
  const _RepresentedCompany({
    required this.id,
    required this.nomeFantasia,
    required this.razaoSocial,
    required this.cnpj,
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
  final String logoUrl;
  final String contato;
  final String telefone;
  final String email;
  final String cidade;
  final String uf;
  final String segmento;
  final bool ativo;
}

List<_RepresentedCompany> _extractRepresentedCompanies(
  Map<String, dynamic> workspaceData,
) {
  final raw = workspaceData['representedCompanies'];
  if (raw is! List) {
    return const <_RepresentedCompany>[];
  }

  final result = <_RepresentedCompany>[];
  for (final item in raw) {
    if (item is Map) {
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final id = (map['id'] ?? '').toString();
      if (id.trim().isEmpty) {
        continue;
      }

      result.add(
        _RepresentedCompany(
          id: id,
          nomeFantasia: (map['nomeFantasia'] ?? '').toString(),
          razaoSocial: (map['razaoSocial'] ?? '').toString(),
          cnpj: (map['cnpj'] ?? '').toString(),
          logoUrl: (map['logoUrl'] ?? '').toString(),
          contato: (map['contato'] ?? '').toString(),
          telefone: (map['telefone'] ?? '').toString(),
          email: (map['email'] ?? '').toString(),
          cidade: (map['cidade'] ?? '').toString(),
          uf: (map['uf'] ?? '').toString(),
          segmento: (map['segmento'] ?? '').toString(),
          ativo: map['ativo'] == true,
        ),
      );
    }
  }

  result.sort(
    (a, b) => a.nomeFantasia.toLowerCase().compareTo(b.nomeFantasia.toLowerCase()),
  );
  return result;
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
  final contatoController = TextEditingController(text: initial?.contato ?? '');
  final telefoneController = TextEditingController(text: initial?.telefone ?? '');
  final emailController = TextEditingController(text: initial?.email ?? '');
  final cidadeController = TextEditingController(text: initial?.cidade ?? '');
  final ufController = TextEditingController(text: initial?.uf ?? '');
  final segmentoController = TextEditingController(text: initial?.segmento ?? '');
  var ativo = initial?.ativo ?? true;
  var logoData = initial?.logoUrl ?? '';

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
                    Row(
                      children: [
                        _RepresentedCompanyAvatar(
                          company: _RepresentedCompany(
                            id: initial?.id ?? 'preview',
                            nomeFantasia: nomeFantasiaController.text,
                            razaoSocial: razaoSocialController.text,
                            cnpj: cnpjController.text,
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
  final List<TextEditingController> _controllers = [];
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
    final canEditRules = widget.activeTenant.workspaceType == 'seller_solo_workspace' ||
        _isRuleEditorRole(widget.activeTenant.role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Condicoes de pagamento', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          representedName.isEmpty
              ? 'Construtor de regras textuais para o contexto ativo.'
              : 'Construtor de regras textuais para a representada $representedName.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: StreamBuilder<List<String>>(
              stream: _service.watchTextRuleList(
                tenantId: widget.activeTenant.tenantId,
                fieldName: 'paymentConditionRules',
              ),
              builder: (context, snapshot) {
                final rules = snapshot.data ?? const <String>[];
                if (!_initialized || _loadedTenantId != widget.activeTenant.tenantId) {
                  _syncControllers(rules);
                  _initialized = true;
                  _loadedTenantId = widget.activeTenant.tenantId;
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Regras livres de pagamento',
                                style: textTheme.titleMedium,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: canEditRules && !_saving ? _addRule : null,
                              icon: const Icon(Icons.add),
                              label: const Text('Adicionar linha'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Digite uma regra por linha. Ex.: A vista, 30/60/90/120/150 Boleto.',
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        if (_controllers.isEmpty)
                          const Text('Nenhuma regra criada ainda.')
                        else
                          Column(
                            children: [
                              for (var index = 0; index < _controllers.length; index++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _controllers[index],
                                          enabled: canEditRules && !_saving,
                                          decoration: InputDecoration(
                                            labelText: 'Regra ${index + 1}',
                                            border: const OutlineInputBorder(),
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
                                          icon: const Icon(Icons.remove_circle_outline),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        if (!canEditRules)
                          const Text(
                            'Esta conta pode apenas selecionar regras existentes. Edição fica bloqueada pelo papel atual.',
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
                              label: Text(_saving ? 'Salvando...' : 'Salvar regras'),
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

  bool _isRuleEditorRole(String role) {
    final normalized = role.trim().toLowerCase();
    return normalized == 'owner' ||
        normalized == 'gerente' ||
        normalized == 'representante';
  }

  void _syncControllers(List<String> rules) {
    _clearControllers();
    if (rules.isEmpty) {
      _controllers.add(TextEditingController());
      return;
    }

    for (final rule in rules) {
      _controllers.add(TextEditingController(text: rule));
    }
  }

  void _addRule() {
    setState(() {
      _controllers.add(TextEditingController());
    });
  }

  void _removeRule(int index) {
    if (_controllers.length == 1) {
      _controllers.first.clear();
      return;
    }

    setState(() {
      _controllers.removeAt(index).dispose();
    });
  }

  Future<void> _saveRules() async {
    final values = _controllers.map((controller) => controller.text).toList();
    setState(() {
      _saving = true;
    });

    try {
      await _service.updateTextRuleList(
        tenantId: widget.activeTenant.tenantId,
        fieldName: 'paymentConditionRules',
        values: values,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Regras de pagamento salvas.')),
      );
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

  void _clearControllers() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _controllers.clear();
  }
}

class _PricingCatalogSection extends StatelessWidget {
  const _PricingCatalogSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final representedName = activeRepresentedCompanyName?.trim() ?? '';
    final representedLabel = representedName.isEmpty
        ? 'sem representada selecionada'
        : 'representada $representedName';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tabelas de preço', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Cadastro de tabelas de preço por tenant para $representedLabel.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Como este módulo vai funcionar', style: textTheme.titleMedium),
                const SizedBox(height: 12),
                const _FeatureRow(
                  icon: Icons.upload_file_outlined,
                  title: 'Importacao via Excel',
                  subtitle: 'Subida de planilha para carga inicial e atualizacao em lote.',
                ),
                const SizedBox(height: 8),
                const _FeatureRow(
                  icon: Icons.edit_outlined,
                  title: 'Cadastro manual',
                  subtitle: 'Edicao tabela a tabela quando precisar tratar excecoes.',
                ),
                const SizedBox(height: 8),
                const _FeatureRow(
                  icon: Icons.sync_outlined,
                  title: 'Integração ERP enterprise',
                  subtitle: 'No futuro, a base do ERP alimenta todos os membros da enterprise.',
                ),
                const SizedBox(height: 16),
                _SimpleCardSection(
                  title: 'Modelos suportados',
                  subtitle:
                      'O modulo precisa suportar tabela por cliente/regiao/canal e política comercial por desconto sobre o bruto.',
                  items: const [
                    'Tabela de preco por cliente, grupo, regiao ou campanha',
                    'Politica comercial com descontos, acrescimos e promocoes',
                    'Travas por perfil e regras de elegibilidade',
                    'Versao/validade e prioridade de aplicacao',
                  ],
                ),
                const SizedBox(height: 16),
                _SimpleCardSection(
                  title: 'Vinculo da tabela',
                  subtitle:
                      'A mesma planilha pode ser geral ou ser amarrada a cliente, regiao ou canal. O sistema deve aceitar sem forcar um unico modelo.',
                  items: const [
                    'Tabela sem vinculo: aplica como base geral',
                    'Tabela por cliente: herda direto para um cliente especifico',
                    'Tabela por regiao: aplica para um conjunto geografico',
                    'Tabela por canal: ajuda em times/comerciais distintos',
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => _showPriceTableImportSheet(context),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Importar planilha'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _showSoon(context, 'Cadastro manual de tabela de preço'),
                      icon: const Icon(Icons.add),
                      label: const Text('Nova tabela'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

void _showSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$feature ainda esta em construcao.')),
  );
}

Future<void> _showPriceTableImportSheet(BuildContext context) async {
  var scope = 'general';
  String? selectedFileName;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> pickFile() async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: const ['xlsx', 'xls', 'csv'],
              allowMultiple: false,
              withData: true,
            );

            final file = result?.files.isNotEmpty == true ? result!.files.first : null;
            if (file == null) {
              return;
            }

            setSheetState(() {
              selectedFileName = file.name;
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Importar tabela de preço',
                    style: Theme.of(sheetContext).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Escolha a planilha e defina se ela sera geral, por cliente ou por regiao.',
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: 'general',
                          groupValue: scope,
                          title: const Text('Tabela sem vínculo'),
                          subtitle: const Text('Aplica como base geral do tenant.'),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => scope = value);
                          },
                        ),
                        RadioListTile<String>(
                          value: 'client',
                          groupValue: scope,
                          title: const Text('Vincular a cliente'),
                          subtitle: const Text('Usa uma tabela específica para um cliente.'),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => scope = value);
                          },
                        ),
                        RadioListTile<String>(
                          value: 'region',
                          groupValue: scope,
                          title: const Text('Vincular a região'),
                          subtitle: const Text('Usa uma tabela por praça, UF ou grupo regional.'),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => scope = value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (selectedFileName != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('Planilha selecionada'),
                        subtitle: Text(selectedFileName!),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: pickFile,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Selecionar planilha'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showSoon(context, 'Mapeamento e validacao da planilha'),
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Validar estrutura'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Fechar'),
                      ),
                    ],
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

    return ProdutosPage(
      identity: identity,
      repository: FirestoreProdutoRepository(FirebaseFirestore.instance),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(icon, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle),
            ],
          ),
        ),
      ],
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(module.icon, size: 28),
            const SizedBox(height: 12),
            Text(module.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(module.subtitle),
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