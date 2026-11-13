part of 'maintainer_console_page.dart';

class _UsersTablePageModel {
  const _UsersTablePageModel({
    required this.totalRows,
    required this.maxPageIndex,
    required this.effectivePageIndex,
    required this.firstRowIndex,
    required this.pageUsers,
    required this.pageStart,
    required this.pageEnd,
    required this.canGoPrevious,
    required this.canGoNext,
  });

  final int totalRows;
  final int maxPageIndex;
  final int effectivePageIndex;
  final int firstRowIndex;
  final List<MaintainerUserAccount> pageUsers;
  final int pageStart;
  final int pageEnd;
  final bool canGoPrevious;
  final bool canGoNext;
}

class _UserRowActionModel {
  const _UserRowActionModel({
    required this.hasActionPermission,
    required this.actionItems,
  });

  final bool hasActionPermission;
  final List<PopupMenuEntry<_MaintainerUserAction>> actionItems;
}

class _UserRowDisplayModel {
  const _UserRowDisplayModel({
    required this.emailLabel,
    required this.nameLabel,
    required this.tenantLabel,
    required this.accountLabel,
    required this.billingLabel,
  });

  final String emailLabel;
  final String nameLabel;
  final String tenantLabel;
  final String accountLabel;
  final String billingLabel;
}
