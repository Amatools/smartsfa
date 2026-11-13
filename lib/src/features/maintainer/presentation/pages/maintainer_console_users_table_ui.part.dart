part of 'maintainer_console_page.dart';

extension _MaintainerConsoleUsersTableUiPart on _MaintainerConsolePageState {
  Widget _buildUsersTable(
    List<MaintainerUserAccount> users,
    Map<String, Set<String>> tenantIdsByUid,
    Map<String, String> tenantNamesById, {
    required bool showBillingColumns,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
  }) {
    final pageModel = _buildUsersTablePageModel(users);
    final columns = _buildUsersTableColumns(showBillingColumns);
    final rows = _buildUsersTableRows(
      pageModel.pageUsers,
      tenantIdsByUid,
      tenantNamesById,
      showBillingColumns: showBillingColumns,
      canManageUserStatus: canManageUserStatus,
      canManageUserBilling: canManageUserBilling,
      canManageUserCrud: canManageUserCrud,
      canManageUserPermissions: canManageUserPermissions,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUsersTableTopControls(pageModel),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 1160),
            child: DataTable(
              sortColumnIndex: _sortColumnIndexForScope(showBillingColumns),
              sortAscending: _userSortAscending,
              headingRowHeight: 40,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 58,
              columnSpacing: 14,
              horizontalMargin: 10,
              columns: columns,
              rows: rows,
            ),
          ),
        ),
      ],
    );
  }

  List<DataRow> _buildUsersTableRows(
    List<MaintainerUserAccount> pageUsers,
    Map<String, Set<String>> tenantIdsByUid,
    Map<String, String> tenantNamesById, {
    required bool showBillingColumns,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
  }) {
    return pageUsers
        .map(
          (user) => _buildUserDataRow(
            user,
            tenantIdsByUid[user.uid],
            tenantNamesById,
            showBillingColumns: showBillingColumns,
            canManageUserStatus: canManageUserStatus,
            canManageUserBilling: canManageUserBilling,
            canManageUserCrud: canManageUserCrud,
            canManageUserPermissions: canManageUserPermissions,
          ),
        )
        .toList(growable: false);
  }

  List<DataColumn> _buildUsersTableColumns(bool showBillingColumns) {
    return <DataColumn>[
      _buildUsersSortableColumn('Usuario', _MaintainerUserSortField.user),
      _buildUsersSortableColumn('UID', _MaintainerUserSortField.uid),
      _buildUsersSortableColumn('Tenants', _MaintainerUserSortField.tenants),
      _buildUsersSortableColumn('Conta', _MaintainerUserSortField.account),
      if (showBillingColumns)
        _buildUsersSortableColumn('Billing', _MaintainerUserSortField.billing),
      if (showBillingColumns)
        _buildUsersSortableColumn(
          'Graca ate',
          _MaintainerUserSortField.graceUntil,
        ),
      _buildUsersSortableColumn(
        'Atualizado',
        _MaintainerUserSortField.updatedAt,
      ),
      const DataColumn(label: Text('Acoes')),
    ];
  }

  DataColumn _buildUsersSortableColumn(
    String label,
    _MaintainerUserSortField field,
  ) {
    return DataColumn(
      label: Text(label),
      onSort: (columnIndex, ascending) =>
          _setUserSort(columnIndex, ascending, field),
    );
  }

  Widget _buildUsersTableTopControls(_UsersTablePageModel pageModel) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Linhas por pagina:'),
        DropdownButton<int>(
          value: _usersRowsPerPage,
          items: const [
            DropdownMenuItem(value: 10, child: Text('10')),
            DropdownMenuItem(value: 20, child: Text('20')),
            DropdownMenuItem(value: 50, child: Text('50')),
            DropdownMenuItem(value: 100, child: Text('100')),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            _updateUsersTableState(() {
              _usersRowsPerPage = value;
              _usersPageIndex = 0;
            });
          },
        ),
        Text(
          '${pageModel.pageStart}-${pageModel.pageEnd} de ${pageModel.totalRows}',
        ),
        IconButton.outlined(
          tooltip: 'Pagina anterior',
          onPressed: pageModel.canGoPrevious
              ? () {
                  _updateUsersTableState(() {
                    _usersPageIndex = math.max(
                      0,
                      pageModel.effectivePageIndex - 1,
                    );
                  });
                }
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton.outlined(
          tooltip: 'Proxima pagina',
          onPressed: pageModel.canGoNext
              ? () {
                  _updateUsersTableState(() {
                    _usersPageIndex = pageModel.effectivePageIndex + 1;
                  });
                }
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
