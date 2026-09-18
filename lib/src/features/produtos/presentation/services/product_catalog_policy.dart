class ProductCatalogPolicy {
  const ProductCatalogPolicy({
    required this.workspaceType,
    required this.role,
    required this.erpSyncEnabled,
  });

  final String workspaceType;
  final String role;
  final bool erpSyncEnabled;

  static ProductCatalogPolicy fromContext({
    required Map<String, dynamic>? tenantData,
    required String role,
    required bool isPersonalWorkspace,
  }) {
    final normalizedRole = role.trim().toLowerCase();
    final workspaceType = isPersonalWorkspace
        ? 'seller_solo_workspace'
        : (tenantData?['workspaceType'] ?? '').toString().trim();
    final erpSyncEnabled =
        workspaceType == 'brand_owner_workspace' && tenantData?['productSyncFromErpEnabled'] == true;

    return ProductCatalogPolicy(
      workspaceType: workspaceType,
      role: normalizedRole,
      erpSyncEnabled: erpSyncEnabled,
    );
  }

  bool get isEnterprise => workspaceType == 'brand_owner_workspace';

  bool get isOwnerOrPlatformAdmin => role == 'owner' || role == 'platform_admin';

  bool get showEnterpriseSyncSwitchCard => isEnterprise && isOwnerOrPlatformAdmin;

  bool get showErpManagedInfoCard => isEnterprise && erpSyncEnabled;

  bool get canCreateOrImportProducts {
    if (erpSyncEnabled) {
      return false;
    }

    if (workspaceType == 'brand_owner_workspace') {
      return role == 'owner';
    }

    if (workspaceType == 'rep_workspace') {
      return role == 'owner';
    }

    if (workspaceType == 'seller_solo_workspace') {
      return role == 'owner';
    }

    return false;
  }
}
