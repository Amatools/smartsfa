import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/features/auth/services/tenant_invitation_service.dart';
import 'package:smartsfa/src/features/notificacoes/presentation/controllers/notification_invitation_action_controller.dart';

void main() {
  group('NotificationInvitationActionController', () {
    late FakeFirebaseFirestore firestore;
    late TenantInvitationService service;
    late NotificationInvitationActionController controller;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = TenantInvitationService(firestore);
      controller = NotificationInvitationActionController(service);
    });

    test('accepts invitation through controller', () async {
      await _seedOwnerMembership(
        firestore,
        tenantId: 'tenant_n',
        uid: 'owner_n',
      );

      final invitation = await service.createInvitation(
        tenantId: 'tenant_n',
        role: 'vendedor',
        createdByUid: 'owner_n',
        invitedEmail: 'user@empresa.com',
      );

      final user = MockUser(uid: 'user_1', email: 'user@empresa.com');
      await controller.acceptInvitation(user: user, token: invitation.token);

      final invitationDoc = await firestore
          .collection('tenant_invitations')
          .doc(invitation.token)
          .get();
      expect(invitationDoc.data()?['status'], 'accepted');
    });

    test('declines invitation through controller', () async {
      await _seedOwnerMembership(
        firestore,
        tenantId: 'tenant_m',
        uid: 'owner_m',
      );

      final invitation = await service.createInvitation(
        tenantId: 'tenant_m',
        role: 'representante',
        createdByUid: 'owner_m',
        invitedEmail: 'rep@empresa.com',
      );

      await controller.declineInvitation(
        token: invitation.token,
        declinedByUid: 'user_2',
      );

      final invitationDoc = await firestore
          .collection('tenant_invitations')
          .doc(invitation.token)
          .get();
      expect(invitationDoc.data()?['status'], 'declined');
      expect(invitationDoc.data()?['declinedByUid'], 'user_2');
    });
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
      'gerenteId': '',
      'representanteId': '',
      'vendedorId': '',
      'state': 'active',
    },
  );
}
