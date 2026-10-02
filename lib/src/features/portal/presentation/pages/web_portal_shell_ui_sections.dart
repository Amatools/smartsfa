part of 'web_portal_page.dart';

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
                                  : Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                              width: selected ? 2 : 1,
                            ),
                            color: selected
                                ? Theme.of(context).colorScheme.primaryContainer
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
                                      const Text('Padrão da conta'),
                                    ],
                                  ],
                                ),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    onSelectTenant(tenant.tenantId),
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
                          final disabled =
                              tenantSectionLocked &&
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
            Text(
              'Workspace em uso',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            Text(
              activeTenant.tenantName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
                  message:
                      'Conta da Plataforma: ${identity.userLabel}\n'
                      'Workspace em uso: ${activeTenant.tenantName}\n'
                      'Workspace: ${_workspaceTypeLabel(activeTenant.workspaceType)}\n'
                      'Tipo de conta: ${_accountContractLockLabel(accountContractLock)}',
                  child: const Icon(Icons.info_outline, size: 18),
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
  })
  onToggleFavoriteRepresented;
  final bool settingFavoriteRepresented;
  final VoidCallback onBackToWorkspaceSelection;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
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
                  'Portal de Gestão',
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
              stream: WorkspaceProfileService(FirebaseFirestore.instance)
                  .watchWorkspace(activeTenant.tenantId),
              builder: (context, snapshot) {
                final workspaceData =
                    snapshot.data ?? const <String, dynamic>{};
                final supportsRepresentedCompanies =
                    activeTenant.workspaceType == 'seller_solo_workspace' ||
                    activeTenant.workspaceType == 'rep_workspace';
                final favoriteRepresentedCompanyId =
                    (workspaceData['favoriteRepresentedCompanyId'] ?? '')
                        .toString()
                        .trim();
                return StreamBuilder<List<Map<String, Object?>>>(
                  stream: WorkspaceProfileService(FirebaseFirestore.instance)
                      .watchRepresentedCompanies(activeTenant.tenantId),
                  builder: (context, representedSnapshot) {
                    final representedCompanies =
                        _representedCompaniesFromStorage(
                          representedSnapshot.data ??
                              const <Map<String, Object?>>[],
                        );
                    final selectedId =
                        representedCompanies.any(
                          (company) =>
                              company.id == selectedRepresentedCompanyId,
                        )
                        ? selectedRepresentedCompanyId
                        : null;
                    final favoriteId =
                        representedCompanies.any(
                          (company) =>
                              company.id == favoriteRepresentedCompanyId,
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
                                    for (final company
                                        in representedCompanies) {
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
                            onPressed:
                                effectiveSelectedId == null ||
                                    settingFavoriteRepresented ||
                                    !supportsRepresentedCompanies
                                ? null
                                : () => onToggleFavoriteRepresented(
                                    activeTenant: activeTenant,
                                    selectedRepresentedCompanyId:
                                        effectiveSelectedId,
                                    favoriteRepresentedCompanyId:
                                        favoriteRepresentedCompanyId,
                                  ),
                            icon: Icon(
                              isFavoriteSelection
                                  ? Icons.star
                                  : Icons.star_outline,
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

String _workspaceTypeLabel(String workspaceType) {
  switch (workspaceType.trim()) {
    case 'seller_solo_workspace':
      return 'Individual';
    case 'rep_workspace':
      return 'Representações';
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
