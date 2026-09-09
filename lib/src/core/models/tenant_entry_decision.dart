import 'domain_types.dart';

class TenantEntryOption {
  const TenantEntryOption({
    required this.membershipId,
    required this.tenantId,
    required this.tenantName,
    required this.role,
    required this.defaultTenant,
  });

  final String membershipId;
  final String tenantId;
  final String tenantName;
  final String role;
  final bool defaultTenant;

  Map<String, Object?> toMap() {
    return {
      'membershipId': membershipId,
      'tenantId': tenantId,
      'tenantName': tenantName,
      'role': role,
      'defaultTenant': defaultTenant,
    };
  }
}

class TenantEntryDecision {
  const TenantEntryDecision({
    required this.uid,
    required this.path,
    required this.options,
    this.selectedTenantId,
    this.defaultTenantId,
    this.personalWorkspaceEnabled = true,
  });

  factory TenantEntryDecision.direct({
    required String uid,
    required String tenantId,
    required String tenantName,
    required String role,
    required String defaultTenantId,
  }) {
    return TenantEntryDecision(
      uid: uid,
      path: TenantEntryPath.directTenant,
      options: [
        TenantEntryOption(
          membershipId: 'direct',
          tenantId: tenantId,
          tenantName: tenantName,
          role: role,
          defaultTenant: true,
        ),
      ],
      selectedTenantId: tenantId,
      defaultTenantId: defaultTenantId,
    );
  }

  factory TenantEntryDecision.selector({
    required String uid,
    required List<String> availableTenantIds,
    String? defaultTenantId,
  }) {
    return TenantEntryDecision(
      uid: uid,
      path: TenantEntryPath.selector,
      options: availableTenantIds
          .map(
            (tenantId) => TenantEntryOption(
              membershipId: tenantId,
              tenantId: tenantId,
              tenantName: tenantId,
              role: 'member',
              defaultTenant: defaultTenantId == tenantId,
            ),
          )
          .toList(),
      defaultTenantId: defaultTenantId,
    );
  }

  factory TenantEntryDecision.requestAccess({
    required String uid,
    bool personalWorkspaceEnabled = true,
  }) {
    return TenantEntryDecision(
      uid: uid,
      path: TenantEntryPath.requestAccess,
      options: const [],
      personalWorkspaceEnabled: personalWorkspaceEnabled,
    );
  }

  factory TenantEntryDecision.personalWorkspace({
    required String uid,
  }) {
    return TenantEntryDecision(
      uid: uid,
      path: TenantEntryPath.personalWorkspace,
      options: const [],
      personalWorkspaceEnabled: true,
    );
  }

  final String uid;
  final TenantEntryPath path;
  final List<TenantEntryOption> options;
  final String? selectedTenantId;
  final String? defaultTenantId;
  final bool personalWorkspaceEnabled;

  Map<String, Object?> toMap() {
    return {
      'uid': uid,
      'path': path.value,
      'options': options.map((option) => option.toMap()).toList(),
      'selectedTenantId': selectedTenantId,
      'defaultTenantId': defaultTenantId,
      'personalWorkspaceEnabled': personalWorkspaceEnabled,
    };
  }
}