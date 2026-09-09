import '../../../auth/services/tenant_membership_service.dart';

class TenantAdminActionController {
  const TenantAdminActionController(this._membershipService);

  final TenantMembershipService _membershipService;

  Future<Map<String, bool>> savePolicy({
    required String tenantId,
    required bool allowManagerDisableRepresentative,
    required bool allowRepresentativeDisableSeller,
    required String updatedByUid,
  }) async {
    await _membershipService.updateGovernancePolicy(
      tenantId: tenantId,
      allowManagerDisableRepresentative: allowManagerDisableRepresentative,
      allowRepresentativeDisableSeller: allowRepresentativeDisableSeller,
      allowPersonalWorkspace: true,
      updatedByUid: updatedByUid,
    );

    return {
      'allowManagerDisableRepresentative': allowManagerDisableRepresentative,
      'allowRepresentativeDisableSeller': allowRepresentativeDisableSeller,
    };
  }

  Future<void> revokeMembership({
    required String membershipId,
    required String actorUid,
  }) {
    return _membershipService.revokeMembershipByActor(
      membershipId: membershipId,
      actorUid: actorUid,
    );
  }

  Future<void> reactivateMembership({
    required String membershipId,
    required String actorUid,
  }) {
    return _membershipService.reactivateMembershipByActor(
      membershipId: membershipId,
      actorUid: actorUid,
    );
  }

  Future<void> changeRole({
    required String membershipId,
    required String newRole,
    required String actorUid,
  }) {
    return _membershipService.changeRoleByActor(
      membershipId: membershipId,
      newRole: newRole,
      actorUid: actorUid,
    );
  }
}