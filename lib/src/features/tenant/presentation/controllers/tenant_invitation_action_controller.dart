import '../../../../core/models/tenant_invitation.dart';
import '../../../auth/services/tenant_invitation_service.dart';

class TenantInvitationActionController {
  const TenantInvitationActionController(this._invitationService);

  final TenantInvitationService _invitationService;

  Future<TenantInvitation> createInvitation({
    required String tenantId,
    required String role,
    required String createdByUid,
    required String invitedEmail,
    required bool defaultTenant,
    required int expirationDays,
  }) async {
    final normalizedEmail = invitedEmail.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw StateError('Informe um e-mail valido para o convite.');
    }

    final expiresAt = DateTime.now().add(Duration(days: expirationDays));
    return _invitationService.createInvitation(
      tenantId: tenantId,
      role: role,
      createdByUid: createdByUid,
      invitedEmail: normalizedEmail,
      defaultTenant: defaultTenant,
      expiresAt: expiresAt,
    );
  }

  Future<void> revokeInvitation({
    required String token,
    required String revokedByUid,
  }) {
    return _invitationService.revokeInvitation(
      token: token,
      revokedByUid: revokedByUid,
    );
  }
}