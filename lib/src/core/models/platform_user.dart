class PlatformUser {
  const PlatformUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.platformRole,
    required this.ativoGlobal,
    this.defaultTenantId,
    this.lastSelectedTenantId,
    this.activeMembershipCount,
  });

  final String uid;
  final String email;
  final String displayName;
  final String platformRole;
  final bool ativoGlobal;
  final String? defaultTenantId;
  final String? lastSelectedTenantId;
  final int? activeMembershipCount;
}
