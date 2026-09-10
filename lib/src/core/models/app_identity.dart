class AppIdentity {
  const AppIdentity({
    required this.tenantId,
    required this.userLabel,
    required this.role,
    required this.tenantName,
    required this.isMock,
    this.membershipId,
    this.isPersonalWorkspace = false,
  });

  final String tenantId;
  final String userLabel;
  final String role;
  final String tenantName;
  final bool isMock;
  final String? membershipId;
  final bool isPersonalWorkspace;
}
