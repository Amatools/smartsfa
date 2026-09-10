import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/features/auth/services/tenant_invitation_service.dart';
import 'package:smartsfa/src/features/tenant/presentation/controllers/tenant_invitation_action_controller.dart';

void main() {
  test('rejects invalid invited email before hitting service layer', () async {
    final service = TenantInvitationService(FakeFirebaseFirestore());
    final controller = TenantInvitationActionController(service);

    expect(
      () => controller.createInvitation(
        tenantId: 'tenant_a',
        role: 'vendedor',
        createdByUid: 'owner_1',
        invitedEmail: 'invalid-email',
        defaultTenant: false,
        expirationDays: 7,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
