part of 'maintainer_console_page.dart';

extension _MaintainerConsoleUsersTablePart on _MaintainerConsolePageState {
  _UsersTablePageModel _buildUsersTablePageModel(
    List<MaintainerUserAccount> users,
  ) {
    final totalRows = users.length;
    final maxPageIndex = totalRows == 0
        ? 0
        : (totalRows - 1) ~/ _usersRowsPerPage;

    if (_usersPageIndex > maxPageIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _updateUsersTableState(() {
          _usersPageIndex = maxPageIndex;
        });
      });
    }

    final effectivePageIndex = _usersPageIndex > maxPageIndex
        ? maxPageIndex
        : _usersPageIndex;
    final firstRowIndex = effectivePageIndex * _usersRowsPerPage;
    final pageUsers = users
        .skip(firstRowIndex)
        .take(_usersRowsPerPage)
        .toList(growable: false);
    final pageStart = totalRows == 0 ? 0 : firstRowIndex + 1;
    final pageEnd = firstRowIndex + pageUsers.length;
    final canGoPrevious = effectivePageIndex > 0;
    final canGoNext = pageEnd < totalRows;

    return _UsersTablePageModel(
      totalRows: totalRows,
      maxPageIndex: maxPageIndex,
      effectivePageIndex: effectivePageIndex,
      firstRowIndex: firstRowIndex,
      pageUsers: pageUsers,
      pageStart: pageStart,
      pageEnd: pageEnd,
      canGoPrevious: canGoPrevious,
      canGoNext: canGoNext,
    );
  }

  int? _sortColumnIndexForScope(bool showBillingColumns) {
    switch (_userSortField) {
      case _MaintainerUserSortField.user:
        return 0;
      case _MaintainerUserSortField.uid:
        return 1;
      case _MaintainerUserSortField.tenants:
        return 2;
      case _MaintainerUserSortField.account:
        return 3;
      case _MaintainerUserSortField.billing:
        return showBillingColumns ? 4 : null;
      case _MaintainerUserSortField.graceUntil:
        return showBillingColumns ? 5 : null;
      case _MaintainerUserSortField.updatedAt:
        return showBillingColumns ? 6 : 4;
    }
  }

  void _setUserSort(
    int columnIndex,
    bool ascending,
    _MaintainerUserSortField field,
  ) {
    _updateUsersTableState(() {
      _userSortAscending = ascending;
      _userSortField = field;
      _usersPageIndex = 0;
    });
  }

  List<MaintainerUserAccount> _sortUsers(
    List<MaintainerUserAccount> users,
    Map<String, Set<String>> tenantIdsByUid,
    Map<String, String> tenantNamesById,
  ) {
    final sorted = List<MaintainerUserAccount>.from(users);

    sorted.sort((a, b) {
      final order = _compareUsersBySortField(
        a,
        b,
        tenantIdsByUid: tenantIdsByUid,
        tenantNamesById: tenantNamesById,
      );
      if (order == 0) {
        return a.uid.compareTo(b.uid);
      }
      return _userSortAscending ? order : -order;
    });

    return sorted;
  }

  int _compareUsersBySortField(
    MaintainerUserAccount a,
    MaintainerUserAccount b, {
    required Map<String, Set<String>> tenantIdsByUid,
    required Map<String, String> tenantNamesById,
  }) {
    switch (_userSortField) {
      case _MaintainerUserSortField.user:
        return _compareUserIdentity(a, b);
      case _MaintainerUserSortField.uid:
        return a.uid.compareTo(b.uid);
      case _MaintainerUserSortField.tenants:
        return _compareUserTenants(
          a,
          b,
          tenantIdsByUid: tenantIdsByUid,
          tenantNamesById: tenantNamesById,
        );
      case _MaintainerUserSortField.account:
        return _compareUserAccountState(a, b);
      case _MaintainerUserSortField.billing:
        return _compareUserBillingState(a, b);
      case _MaintainerUserSortField.graceUntil:
        return _compareUserGraceUntil(a, b);
      case _MaintainerUserSortField.updatedAt:
        return _compareUserUpdatedAt(a, b);
    }
  }

  int _compareUserIdentity(MaintainerUserAccount a, MaintainerUserAccount b) {
    final emailOrder = a.email.toLowerCase().compareTo(b.email.toLowerCase());
    if (emailOrder != 0) {
      return emailOrder;
    }
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  int _compareUserTenants(
    MaintainerUserAccount a,
    MaintainerUserAccount b, {
    required Map<String, Set<String>> tenantIdsByUid,
    required Map<String, String> tenantNamesById,
  }) {
    final aTenant = _tenantSortKey(
      tenantIdsByUid[a.uid] ?? const <String>{},
      tenantNamesById,
    );
    final bTenant = _tenantSortKey(
      tenantIdsByUid[b.uid] ?? const <String>{},
      tenantNamesById,
    );
    final tenantOrder = aTenant.compareTo(bTenant);
    if (tenantOrder != 0) {
      return tenantOrder;
    }
    return a.uid.compareTo(b.uid);
  }

  int _compareUserAccountState(
    MaintainerUserAccount a,
    MaintainerUserAccount b,
  ) {
    final aValue = a.activeGlobal ? 1 : 0;
    final bValue = b.activeGlobal ? 1 : 0;
    return aValue.compareTo(bValue);
  }

  int _compareUserBillingState(
    MaintainerUserAccount a,
    MaintainerUserAccount b,
  ) {
    return a.billingAccountState.toLowerCase().compareTo(
      b.billingAccountState.toLowerCase(),
    );
  }

  int _compareUserGraceUntil(MaintainerUserAccount a, MaintainerUserAccount b) {
    final aGrace = a.billingGraceUntilAt?.millisecondsSinceEpoch ?? -1;
    final bGrace = b.billingGraceUntilAt?.millisecondsSinceEpoch ?? -1;
    return aGrace.compareTo(bGrace);
  }

  int _compareUserUpdatedAt(MaintainerUserAccount a, MaintainerUserAccount b) {
    final aUpdated = a.updatedAt?.millisecondsSinceEpoch ?? -1;
    final bUpdated = b.updatedAt?.millisecondsSinceEpoch ?? -1;
    return aUpdated.compareTo(bUpdated);
  }

  String _tenantSortKey(
    Set<String> tenantIds,
    Map<String, String> tenantNamesById,
  ) {
    if (tenantIds.isEmpty) {
      return '';
    }
    final sorted = tenantIds.toList(growable: false)..sort();
    return sorted
        .map((tenantId) => _tenantFilterLabel(tenantId, tenantNamesById))
        .join('|');
  }

  List<MaintainerUserAccount> _filterUsersByScope(
    List<MaintainerUserAccount> users,
    _MaintainerUserScope scope,
  ) {
    final filtered = users
        .where((user) => _matchesUserScope(user, scope))
        .toList(growable: false);

    filtered.sort(_compareUsersByEmailThenUid);

    return filtered;
  }

  bool _matchesUserScope(
    MaintainerUserAccount user,
    _MaintainerUserScope scope,
  ) {
    final isMaintainer = _isMaintainerAccount(user);
    if (scope == _MaintainerUserScope.platformUsers) {
      return isMaintainer;
    }
    return !isMaintainer;
  }

  int _compareUsersByEmailThenUid(
    MaintainerUserAccount a,
    MaintainerUserAccount b,
  ) {
    final emailOrder = a.email.toLowerCase().compareTo(b.email.toLowerCase());
    if (emailOrder != 0) {
      return emailOrder;
    }
    return a.uid.compareTo(b.uid);
  }
}
