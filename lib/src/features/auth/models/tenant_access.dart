class TenantAccess {
  const TenantAccess({
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
}