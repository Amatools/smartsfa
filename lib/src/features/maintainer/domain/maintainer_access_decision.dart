class MaintainerPermission {
  static const String viewHome = 'maintainer.view.home';
  static const String viewOverview = 'maintainer.view.overview';
  static const String viewUsers = 'maintainer.view.users';
  static const String manageUserStatus = 'maintainer.manage.user_status';
  static const String manageUserBilling = 'maintainer.manage.user_billing';
  static const String manageUserCrud = 'maintainer.manage.user_crud';
  static const String manageUserPermissions =
      'maintainer.manage.user_permissions';
    static const String manageImpersonation =
      'maintainer.manage.impersonation';

  static const Set<String> all = {
    viewHome,
    viewOverview,
    viewUsers,
    manageUserStatus,
    manageUserBilling,
    manageUserCrud,
    manageUserPermissions,
    manageImpersonation,
  };
}

class MaintainerAccessDecision {
  const MaintainerAccessDecision({
    required this.granted,
    required this.effectiveRole,
    required this.reason,
    required this.grantedPermissions,
  });

  final bool granted;
  final String effectiveRole;
  final String reason;
  final Set<String> grantedPermissions;

  bool can(String permission) {
    return granted && grantedPermissions.contains(permission);
  }
}
