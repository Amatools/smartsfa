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

class DevAccessSession {
  const DevAccessSession({
    required this.tenant,
    required this.role,
    required this.userEmail,
  });

  final DevTenant tenant;
  final DevRole role;
  final String userEmail;
}

class DevTenant {
  const DevTenant({required this.id, required this.name});

  final String id;
  final String name;
}

enum DevRole {
  platformAdmin('platform_admin', 'Platform Admin'),
  owner('owner', 'Owner'),
  gerente('gerente', 'Gerente'),
  representante('representante', 'Representante'),
  vendedor('vendedor', 'Vendedor');

  const DevRole(this.name, this.label);

  final String name;
  final String label;
}
