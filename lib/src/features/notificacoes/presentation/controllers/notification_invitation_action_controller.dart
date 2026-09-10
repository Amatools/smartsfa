import 'package:firebase_auth/firebase_auth.dart';

import '../../../auth/services/tenant_invitation_service.dart';

class NotificationInvitationActionController {
  const NotificationInvitationActionController(this._invitationService);

  final TenantInvitationService _invitationService;

  Future<void> acceptInvitation({required User user, required String token}) {
    return _invitationService.acceptInvitation(user: user, token: token);
  }

  Future<void> declineInvitation({
    required String token,
    required String declinedByUid,
  }) {
    return _invitationService.declineInvitation(
      token: token,
      declinedByUid: declinedByUid,
    );
  }
}
