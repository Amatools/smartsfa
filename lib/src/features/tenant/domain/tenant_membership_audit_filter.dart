class TenantMembershipAuditFilter {
  const TenantMembershipAuditFilter._();

  static List<Map<String, dynamic>> apply({
    required List<Map<String, dynamic>> entries,
    required String query,
    required String selectedAction,
  }) {
    final normalizedQuery = query.trim().toLowerCase();

    return entries.where((entry) {
      final action = (entry['action'] ?? '').toString().toLowerCase();
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
          actorUid.contains(normalizedQuery) ||
          membershipId.contains(normalizedQuery);
    }).toList();
  }
}