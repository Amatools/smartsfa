part of 'maintainer_console_page.dart';

extension _MaintainerConsoleAccessPart on _MaintainerConsolePageState {
  void _initializeMaintainerDependencies() {
    final firestore = FirebaseFirestore.instance;
    _accessService = MaintainerAccessService(firestore);
    _auditService = MaintainerAuditService(firestore);
    _impersonationService = MaintainerImpersonationService();
    _billingIntegrationService = MaintainerBillingIntegrationService(firestore);
    _overviewService = MaintainerOverviewService(firestore);
    _userAdminService = MaintainerUserAdminService(firestore);
    _criticalAuditStream = _auditService
        .watchCriticalEvents(limit: 400)
        .asBroadcastStream();
  }

  void _disposeMainControllers() {
    _userSearchController.dispose();
    _billingSearchController.dispose();
    _auditSearchController.dispose();
    _impersonationTargetSearchController.dispose();
    _impersonationReasonController.dispose();
  }

  bool _membershipRoleChanged(
    MaintainerConsolePage oldWidget,
    MaintainerConsolePage newWidget,
  ) {
    return _resolvedMembershipRole(oldWidget) !=
        _resolvedMembershipRole(newWidget);
  }

  String _resolvedMembershipRole(MaintainerConsolePage widgetValue) {
    final override = (widgetValue.membershipRoleOverride ?? '').trim();
    if (override.isNotEmpty) {
      return override;
    }
    return (widgetValue.activeTenant?.role ?? '').trim();
  }

  void _reloadAccess() {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    _accessFuture = _accessService.evaluateAccess(
      uid: uid,
      membershipRole: _resolvedMembershipRole(widget),
    );
    _overviewFuture = null;
  }

  bool _canAccessStripeTab(MaintainerAccessDecision decision) {
    final canViewBillingIntegrations = decision.can(
      MaintainerPermission.viewBillingIntegrations,
    );
    final canManageBillingIntegrations = decision.can(
      MaintainerPermission.manageBillingIntegrations,
    );
    return canViewBillingIntegrations || canManageBillingIntegrations;
  }

  _MaintainerConsoleTab _resolveActiveTabForPermissions({
    required bool canViewUsers,
    required bool canViewAudit,
    required bool canManageImpersonation,
    required bool canAccessStripeTab,
  }) {
    return switch (_activeTab) {
      _MaintainerConsoleTab.home => _MaintainerConsoleTab.home,
      _MaintainerConsoleTab.billing =>
        canViewUsers
            ? _MaintainerConsoleTab.billing
            : _MaintainerConsoleTab.home,
      _MaintainerConsoleTab.clients =>
        canViewUsers
            ? _MaintainerConsoleTab.clients
            : _MaintainerConsoleTab.home,
      _MaintainerConsoleTab.users =>
        canViewUsers ? _MaintainerConsoleTab.users : _MaintainerConsoleTab.home,
      _MaintainerConsoleTab.audit =>
        canViewAudit ? _MaintainerConsoleTab.audit : _MaintainerConsoleTab.home,
      _MaintainerConsoleTab.impersonation =>
        canManageImpersonation
            ? _MaintainerConsoleTab.impersonation
            : _MaintainerConsoleTab.home,
      _MaintainerConsoleTab.stripe =>
        canAccessStripeTab
            ? _MaintainerConsoleTab.stripe
            : _MaintainerConsoleTab.home,
    };
  }

  bool _hasAnyVisibleModule({
    required bool canViewHome,
    required bool canViewUsers,
    required bool canManageImpersonation,
    required bool canAccessStripeTab,
  }) {
    return canViewHome ||
        canViewUsers ||
        canManageImpersonation ||
        canAccessStripeTab;
  }
}
