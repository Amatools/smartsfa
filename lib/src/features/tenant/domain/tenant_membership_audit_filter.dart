class TenantMembershipAuditFilter {
  const TenantMembershipAuditFilter._();

  static String actionLabel(String action) {
    switch (action.trim().toLowerCase()) {
      case 'membership_revoked':
        return 'Membership revogado';
      case 'membership_reactivated':
        return 'Membership reativado';
      case 'membership_deactivated':
        return 'Membership inativado';
      case 'membership_role_changed':
        return 'Papel de membership alterado';
      case 'tenant_policy_updated':
        return 'Política do tenant atualizada';
      default:
        return action;
    }
  }

  static List<Map<String, dynamic>> apply({
    required List<Map<String, dynamic>> entries,
    required String query,
    required String selectedAction,
  }) {
    final normalizedQuery = query.trim().toLowerCase();

    return entries.where((entry) {
      final action = (entry['action'] ?? '').toString().toLowerCase();
      final actionLabelText = actionLabel(action).toLowerCase();
      final actorUid = (entry['actorUid'] ?? '').toString().toLowerCase();
      final membershipId = (entry['membershipId'] ?? '').toString().toLowerCase();

      final matchesAction =
          selectedAction == 'todos' || action == selectedAction;
      if (!matchesAction) {
        return false;
      }

      if (normalizedQuery.isEmpty) {
        return true;
      }

      return action.contains(normalizedQuery) ||
          actionLabelText.contains(normalizedQuery) ||
          actorUid.contains(normalizedQuery) ||
          membershipId.contains(normalizedQuery);
    }).toList();
  }
}