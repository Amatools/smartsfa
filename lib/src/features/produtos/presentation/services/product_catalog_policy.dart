class ProductCatalogPolicy {
  const ProductCatalogPolicy({
    required this.workspaceType,
    required this.role,
    required this.erpSyncEnabled,
    required this.allowCatalogWrite,
  });

  final String workspaceType;
  final String role;
  final bool erpSyncEnabled;
  final bool allowCatalogWrite;

  static ProductCatalogPolicy fromContext({
    required Map<String, dynamic>? tenantData,
    required String role,
    required bool isPersonalWorkspace,
    required bool isWebPlatform,
  }) {
    final normalizedRole = role.trim().toLowerCase();
    final workspaceType = isPersonalWorkspace
        ? 'seller_solo_workspace'
        : (tenantData?['workspaceType'] ?? '').toString().trim();
    final erpSyncEnabled =
        workspaceType == 'brand_owner_workspace' &&
        tenantData?['productSyncFromErpEnabled'] == true;

    return ProductCatalogPolicy(
      workspaceType: workspaceType,
      role: normalizedRole,
      erpSyncEnabled: erpSyncEnabled,
      allowCatalogWrite: isWebPlatform,
    );
  }

  bool get isEnterprise => workspaceType == 'brand_owner_workspace';

  bool get isOwnerOrPlatformAdmin =>
      role == 'owner' || role == 'platform_admin';

  bool get showEnterpriseSyncSwitchCard =>
      isEnterprise && isOwnerOrPlatformAdmin;

  bool get showErpManagedInfoCard => isEnterprise && erpSyncEnabled;

  bool get canCreateOrImportProducts {
    if (!allowCatalogWrite) {
      return false;
    }

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
