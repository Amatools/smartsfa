import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/core/models/tenant_membership.dart';
import 'package:smartsfa/src/features/tenant/domain/tenant_admin_permissions.dart';

void main() {
  TenantMembership membership({
    required String uid,
    required String role,
  }) {
    return TenantMembership(
      membershipId: 'm_$uid',
      tenantId: 'tenant_a',
      uid: uid,
      role: role,
      ativo: true,
      defaultTenant: false,
      ownerId: '',
      gerenteId: '',
      representanteId: '',
      vendedorId: '',
      state: TenantMembershipState.active,
    );
  }

  test('owner can revoke vendedor but not owner', () {
    const permissions = TenantAdminPermissions(
      actorRole: 'owner',
      allowManagerDisableRepresentative: false,
      allowRepresentativeDisableSeller: true,
    );

    expect(
      permissions.canRevoke(
        membership(uid: 'v1', role: 'vendedor'),
        actorUid: 'owner1',
      ),
      isTrue,
    );

    expect(
      permissions.canRevoke(
        membership(uid: 'owner2', role: 'owner'),
        actorUid: 'owner1',
      ),
      isFalse,
    );
  });

  test('representante can revoke vendedor only when policy allows', () {
    const allowed = TenantAdminPermissions(
      actorRole: 'representante',
      allowManagerDisableRepresentative: false,
      allowRepresentativeDisableSeller: true,
    );
    const blocked = TenantAdminPermissions(
      actorRole: 'representante',
      allowManagerDisableRepresentative: false,
      allowRepresentativeDisableSeller: false,
    );

    expect(
      allowed.canRevoke(
        membership(uid: 'seller1', role: 'vendedor'),
        actorUid: 'rep1',
      ),
      isTrue,
    );

    expect(
      blocked.canRevoke(
        membership(uid: 'seller1', role: 'vendedor'),
        actorUid: 'rep1',
      ),
      isFalse,
    );
  });

  test('platform admin can change role to owner', () {
    const permissions = TenantAdminPermissions(
      actorRole: 'platform_admin',
      allowManagerDisableRepresentative: false,
      allowRepresentativeDisableSeller: true,
    );

    expect(
      permissions.canChangeRole(
        membership(uid: 'u2', role: 'vendedor'),
        actorUid: 'admin1',
        newRole: 'owner',
      ),
      isTrue,
    );
  });

  test('self-management is blocked', () {
    const permissions = TenantAdminPermissions(
      actorRole: 'owner',
      allowManagerDisableRepresentative: false,
      allowRepresentativeDisableSeller: true,
    );

    expect(
      permissions.canRevoke(
        membership(uid: 'owner1', role: 'owner'),
        actorUid: 'owner1',
      ),
      isFalse,
    );
  });
}
