import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/tenant_entry_decision.dart';
import '../../../../shared/utils/window_open.dart';
import '../../domain/maintainer_access_decision.dart';
import '../../services/maintainer_access_service.dart';
import '../../services/maintainer_audit_service.dart';
import '../../services/maintainer_billing_integration_service.dart';
import '../../services/maintainer_impersonation_service.dart';
import '../../services/maintainer_overview_service.dart';
import '../../services/maintainer_user_admin_service.dart';

part 'maintainer_console_user_dialogs.part.dart';
part 'maintainer_console_stripe.part.dart';
part 'maintainer_console_stripe_config_dialog.part.dart';
part 'maintainer_console_stripe_plan_mapping_dialog_models.part.dart';
part 'maintainer_console_stripe_plan_mapping_dialog_ui.part.dart';
part 'maintainer_console_stripe_plan_mapping_dialog_catalog_ui.part.dart';
part 'maintainer_console_stripe_plan_mapping_dialog_helpers.part.dart';
part 'maintainer_console_stripe_plan_mapping_dialog.part.dart';
part 'maintainer_console_users.part.dart';
part 'maintainer_console_users_filters.part.dart';
part 'maintainer_console_users_table_models.part.dart';
part 'maintainer_console_users_table_ui.part.dart';
part 'maintainer_console_users_table_row_ui.part.dart';
part 'maintainer_console_users_table.part.dart';
part 'maintainer_console_billing.part.dart';
part 'maintainer_console_audit.part.dart';
part 'maintainer_console_impersonation_models.part.dart';
part 'maintainer_console_impersonation_ui.part.dart';
part 'maintainer_console_impersonation.part.dart';
part 'maintainer_console_home.part.dart';
part 'maintainer_console_helpers.part.dart';
part 'maintainer_console_access.part.dart';
part 'maintainer_console_types.part.dart';
part 'maintainer_console_build.part.dart';
part 'maintainer_console_gate.part.dart';
part 'maintainer_console_user_actions.part.dart';
part 'maintainer_console_stripe_plans.part.dart';
part 'maintainer_console_stripe_catalog.part.dart';
part 'maintainer_console_stripe_helpers.part.dart';
part 'maintainer_console_user_permissions.part.dart';

class MaintainerConsolePage extends StatefulWidget {
  const MaintainerConsolePage({
    super.key,
    this.activeTenant,
    this.membershipRoleOverride,
  });

  final TenantEntryOption? activeTenant;
  final String? membershipRoleOverride;

  @override
  State<MaintainerConsolePage> createState() => _MaintainerConsolePageState();
}

class _MaintainerConsolePageState extends State<MaintainerConsolePage> {
  static const String _defaultFirebaseProjectId = 'smart-sfa';
  static const String _defaultCloudFunctionsRegion = 'us-central1';
  static const String _defaultStripeWebhookFunctionName = 'handleStripeWebhook';
  static const List<String> _defaultStripeWebhookEvents = [
    'checkout.session.completed',
    'customer.subscription.created',
    'customer.subscription.updated',
    'customer.subscription.deleted',
    'invoice.finalized',
    'invoice.paid',
    'invoice.payment_failed',
  ];

  late final MaintainerAccessService _accessService;
  late final MaintainerAuditService _auditService;
  late final MaintainerImpersonationService _impersonationService;
  late final MaintainerBillingIntegrationService _billingIntegrationService;
  late final MaintainerOverviewService _overviewService;
  late final MaintainerUserAdminService _userAdminService;
  late final Stream<List<MaintainerCriticalAuditEntry>> _criticalAuditStream;

  late Future<MaintainerAccessDecision> _accessFuture;
  Future<MaintainerOverviewSnapshot>? _overviewFuture;

  _MaintainerConsoleTab _activeTab = _MaintainerConsoleTab.home;
  String? _selectedTenantId;
  _MaintainerUserSortField _userSortField = _MaintainerUserSortField.user;
  bool _userSortAscending = true;
  int _usersRowsPerPage = 20;
  int _usersPageIndex = 0;
  String _billingStatusFilter = '';
  int _billingRowsPerPage = 20;
  int _billingPageIndex = 0;

  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _billingSearchController =
      TextEditingController();
  final TextEditingController _auditSearchController = TextEditingController();
  final TextEditingController _impersonationTargetSearchController =
      TextEditingController();
  final TextEditingController _impersonationReasonController =
      TextEditingController();

  final Set<String> _processingUserIds = <String>{};
  final Set<String> _processingBillingTenantIds = <String>{};
  String? _impersonationSelectedUid;
  String? _impersonationSelectedMembershipId;
  int _impersonationDurationMinutes = 15;
  bool _impersonationLaunching = false;
  String _impersonationLaunchStatus = '';

  @override
  void initState() {
    super.initState();
    _initializeMaintainerDependencies();
    _reloadAccess();
  }

  @override
  void dispose() {
    _disposeMainControllers();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MaintainerConsolePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_membershipRoleChanged(oldWidget, widget)) {
      _reloadAccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _buildAccessGatedBody(textTheme: textTheme);
  }

  static const List<String> _maintainerRoleOptions = [
    'none',
    'platform_observer',
    'platform_operator',
    'platform_admin',
  ];

  void _reloadOverview() {
    setState(() {
      _overviewFuture = _overviewService.loadSnapshot();
    });
  }

  void _markUserProcessing(String uid) {
    setState(() {
      _processingUserIds.add(uid);
    });
  }

  void _unmarkUserProcessing(String uid) {
    if (!mounted) {
      return;
    }
    setState(() {
      _processingUserIds.remove(uid);
    });
  }

  void _markBillingTenantProcessing(String tenantId) {
    setState(() {
      _processingBillingTenantIds.add(tenantId.trim());
    });
  }

  void _unmarkBillingTenantProcessing(String tenantId) {
    if (!mounted) {
      return;
    }
    setState(() {
      _processingBillingTenantIds.remove(tenantId.trim());
    });
  }

  void _resetUsersPageIndex() {
    setState(() {
      _usersPageIndex = 0;
    });
  }

  void _applyUserTenantFilter(String? selectedTenantId) {
    setState(() {
      _selectedTenantId = selectedTenantId;
      _usersPageIndex = 0;
    });
  }

  void _updateUsersTableState(VoidCallback updater) {
    setState(updater);
  }

  void _resetBillingPageIndex() {
    setState(() {
      _billingPageIndex = 0;
    });
  }

  void _applyBillingStatusFilter(String status) {
    setState(() {
      _billingStatusFilter = status.trim();
      _billingPageIndex = 0;
    });
  }

  void _updateBillingTableState(VoidCallback updater) {
    setState(updater);
  }

  void _refreshAuditFilters() {
    setState(() {});
  }

  void _updateImpersonationState(VoidCallback updater) {
    setState(updater);
  }

  void _setActiveTab(_MaintainerConsoleTab tab) {
    setState(() {
      _activeTab = tab;
    });
  }
}
