import '../../../core/models/tenant_membership.dart';

class TenantAdminPermissions {
  const TenantAdminPermissions({
    required this.actorRole,
    required this.allowManagerDisableRepresentative,
    required this.allowRepresentativeDisableSeller,
  });

  final String actorRole;
  final bool allowManagerDisableRepresentative;
  final bool allowRepresentativeDisableSeller;

  bool canRevoke(TenantMembership membership, {required String actorUid}) {
    if (membership.uid == actorUid) {
      return false;
    }

    if (actorRole == 'platform_admin') {
      return true;
    }

    final targetRole = membership.role.trim().toLowerCase();
    if (actorRole == 'owner') {
      return targetRole != 'owner' && targetRole != 'platform_admin';
    }

    if (actorRole == 'gerente') {
      return allowManagerDisableRepresentative && targetRole == 'representante';
    }

    if (actorRole == 'representante') {
      return allowRepresentativeDisableSeller && targetRole == 'vendedor';
    }

    return false;
  }

  bool canReactivate(TenantMembership membership, {required String actorUid}) {
    return canRevoke(membership, actorUid: actorUid);
  }

  bool canChangeRole(
    TenantMembership membership, {
    required String actorUid,
    required String newRole,
  }) {
    if (!canRevoke(membership, actorUid: actorUid)) {
      return false;
    }

    final normalizedNewRole = newRole.trim().toLowerCase();
    if (normalizedNewRole == membership.role.trim().toLowerCase()) {
      return false;
    }

    if (actorRole == 'platform_admin') {
      return const {'owner', 'gerente', 'representante', 'vendedor'}
          .contains(normalizedNewRole);
    }

    if (actorRole == 'owner') {
      return const {'gerente', 'representante', 'vendedor'}
          .contains(normalizedNewRole);
    }

    return false;
  }

  List<String> availableRoleTargets(
    TenantMembership membership, {
    required String actorUid,
  }) {
    final candidates = actorRole == 'platform_admin'
        ? const ['owner', 'gerente', 'representante', 'vendedor']
        : actorRole == 'owner'
            ? const ['gerente', 'representante', 'vendedor']
            : actorRole == 'gerente'
                ? const ['representante']
                : actorRole == 'representante'
                    ? const ['vendedor']
                    : const <String>[];

    return candidates
        .where(
          (role) => canChangeRole(
            membership,
            actorUid: actorUid,
            newRole: role,
          ),
        )
        .toList();
  }
}