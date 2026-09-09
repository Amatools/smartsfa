import '../../../core/models/tenant_membership.dart';

class TenantMembershipFilter {
  const TenantMembershipFilter._();

  static List<TenantMembership> apply({
    required List<TenantMembership> memberships,
    required String query,
    required String selectedRole,
    required String selectedStatus,
  }) {
    final normalizedQuery = query.trim().toLowerCase();

    return memberships.where((membership) {
      final role = membership.role.trim().toLowerCase();
      final status = membership.isActive
          ? 'ativo'
          : membership.state == TenantMembershipState.revoked
              ? 'revogado'
              : 'inativo';

      final matchesRole = selectedRole == 'todos' || role == selectedRole;
      final matchesStatus = selectedStatus == 'todos' || status == selectedStatus;

      if (!matchesRole || !matchesStatus) {
        return false;
      }

      if (normalizedQuery.isEmpty) {
        return true;
      }

      return membership.uid.toLowerCase().contains(normalizedQuery) ||
          membership.membershipId.toLowerCase().contains(normalizedQuery) ||
          role.contains(normalizedQuery);
    }).toList();
  }
}