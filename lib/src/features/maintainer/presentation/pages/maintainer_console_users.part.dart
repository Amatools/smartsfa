part of 'maintainer_console_page.dart';

extension _MaintainerConsoleUsersPart on _MaintainerConsolePageState {
  Widget _buildUserAdminCard(
    BuildContext context,
    MaintainerAccessDecision decision, {
    required _MaintainerUserScope scope,
  }) {
    final canViewUsers = decision.can(MaintainerPermission.viewUsers);
    final canManageUserStatus = decision.can(
      MaintainerPermission.manageUserStatus,
    );
    final canManageUserBilling = decision.can(
      MaintainerPermission.manageUserBilling,
    );
    final canManageUserCrud = decision.can(MaintainerPermission.manageUserCrud);
    final canManageUserPermissions = decision.can(
      MaintainerPermission.manageUserPermissions,
    );
    final isPlatformUserScope = scope == _MaintainerUserScope.platformUsers;
    final title = isPlatformUserScope
        ? 'Gestao de usuarios'
        : 'Gestao de cliente';
    final description = isPlatformUserScope
        ? 'CRUD e matriz de permissoes para usuarios administrativos da plataforma.'
        : 'Lista operacional de contas de clientes com filtros por tenant e controle de status de conta.';

    if (!canViewUsers) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Gestao de usuarios indisponivel para esta conta.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Solicite permissao maintainer.view.users no cadastro de seguranca.',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (isPlatformUserScope && canManageUserCrud)
                      FilledButton.icon(
                        onPressed: () => _openEditUserDialog(context),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Novo usuario'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(description),
                const SizedBox(height: 12),
                _buildUsersMembershipSection(
                  scope: scope,
                  isPlatformUserScope: isPlatformUserScope,
                  canManageUserStatus: canManageUserStatus,
                  canManageUserBilling: canManageUserBilling,
                  canManageUserCrud: canManageUserCrud,
                  canManageUserPermissions: canManageUserPermissions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUsersMembershipSection({
    required _MaintainerUserScope scope,
    required bool isPlatformUserScope,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
  }) {
    return StreamBuilder<List<MaintainerUserTenantMembership>>(
      stream: _userAdminService.watchTenantMemberships(),
      builder: (context, membershipsSnapshot) {
        if (membershipsSnapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }

        if (membershipsSnapshot.hasError) {
          return Text(
            'Falha ao carregar memberships: ${membershipsSnapshot.error}',
          );
        }

        final memberships =
            membershipsSnapshot.data ??
            const <MaintainerUserTenantMembership>[];
        final activeMemberships = memberships
            .where((membership) => membership.isActiveMembership)
            .toList(growable: false);

        final tenantIdsByUid = <String, Set<String>>{};
        for (final membership in activeMemberships) {
          tenantIdsByUid
              .putIfAbsent(membership.uid, () => <String>{})
              .add(membership.tenantId);
        }

        final tenantOptions =
            activeMemberships
                .map((membership) => membership.tenantId)
                .toSet()
                .toList(growable: false)
              ..sort();

        final selectedTenant = tenantOptions.contains(_selectedTenantId)
            ? _selectedTenantId
            : null;

        return _buildUsersTenantNamesSection(
          scope: scope,
          tenantIdsByUid: tenantIdsByUid,
          tenantOptions: tenantOptions,
          selectedTenant: selectedTenant,
          isPlatformUserScope: isPlatformUserScope,
          canManageUserStatus: canManageUserStatus,
          canManageUserBilling: canManageUserBilling,
          canManageUserCrud: canManageUserCrud,
          canManageUserPermissions: canManageUserPermissions,
        );
      },
    );
  }

  Widget _buildUsersTenantNamesSection({
    required _MaintainerUserScope scope,
    required Map<String, Set<String>> tenantIdsByUid,
    required List<String> tenantOptions,
    required String? selectedTenant,
    required bool isPlatformUserScope,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
  }) {
    return StreamBuilder<Map<String, String>>(
      stream: _userAdminService.watchTenantNamesById(),
      builder: (context, tenantNamesSnapshot) {
        if (tenantNamesSnapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }

        if (tenantNamesSnapshot.hasError) {
          return Text(
            'Falha ao carregar nomes de tenants: ${tenantNamesSnapshot.error}',
          );
        }

        final tenantNamesById =
            tenantNamesSnapshot.data ?? const <String, String>{};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUserFiltersRow(
              tenantOptions,
              selectedTenant,
              tenantNamesById,
            ),
            const SizedBox(height: 12),
            _buildUsersResultsSection(
              scope: scope,
              tenantIdsByUid: tenantIdsByUid,
              tenantNamesById: tenantNamesById,
              selectedTenant: selectedTenant,
              isPlatformUserScope: isPlatformUserScope,
              canManageUserStatus: canManageUserStatus,
              canManageUserBilling: canManageUserBilling,
              canManageUserCrud: canManageUserCrud,
              canManageUserPermissions: canManageUserPermissions,
            ),
          ],
        );
      },
    );
  }

  Widget _buildUsersResultsSection({
    required _MaintainerUserScope scope,
    required Map<String, Set<String>> tenantIdsByUid,
    required Map<String, String> tenantNamesById,
    required String? selectedTenant,
    required bool isPlatformUserScope,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
  }) {
    return StreamBuilder<List<MaintainerUserAccount>>(
      stream: _userAdminService.watchUsers(),
      builder: (context, usersSnapshot) {
        if (usersSnapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }

        if (usersSnapshot.hasError) {
          return Text('Falha ao carregar usuarios: ${usersSnapshot.error}');
        }

        final allUsers = usersSnapshot.data ?? const <MaintainerUserAccount>[];
        final scopedUsers = _filterUsersByScope(allUsers, scope);
        final filteredUsers = _filterUsers(
          scopedUsers,
          tenantIdsByUid,
          selectedTenantId: selectedTenant,
        );
        final sortedUsers = _sortUsers(
          filteredUsers,
          tenantIdsByUid,
          tenantNamesById,
        );

        if (sortedUsers.isEmpty) {
          return const Text('Nenhum usuario encontrado com os filtros atuais.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resultados: ${sortedUsers.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _buildUsersTable(
              sortedUsers,
              tenantIdsByUid,
              tenantNamesById,
              showBillingColumns: false,
              canManageUserStatus: canManageUserStatus,
              canManageUserBilling: false,
              canManageUserCrud: isPlatformUserScope && canManageUserCrud,
              canManageUserPermissions:
                  isPlatformUserScope && canManageUserPermissions,
            ),
          ],
        );
      },
    );
  }
}
