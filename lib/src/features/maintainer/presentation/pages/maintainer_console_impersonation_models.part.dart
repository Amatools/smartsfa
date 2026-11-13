part of 'maintainer_console_page.dart';

class _ImpersonationResolvedSelection {
  const _ImpersonationResolvedSelection({
    required this.selectedUid,
    required this.selectedUser,
    required this.normalizedMemberships,
    required this.selectedMembershipId,
    required this.selectedMembership,
  });

  final String selectedUid;
  final MaintainerUserAccount selectedUser;
  final List<MaintainerUserTenantMembership> normalizedMemberships;
  final String? selectedMembershipId;
  final MaintainerUserTenantMembership? selectedMembership;
}
