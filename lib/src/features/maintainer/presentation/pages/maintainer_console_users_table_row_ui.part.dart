part of 'maintainer_console_page.dart';

extension _MaintainerConsoleUsersTableRowUiPart on _MaintainerConsolePageState {
  DataRow _buildUserDataRow(
    MaintainerUserAccount user,
    Set<String>? tenantIds,
    Map<String, String> tenantNamesById, {
    required bool showBillingColumns,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
  }) {
    final processing = _processingUserIds.contains(user.uid);
    final displayModel = _buildUserRowDisplayModel(
      user,
      tenantIds ?? const <String>{},
      tenantNamesById,
    );
    final actionModel = _buildUserRowActionModel(
      user,
      canManageUserStatus: canManageUserStatus,
      canManageUserBilling: canManageUserBilling,
      canManageUserCrud: canManageUserCrud,
      canManageUserPermissions: canManageUserPermissions,
    );

    return DataRow(
      cells: _buildUserDataCells(
        user,
        displayModel: displayModel,
        actionModel: actionModel,
        showBillingColumns: showBillingColumns,
        processing: processing,
        canManageUserStatus: canManageUserStatus,
        canManageUserBilling: canManageUserBilling,
        canManageUserCrud: canManageUserCrud,
        canManageUserPermissions: canManageUserPermissions,
      ),
    );
  }

  _UserRowDisplayModel _buildUserRowDisplayModel(
    MaintainerUserAccount user,
    Set<String> tenantIds,
    Map<String, String> tenantNamesById,
  ) {
    final emailLabel = user.email.isEmpty ? '(sem e-mail)' : user.email;
    final nameLabel = user.displayName.isEmpty
        ? '(sem nome)'
        : user.displayName;
    final tenantLabel = _formatTenantSummary(tenantIds, tenantNamesById);
    final accountLabel = user.activeGlobal ? 'Ativa' : 'Inativa';
    final billingLabel = user.billingAccountState.isEmpty
        ? 'active'
        : user.billingAccountState;

    return _UserRowDisplayModel(
      emailLabel: emailLabel,
      nameLabel: nameLabel,
      tenantLabel: tenantLabel,
      accountLabel: accountLabel,
      billingLabel: billingLabel,
      showAuthOrphanBadge: user.isAuthOrphan,
    );
  }

  List<DataCell> _buildUserDataCells(
    MaintainerUserAccount user, {
    required _UserRowDisplayModel displayModel,
    required _UserRowActionModel actionModel,
    required bool showBillingColumns,
    required bool processing,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
  }) {
    return [
      _buildUserIdentityDataCell(
        emailLabel: displayModel.emailLabel,
        nameLabel: displayModel.nameLabel,
        showAuthOrphanBadge: displayModel.showAuthOrphanBadge,
      ),
      _buildUserUidDataCell(user.uid),
      _buildUserTenantDataCell(displayModel.tenantLabel),
      DataCell(Text(displayModel.accountLabel)),
      if (showBillingColumns) DataCell(Text(displayModel.billingLabel)),
      if (showBillingColumns)
        DataCell(Text(_formatDateTime(user.billingGraceUntilAt))),
      DataCell(Text(_formatDateTime(user.updatedAt))),
      _buildUserActionsDataCell(
        user,
        processing: processing,
        actionModel: actionModel,
        canManageUserStatus: canManageUserStatus,
        canManageUserBilling: canManageUserBilling,
        canManageUserCrud: canManageUserCrud,
        canManageUserPermissions: canManageUserPermissions,
      ),
    ];
  }

  DataCell _buildUserIdentityDataCell({
    required String emailLabel,
    required String nameLabel,
    required bool showAuthOrphanBadge,
  }) {
    return DataCell(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Tooltip(
                  message: emailLabel,
                  waitDuration: const Duration(milliseconds: 350),
                  child: Text(emailLabel, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (showAuthOrphanBadge) ...[
                const SizedBox(width: 8),
                _buildAuthOrphanBadge(),
              ],
            ],
          ),
          Tooltip(
            message: nameLabel,
            waitDuration: const Duration(milliseconds: 350),
            child: Text(
              nameLabel,
              style: const TextStyle(fontSize: 12, color: Color(0xFF576074)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthOrphanBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD97706), width: 1),
      ),
      child: const Text(
        'ORFAO',
        style: TextStyle(
          fontSize: 10,
          color: Color(0xFF9A3412),
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  DataCell _buildUserUidDataCell(String uid) {
    return DataCell(
      SizedBox(
        width: 180,
        child: Tooltip(
          message: uid,
          waitDuration: const Duration(milliseconds: 350),
          child: Text(uid, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  DataCell _buildUserTenantDataCell(String tenantLabel) {
    return DataCell(
      SizedBox(
        width: 220,
        child: Tooltip(
          message: tenantLabel,
          waitDuration: const Duration(milliseconds: 350),
          child: Text(tenantLabel, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  _UserRowActionModel _buildUserRowActionModel(
    MaintainerUserAccount user, {
    required bool canManageUserStatus,
    required bool canManageUserBilling,
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
  }) {
    final hasActionPermission =
        canManageUserStatus || canManageUserCrud || canManageUserPermissions;
    final currentUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final isSelfAccount =
        currentUid.isNotEmpty && currentUid == user.uid.trim();

    final actionItems = <PopupMenuEntry<_MaintainerUserAction>>[
      if (canManageUserCrud)
        const PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.editProfile,
          child: Text('Editar cadastro'),
        ),
      if (canManageUserPermissions)
        const PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.editPermissionMatrix,
          child: Text('Editar matriz de permissoes'),
        ),
      if (canManageUserCrud && !isSelfAccount)
        const PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.deleteUser,
          child: Text('Excluir usuario'),
        ),
      if (canManageUserCrud && isSelfAccount)
        const PopupMenuItem<_MaintainerUserAction>(
          enabled: false,
          child: Text('Excluir usuario (bloqueado para a propria conta)'),
        ),
      if ((canManageUserCrud || canManageUserPermissions) &&
          canManageUserStatus)
        const PopupMenuDivider(),
      if (canManageUserStatus)
        PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.toggleAccount,
          child: Text(user.activeGlobal ? 'Desativar conta' : 'Ativar conta'),
        ),
      if (canManageUserStatus)
        const PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.requestDeleteAccount,
          child: Text('Solicitar exclusao de conta'),
        ),
    ];

    return _UserRowActionModel(
      hasActionPermission: hasActionPermission,
      actionItems: actionItems,
    );
  }

  DataCell _buildUserActionsDataCell(
    MaintainerUserAccount user, {
    required bool processing,
    required _UserRowActionModel actionModel,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
  }) {
    return DataCell(
      !actionModel.hasActionPermission
          ? const Text('Somente leitura')
          : processing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<_MaintainerUserAction>(
              tooltip: 'Acoes do usuario',
              onSelected: (action) => _onUserActionSelected(
                user,
                action,
                canManageUserCrud: canManageUserCrud,
                canManageUserPermissions: canManageUserPermissions,
                canManageUserStatus: canManageUserStatus,
                canManageUserBilling: canManageUserBilling,
              ),
              itemBuilder: (_) => actionModel.actionItems,
              child: const Icon(Icons.more_horiz),
            ),
    );
  }
}
