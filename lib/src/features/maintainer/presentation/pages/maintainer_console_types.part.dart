part of 'maintainer_console_page.dart';

enum _MaintainerConsoleTab {
  home,
  billing,
  clients,
  users,
  audit,
  impersonation,
  stripe,
}

class _MaintainerBillingWorkspaceRow {
  const _MaintainerBillingWorkspaceRow({
    required this.workspace,
    required this.ownerMembership,
    required this.ownerAccount,
  });

  final MaintainerTenantBillingWorkspace workspace;
  final MaintainerUserTenantMembership? ownerMembership;
  final MaintainerUserAccount? ownerAccount;
}

class _MaintainerBillingTablePageModel {
  const _MaintainerBillingTablePageModel({
    required this.totalRows,
    required this.maxPageIndex,
    required this.effectivePageIndex,
    required this.firstRowIndex,
    required this.pageRows,
    required this.pageStart,
    required this.pageEnd,
    required this.canGoPrevious,
    required this.canGoNext,
  });

  final int totalRows;
  final int maxPageIndex;
  final int effectivePageIndex;
  final int firstRowIndex;
  final List<_MaintainerBillingWorkspaceRow> pageRows;
  final int pageStart;
  final int pageEnd;
  final bool canGoPrevious;
  final bool canGoNext;
}

enum _MaintainerUserScope { clients, platformUsers }

enum _StripePlanSection { individual, representacoes, enterprise, outros }

class _StripeCatalogImportSelection {
  const _StripeCatalogImportSelection({
    required this.section,
    required this.productId,
    required this.productName,
    required this.priceId,
    required this.lookupKey,
    required this.priceNickname,
    required this.unitAmount,
    required this.currency,
    required this.recurringInterval,
    required this.recurringIntervalCount,
    required this.planDisplayAmount,
    required this.suggestedSlug,
  });

  final _StripePlanSection section;
  final String productId;
  final String productName;
  final String priceId;
  final String lookupKey;
  final String priceNickname;
  final int unitAmount;
  final String currency;
  final String recurringInterval;
  final int recurringIntervalCount;
  final String planDisplayAmount;
  final String suggestedSlug;
}

enum _MaintainerUserAction {
  editProfile,
  editPermissionMatrix,
  deleteUser,
  toggleAccount,
  requestDeleteAccount,
  grant7days,
  grant30days,
  normalizeBilling,
  suspendBilling,
}

enum _MaintainerBillingAction {
  grant7days,
  grant30days,
  normalizeBilling,
  suspendBilling,
  requestCloseWorkspace,
  requestDeleteWorkspace,
}

enum _MaintainerUserSortField {
  user,
  uid,
  tenants,
  account,
  billing,
  graceUntil,
  updatedAt,
}
