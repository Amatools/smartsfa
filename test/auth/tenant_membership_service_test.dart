import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartsfa/src/features/auth/services/tenant_membership_service.dart';

void main() {
  group('TenantMembershipService', () {
    late FakeFirebaseFirestore firestore;
    late TenantMembershipService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = TenantMembershipService(firestore);
    });

    test('revoke and reactivate membership lifecycle', () async {
      await firestore.collection('tenant_memberships').doc('tenant1_u1').set({
        'membershipId': 'tenant1_u1',
        'tenantId': 'tenant1',
        'uid': 'u1',
        'role': 'vendedor',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'owner_1',
        'gerenteId': 'g1',
        'representanteId': 'r1',
        'vendedorId': 'u1',
        'state': 'active',
      });

      final revoked = await service.revokeMembership(
        membershipId: 'tenant1_u1',
        revokedByUid: 'owner_1',
        reason: 'Offboarding',
      );

      expect(revoked.ativo, isFalse);
      expect(revoked.state.value, 'revoked');

      final reactivated = await service.reactivateMembership(
        membershipId: 'tenant1_u1',
      );

      expect(reactivated.ativo, isTrue);
      expect(reactivated.state.value, 'active');

      final doc = await firestore
          .collection('tenant_memberships')
          .doc('tenant1_u1')
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['ativo'], isTrue);
      expect(doc.data()?['state'], 'active');
    });

    test('deactivate and reactivate membership lifecycle', () async {
      await firestore.collection('tenant_memberships').doc('tenant1_u2').set({
        'membershipId': 'tenant1_u2',
        'tenantId': 'tenant1',
        'uid': 'u2',
        'role': 'vendedor',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'owner_1',
        'gerenteId': 'g1',
        'representanteId': 'r1',
        'vendedorId': 'u2',
        'state': 'active',
      });

      final deactivated = await service.deactivateMembership(
        membershipId: 'tenant1_u2',
        deactivatedByUid: 'owner_1',
        reason: 'Ferias temporarias',
      );

      expect(deactivated.ativo, isFalse);
      expect(deactivated.state.value, 'inactive');

      final reactivated = await service.reactivateMembership(
        membershipId: 'tenant1_u2',
      );

      expect(reactivated.ativo, isTrue);
      expect(reactivated.state.value, 'active');
    });

    test('watchMembershipsForTenant returns filtered memberships', () async {
      await firestore.collection('tenant_memberships').doc('t1_u1').set({
        'membershipId': 't1_u1',
        'tenantId': 'tenant1',
        'uid': 'u1',
        'role': 'owner',
        'ativo': true,
        'defaultTenant': true,
        'ownerId': 'u1',
        'gerenteId': '',
        'representanteId': '',
        'vendedorId': '',
        'state': 'active',
      });

      await firestore.collection('tenant_memberships').doc('t2_u2').set({
        'membershipId': 't2_u2',
        'tenantId': 'tenant2',
        'uid': 'u2',
        'role': 'vendedor',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'u2',
        'gerenteId': '',
        'representanteId': '',
        'vendedorId': 'u2',
        'state': 'active',
      });

      final result = await service.watchMembershipsForTenant('tenant1').first;
      expect(result.length, 1);
      expect(result.first.tenantId, 'tenant1');
      expect(result.first.membershipId, 't1_u1');
    });

    test('changeRole updates role and writes audit log', () async {
      await firestore.collection('tenant_memberships').doc('tenant1_u10').set({
        'membershipId': 'tenant1_u10',
        'tenantId': 'tenant1',
        'uid': 'u10',
        'role': 'vendedor',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'owner_1',
        'gerenteId': 'g1',
        'representanteId': 'r1',
        'vendedorId': 'u10',
        'state': 'active',
      });

      final updated = await service.changeRole(
        membershipId: 'tenant1_u10',
        newRole: 'gerente',
        changedByUid: 'owner_1',
      );

      expect(updated.role, 'gerente');
      expect(updated.gerenteId, 'u10');
      expect(updated.representanteId, 'u10');
      expect(updated.vendedorId, 'u10');

      final auditSnapshot = await firestore
          .collection('tenant_membership_audit')
          .where('membershipId', isEqualTo: 'tenant1_u10')
          .where('action', isEqualTo: 'membership_role_changed')
          .get();

      expect(auditSnapshot.docs.isNotEmpty, isTrue);
      final details =
          auditSnapshot.docs.first.data()['details'] as Map<String, dynamic>?;
      expect(details?['oldRole'], 'vendedor');
      expect(details?['newRole'], 'gerente');

      final movementSnapshot = await firestore
          .collection('tenant_hierarchy_movements')
          .where('tenantId', isEqualTo: 'tenant1')
          .where('subjectUid', isEqualTo: 'u10')
          .get();
      expect(movementSnapshot.docs.length, 1);
      expect(movementSnapshot.docs.first.data()['actorUid'], 'owner_1');
      expect(
        movementSnapshot.docs.first.data()['reason'],
        'membership_role_changed:vendedor->gerente',
      );
    });

    test('revoke and reactivate write audit entries', () async {
      await firestore.collection('tenant_memberships').doc('tenant1_u30').set({
        'membershipId': 'tenant1_u30',
        'tenantId': 'tenant1',
        'uid': 'u30',
        'role': 'vendedor',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'owner_1',
        'gerenteId': 'g1',
        'representanteId': 'r1',
        'vendedorId': 'u30',
        'state': 'active',
      });

      await service.revokeMembership(
        membershipId: 'tenant1_u30',
        revokedByUid: 'owner_1',
      );
      await service.reactivateMembership(
        membershipId: 'tenant1_u30',
        reactivatedByUid: 'owner_1',
      );

      final revokedAudit = await firestore
          .collection('tenant_membership_audit')
          .where('membershipId', isEqualTo: 'tenant1_u30')
          .where('action', isEqualTo: 'membership_revoked')
          .get();
      final reactivatedAudit = await firestore
          .collection('tenant_membership_audit')
          .where('membershipId', isEqualTo: 'tenant1_u30')
          .where('action', isEqualTo: 'membership_reactivated')
          .get();

      expect(revokedAudit.docs.length, 1);
      expect(reactivatedAudit.docs.length, 1);
    });

    test('deactivate and reactivate write audit entries', () async {
      await firestore.collection('usuarios').doc('owner_1').set({
        'uid': 'owner_1',
        'displayName': 'Owner Um',
        'email': 'owner1@test.local',
        'platformRole': 'none',
      });

      await firestore.collection('tenant_memberships').doc('tenant1_u31').set({
        'membershipId': 'tenant1_u31',
        'tenantId': 'tenant1',
        'uid': 'u31',
        'role': 'vendedor',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'owner_1',
        'gerenteId': 'g1',
        'representanteId': 'r1',
        'vendedorId': 'u31',
        'state': 'active',
      });

      await service.deactivateMembership(
        membershipId: 'tenant1_u31',
        deactivatedByUid: 'owner_1',
      );
      await service.reactivateMembership(
        membershipId: 'tenant1_u31',
        reactivatedByUid: 'owner_1',
      );

      final deactivatedAudit = await firestore
          .collection('tenant_membership_audit')
          .where('membershipId', isEqualTo: 'tenant1_u31')
          .where('action', isEqualTo: 'membership_deactivated')
          .get();
      final reactivatedAudit = await firestore
          .collection('tenant_membership_audit')
          .where('membershipId', isEqualTo: 'tenant1_u31')
          .where('action', isEqualTo: 'membership_reactivated')
          .get();

      expect(deactivatedAudit.docs.length, 1);
      expect(reactivatedAudit.docs.length, 1);
      expect(
        deactivatedAudit.docs.first.data()['actorLabel'],
        'Owner Um <owner1@test.local>',
      );
    });

    test('leaveTenant allows vendedor self-offboarding', () async {
      await firestore.collection('tenant_memberships').doc('tenant1_u40').set({
        'membershipId': 'tenant1_u40',
        'tenantId': 'tenant1',
        'uid': 'u40',
        'role': 'vendedor',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'owner_1',
        'gerenteId': 'g1',
        'representanteId': 'r1',
        'vendedorId': 'u40',
        'state': 'active',
      });

      final left = await service.leaveTenant(
        membershipId: 'tenant1_u40',
        actorUid: 'u40',
      );

      expect(left.ativo, isFalse);
      expect(left.state.value, 'revoked');
    });

    test('leaveTenant blocks owner self-offboarding', () async {
      await firestore
          .collection('tenant_memberships')
          .doc('tenant1_owner1')
          .set({
            'membershipId': 'tenant1_owner1',
            'tenantId': 'tenant1',
            'uid': 'owner1',
            'role': 'owner',
            'ativo': true,
            'defaultTenant': true,
            'ownerId': 'owner1',
            'gerenteId': '',
            'representanteId': '',
            'vendedorId': '',
            'state': 'active',
          });

      expect(
        () => service.leaveTenant(
          membershipId: 'tenant1_owner1',
          actorUid: 'owner1',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('representante can revoke vendedor with default policy', () async {
      await firestore.collection('tenant_memberships').doc('tenant1_rep').set({
        'membershipId': 'tenant1_rep',
        'tenantId': 'tenant1',
        'uid': 'rep1',
        'role': 'representante',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'owner_1',
        'gerenteId': 'g1',
        'representanteId': 'rep1',
        'vendedorId': '',
        'state': 'active',
      });
      await firestore
          .collection('tenant_memberships')
          .doc('tenant1_seller')
          .set({
            'membershipId': 'tenant1_seller',
            'tenantId': 'tenant1',
            'uid': 'seller1',
            'role': 'vendedor',
            'ativo': true,
            'defaultTenant': false,
            'ownerId': 'owner_1',
            'gerenteId': 'g1',
            'representanteId': 'rep1',
            'vendedorId': 'seller1',
            'state': 'active',
          });

      final revoked = await service.revokeMembershipByActor(
        membershipId: 'tenant1_seller',
        actorUid: 'rep1',
      );

      expect(revoked.ativo, isFalse);
      expect(revoked.state.value, 'revoked');
    });

    test('gerente cannot revoke representante by default policy', () async {
      await firestore
          .collection('tenant_memberships')
          .doc('tenant1_manager')
          .set({
            'membershipId': 'tenant1_manager',
            'tenantId': 'tenant1',
            'uid': 'manager1',
            'role': 'gerente',
            'ativo': true,
            'defaultTenant': false,
            'ownerId': 'owner_1',
            'gerenteId': 'manager1',
            'representanteId': '',
            'vendedorId': '',
            'state': 'active',
          });
      await firestore
          .collection('tenant_memberships')
          .doc('tenant1_representative')
          .set({
            'membershipId': 'tenant1_representative',
            'tenantId': 'tenant1',
            'uid': 'rep1',
            'role': 'representante',
            'ativo': true,
            'defaultTenant': false,
            'ownerId': 'owner_1',
            'gerenteId': 'manager1',
            'representanteId': 'rep1',
            'vendedorId': '',
            'state': 'active',
          });

      expect(
        () => service.revokeMembershipByActor(
          membershipId: 'tenant1_representative',
          actorUid: 'manager1',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('owner cannot revoke representative with active seller', () async {
      await firestore.collection('usuarios').doc('owner_uid').set({
        'uid': 'owner_uid',
        'platformRole': 'none',
      });
      await firestore.collection('tenants').doc('tenant1').set({
        'tenantId': 'tenant1',
        'workspaceType': 'rep_workspace',
      });

      await firestore.collection('tenant_memberships').doc('tenant1_owner_uid').set({
        'membershipId': 'tenant1_owner_uid',
        'tenantId': 'tenant1',
        'uid': 'owner_uid',
        'role': 'owner',
        'ativo': true,
        'defaultTenant': true,
        'ownerId': 'owner_uid',
        'gerenteId': 'owner_uid',
        'representanteId': 'owner_uid',
        'vendedorId': 'owner_uid',
        'state': 'active',
      });
      await firestore.collection('tenant_memberships').doc('tenant1_rep_uid').set({
        'membershipId': 'tenant1_rep_uid',
        'tenantId': 'tenant1',
        'uid': 'rep_uid',
        'role': 'representante',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'owner_uid',
        'gerenteId': 'owner_uid',
        'representanteId': 'rep_uid',
        'vendedorId': 'rep_uid',
        'state': 'active',
      });
      await firestore.collection('tenant_memberships').doc('tenant1_seller_uid').set({
        'membershipId': 'tenant1_seller_uid',
        'tenantId': 'tenant1',
        'uid': 'seller_uid',
        'role': 'vendedor',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'owner_uid',
        'gerenteId': 'owner_uid',
        'representanteId': 'rep_uid',
        'vendedorId': 'seller_uid',
        'state': 'active',
      });

      expect(
        () => service.revokeMembershipByActor(
          membershipId: 'tenant1_rep_uid',
          actorUid: 'owner_uid',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('vendedores ativos'),
          ),
        ),
      );
    });

    test('owner cannot revoke manager with active representative', () async {
      await firestore.collection('usuarios').doc('owner_uid').set({
        'uid': 'owner_uid',
        'platformRole': 'none',
      });
      await firestore.collection('tenants').doc('tenant_ent').set({
        'tenantId': 'tenant_ent',
        'workspaceType': 'brand_owner_workspace',
      });

      await firestore.collection('tenant_memberships').doc('tenant_ent_owner_uid').set({
        'membershipId': 'tenant_ent_owner_uid',
        'tenantId': 'tenant_ent',
        'uid': 'owner_uid',
        'role': 'owner',
        'ativo': true,
        'defaultTenant': true,
        'ownerId': 'owner_uid',
        'gerenteId': 'owner_uid',
        'representanteId': 'owner_uid',
        'vendedorId': 'owner_uid',
        'state': 'active',
      });
      await firestore.collection('tenant_memberships').doc('tenant_ent_manager_uid').set({
        'membershipId': 'tenant_ent_manager_uid',
        'tenantId': 'tenant_ent',
        'uid': 'manager_uid',
        'role': 'gerente',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'owner_uid',
        'gerenteId': 'manager_uid',
        'representanteId': 'manager_uid',
        'vendedorId': 'manager_uid',
        'state': 'active',
      });
      await firestore.collection('tenant_memberships').doc('tenant_ent_rep_uid').set({
        'membershipId': 'tenant_ent_rep_uid',
        'tenantId': 'tenant_ent',
        'uid': 'rep_uid',
        'role': 'representante',
        'ativo': true,
        'defaultTenant': false,
        'ownerId': 'owner_uid',
        'gerenteId': 'manager_uid',
        'representanteId': 'rep_uid',
        'vendedorId': 'rep_uid',
        'state': 'active',
      });

      expect(
        () => service.revokeMembershipByActor(
          membershipId: 'tenant_ent_manager_uid',
          actorUid: 'owner_uid',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('equipe ativa'),
          ),
        ),
      );
    });
  });
}
