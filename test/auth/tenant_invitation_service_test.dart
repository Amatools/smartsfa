import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartsfa/src/core/models/tenant_invitation.dart';
import 'package:smartsfa/src/features/auth/services/tenant_invitation_service.dart';

void main() {
  group('TenantInvitationService', () {
    late FakeFirebaseFirestore firestore;
    late TenantInvitationService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = TenantInvitationService(firestore);
    });

    test('creates and revokes invitation', () async {
      await _seedOwnerMembership(
        firestore,
        tenantId: 'tenant_a',
        uid: 'owner_1',
      );

      final invitation = await service.createInvitation(
        tenantId: 'tenant_a',
        role: 'vendedor',
        createdByUid: 'owner_1',
        invitedEmail: 'rep@empresa.com',
        defaultTenant: true,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );

      expect(invitation.status, TenantInvitationStatus.pending);
      expect(invitation.tenantId, 'tenant_a');
      expect(invitation.invitedEmail, 'rep@empresa.com');

      await service.revokeInvitation(
        token: invitation.token,
        revokedByUid: 'owner_1',
      );

      final doc = await firestore
          .collection('tenant_invitations')
          .doc(invitation.token)
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['status'], TenantInvitationStatus.revoked.value);
    });

    test('accepts valid invitation and creates membership', () async {
      await _seedOwnerMembership(
        firestore,
        tenantId: 'tenant_b',
        uid: 'owner_2',
      );

      final invitation = await service.createInvitation(
        tenantId: 'tenant_b',
        role: 'gerente',
        createdByUid: 'owner_2',
        invitedEmail: 'gestor@empresa.com',
        defaultTenant: true,
        expiresAt: DateTime.now().add(const Duration(days: 3)),
      );

      final user = MockUser(uid: 'u_1', email: 'gestor@empresa.com');
      final membership = await service.acceptInvitation(
        user: user,
        token: invitation.token,
      );

      expect(membership.uid, 'u_1');
      expect(membership.tenantId, 'tenant_b');
      expect(membership.role, 'gerente');

      final membershipDoc = await firestore
          .collection('tenant_memberships')
          .doc('tenant_b_u_1')
          .get();
      expect(membershipDoc.exists, isTrue);
      expect(membershipDoc.data()?['state'], 'active');

      final invitationDoc = await firestore
          .collection('tenant_invitations')
          .doc(invitation.token)
          .get();
      expect(
        invitationDoc.data()?['status'],
        TenantInvitationStatus.accepted.value,
      );
    });

    test('rejects expired invitation', () async {
      await _seedOwnerMembership(
        firestore,
        tenantId: 'tenant_c',
        uid: 'owner_3',
      );

      final invitation = await service.createInvitation(
        tenantId: 'tenant_c',
        role: 'vendedor',
        createdByUid: 'owner_3',
        invitedEmail: 'user@empresa.com',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      final user = MockUser(uid: 'u_2', email: 'user@empresa.com');

      expect(
        () => service.acceptInvitation(user: user, token: invitation.token),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects invitation for different email', () async {
      await _seedOwnerMembership(
        firestore,
        tenantId: 'tenant_d',
        uid: 'owner_4',
      );

      final invitation = await service.createInvitation(
        tenantId: 'tenant_d',
        role: 'representante',
        createdByUid: 'owner_4',
        invitedEmail: 'destino@empresa.com',
      );

      final user = MockUser(uid: 'u_3', email: 'outro@empresa.com');

      expect(
        () => service.acceptInvitation(user: user, token: invitation.token),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects invitation not pending', () async {
      await _seedOwnerMembership(
        firestore,
        tenantId: 'tenant_e',
        uid: 'owner_5',
      );

      final invitation = await service.createInvitation(
        tenantId: 'tenant_e',
        role: 'vendedor',
        createdByUid: 'owner_5',
        invitedEmail: 'vendedor@empresa.com',
      );

      await service.revokeInvitation(
        token: invitation.token,
        revokedByUid: 'owner_5',
      );

      final user = MockUser(uid: 'u_4', email: 'vendedor@empresa.com');

      expect(
        () => service.acceptInvitation(user: user, token: invitation.token),
        throwsA(isA<StateError>()),
      );
    });

    test('declines pending invitation', () async {
      await _seedOwnerMembership(
        firestore,
        tenantId: 'tenant_f',
        uid: 'owner_6',
      );

      final invitation = await service.createInvitation(
        tenantId: 'tenant_f',
        role: 'vendedor',
        createdByUid: 'owner_6',
        invitedEmail: 'vendedor2@empresa.com',
      );

      await service.declineInvitation(
        token: invitation.token,
        declinedByUid: 'u_6',
      );

      final doc = await firestore
          .collection('tenant_invitations')
          .doc(invitation.token)
          .get();
      expect(doc.data()?['status'], TenantInvitationStatus.declined.value);
      expect(doc.data()?['declinedByUid'], 'u_6');
    });

    test('blocks create invitation for non-owner', () async {
      await firestore
          .collection('tenant_memberships')
          .doc('tenant_g_user_7')
          .set({
            'membershipId': 'tenant_g_user_7',
            'tenantId': 'tenant_g',
            'uid': 'user_7',
            'role': 'vendedor',
            'ativo': true,
            'defaultTenant': false,
            'ownerId': 'owner_g',
            'gerenteId': '',
            'representanteId': '',
            'vendedorId': 'user_7',
            'state': 'active',
          });

      expect(
        () => service.createInvitation(
          tenantId: 'tenant_g',
          role: 'vendedor',
          createdByUid: 'user_7',
          invitedEmail: 'novo@empresa.com',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'non-owner cannot revoke invitation created by another actor',
      () async {
        await _seedOwnerMembership(
          firestore,
          tenantId: 'tenant_h',
          uid: 'owner_h',
        );
        await _seedRepresentativeMembership(
          firestore,
          tenantId: 'tenant_h',
          uid: 'rep_h',
          ownerUid: 'owner_h',
        );

        final invitation = await service.createInvitation(
          tenantId: 'tenant_h',
          role: 'vendedor',
          createdByUid: 'owner_h',
          invitedEmail: 'seller-h@empresa.com',
        );

        expect(
          () => service.revokeInvitation(
            token: invitation.token,
            revokedByUid: 'rep_h',
          ),
          throwsA(isA<StateError>()),
        );

        final doc = await firestore
            .collection('tenant_invitations')
            .doc(invitation.token)
            .get();
        expect(doc.data()?['status'], TenantInvitationStatus.pending.value);
      },
    );

    test('owner can revoke invitation created by another actor', () async {
      await _seedTenant(
        firestore,
        tenantId: 'tenant_i',
        workspaceType: 'brand_owner_workspace',
        allowRepresentativeSendInvites: true,
      );
      await _seedOwnerMembership(
        firestore,
        tenantId: 'tenant_i',
        uid: 'owner_i',
      );
      await _seedRepresentativeMembership(
        firestore,
        tenantId: 'tenant_i',
        uid: 'rep_i',
        ownerUid: 'owner_i',
      );

      final invitation = await service.createInvitation(
        tenantId: 'tenant_i',
        role: 'vendedor',
        createdByUid: 'rep_i',
        invitedEmail: 'seller-i@empresa.com',
      );

      await service.revokeInvitation(
        token: invitation.token,
        revokedByUid: 'owner_i',
      );

      final doc = await firestore
          .collection('tenant_invitations')
          .doc(invitation.token)
          .get();
      expect(doc.data()?['status'], TenantInvitationStatus.revoked.value);
      expect(doc.data()?['revokedByUid'], 'owner_i');
    });

    test('manager cannot invite by default policy', () async {
      await _seedTenant(
        firestore,
        tenantId: 'tenant_j',
        workspaceType: 'brand_owner_workspace',
      );
      await _seedOwnerMembership(
        firestore,
        tenantId: 'tenant_j',
        uid: 'owner_j',
      );
      await _seedManagerMembership(
        firestore,
        tenantId: 'tenant_j',
        uid: 'manager_j',
        ownerUid: 'owner_j',
      );

      expect(
        () => service.createInvitation(
          tenantId: 'tenant_j',
          role: 'representante',
          createdByUid: 'manager_j',
          invitedEmail: 'rep-j@empresa.com',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('manager can invite when owner enables policy', () async {
      await _seedTenant(
        firestore,
        tenantId: 'tenant_k',
        workspaceType: 'brand_owner_workspace',
        allowManagerSendInvites: true,
      );
      await _seedOwnerMembership(
        firestore,
        tenantId: 'tenant_k',
        uid: 'owner_k',
      );
      await _seedManagerMembership(
        firestore,
        tenantId: 'tenant_k',
        uid: 'manager_k',
        ownerUid: 'owner_k',
      );

      final invitation = await service.createInvitation(
        tenantId: 'tenant_k',
        role: 'representante',
        createdByUid: 'manager_k',
        invitedEmail: 'rep-k@empresa.com',
      );

      expect(invitation.createdByUid, 'manager_k');
      expect(invitation.role, 'representante');
    });
  });
}

Future<void> _seedTenant(
  FakeFirebaseFirestore firestore, {
  required String tenantId,
  required String workspaceType,
  bool allowManagerSendInvites = false,
  bool allowRepresentativeSendInvites = false,
}) {
  return firestore.collection('tenants').doc(tenantId).set({
    'tenantId': tenantId,
    'slug': tenantId,
    'nomeFantasia': tenantId,
    'ativo': true,
    'operationMode': 'manual',
    'erpProvider': 'none',
    'workspaceType': workspaceType,
    'hierarchyModel': workspaceType == 'rep_workspace'
        ? 'rep_to_seller'
        : 'full_chain',
    'allowInvitations': workspaceType != 'seller_solo_workspace',
    'cnpjBinding': workspaceType == 'brand_owner_workspace'
        ? 'owner_legal_entity'
        : 'informational_only',
    'policy': {
      'allowManagerDisableRepresentative': false,
      'allowRepresentativeDisableSeller': true,
      'allowManagerSendInvites': allowManagerSendInvites,
      'allowRepresentativeSendInvites': allowRepresentativeSendInvites,
      'allowPersonalWorkspace': true,
    },
  });
}

Future<void> _seedOwnerMembership(
  FakeFirebaseFirestore firestore, {
  required String tenantId,
  required String uid,
}) {
  return firestore.collection('tenant_memberships').doc('${tenantId}_$uid').set(
    {
      'membershipId': '${tenantId}_$uid',
      'tenantId': tenantId,
      'uid': uid,
      'role': 'owner',
      'ativo': true,
      'defaultTenant': true,
      'ownerId': uid,
      'gerenteId': uid,
      'representanteId': uid,
      'vendedorId': uid,
      'state': 'active',
    },
  );
}

Future<void> _seedRepresentativeMembership(
  FakeFirebaseFirestore firestore, {
  required String tenantId,
  required String uid,
  required String ownerUid,
}) {
  return firestore.collection('tenant_memberships').doc('${tenantId}_$uid').set(
    {
      'membershipId': '${tenantId}_$uid',
      'tenantId': tenantId,
      'uid': uid,
      'role': 'representante',
      'ativo': true,
      'defaultTenant': false,
      'ownerId': ownerUid,
      'gerenteId': ownerUid,
      'representanteId': uid,
      'vendedorId': uid,
      'state': 'active',
    },
  );
}

Future<void> _seedManagerMembership(
  FakeFirebaseFirestore firestore, {
  required String tenantId,
  required String uid,
  required String ownerUid,
}) {
  return firestore.collection('tenant_memberships').doc('${tenantId}_$uid').set(
    {
      'membershipId': '${tenantId}_$uid',
      'tenantId': tenantId,
      'uid': uid,
      'role': 'gerente',
      'ativo': true,
      'defaultTenant': false,
      'ownerId': ownerUid,
      'gerenteId': uid,
      'representanteId': uid,
      'vendedorId': uid,
      'state': 'active',
    },
  );
}
