import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/models/tenant_invitation.dart';
import '../../../core/models/tenant_membership.dart';

class TenantInvitationService {
  TenantInvitationService(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<TenantInvitation>> watchInvitationsForTenant(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const []);
    }

    return _firestore
        .collection('tenant_invitations')
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TenantInvitation.fromMap(doc.data()))
              .toList()
            ..sort(
              (a, b) =>
                  (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                      .compareTo(
                a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              ),
            ),
        );
  }

  Stream<List<TenantInvitation>> watchPendingInvitationsForEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      return Stream.value(const []);
    }

    return _firestore
        .collection('tenant_invitations')
        .where('status', isEqualTo: TenantInvitationStatus.pending.value)
        .where('invitedEmail', isEqualTo: normalizedEmail)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TenantInvitation.fromMap(doc.data()))
              .toList(),
        );
  }

  Future<TenantInvitation> createInvitation({
    required String tenantId,
    required String role,
    required String createdByUid,
    String? invitedEmail,
    bool defaultTenant = false,
    DateTime? expiresAt,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedRole = role.trim();
    final normalizedCreatedByUid = createdByUid.trim();
    final normalizedEmail = invitedEmail?.trim().toLowerCase();

    if (normalizedTenantId.isEmpty) {
      throw StateError('Tenant invalido para convite.');
    }

    if (normalizedRole.isEmpty) {
      throw StateError('Perfil invalido para convite.');
    }

    if (normalizedCreatedByUid.isEmpty) {
      throw StateError('Usuario emissor do convite nao identificado.');
    }

    await _requireOwnerMembership(
      tenantId: normalizedTenantId,
      uid: normalizedCreatedByUid,
    );

    final now = DateTime.now();
    final invitationRef = _firestore.collection('tenant_invitations').doc();
    final invitation = TenantInvitation(
      token: invitationRef.id,
      tenantId: normalizedTenantId,
      role: normalizedRole,
      status: TenantInvitationStatus.pending,
      invitedEmail: normalizedEmail,
      defaultTenant: defaultTenant,
      expiresAt: expiresAt,
      createdByUid: normalizedCreatedByUid,
      createdAt: now,
      updatedAt: now,
    );

    await invitationRef.set(invitation.toMap(), SetOptions(merge: true));
    return invitation;
  }

  Future<void> revokeInvitation({
    required String token,
    required String revokedByUid,
  }) async {
    final normalizedToken = token.trim();
    final normalizedRevokedByUid = revokedByUid.trim();

    if (normalizedToken.isEmpty) {
      throw StateError('Token de convite invalido.');
    }

    if (normalizedRevokedByUid.isEmpty) {
      throw StateError('Usuario que revogou nao identificado.');
    }

    final invitation = await loadByToken(normalizedToken);
    if (invitation == null) {
      throw StateError('Convite nao encontrado.');
    }

    if (invitation.status != TenantInvitationStatus.pending) {
      throw StateError('Apenas convites pendentes podem ser revogados.');
    }

    await _requireOwnerMembership(
      tenantId: invitation.tenantId,
      uid: normalizedRevokedByUid,
    );

    final now = DateTime.now();
    await _firestore.collection('tenant_invitations').doc(invitation.token).set(
      {
        'status': TenantInvitationStatus.revoked.value,
        'revokedByUid': normalizedRevokedByUid,
        'revokedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> declineInvitation({
    required String token,
    required String declinedByUid,
  }) async {
    final normalizedToken = token.trim();
    final normalizedDeclinedByUid = declinedByUid.trim();

    if (normalizedToken.isEmpty) {
      throw StateError('Token de convite invalido.');
    }

    if (normalizedDeclinedByUid.isEmpty) {
      throw StateError('Usuario que recusou nao identificado.');
    }

    final invitation = await loadByToken(normalizedToken);
    if (invitation == null) {
      throw StateError('Convite nao encontrado.');
    }

    if (invitation.status != TenantInvitationStatus.pending) {
      throw StateError('Apenas convites pendentes podem ser recusados.');
    }

    final now = DateTime.now();
    await _firestore.collection('tenant_invitations').doc(invitation.token).set(
      {
        'status': TenantInvitationStatus.declined.value,
        'declinedByUid': normalizedDeclinedByUid,
        'declinedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      },
      SetOptions(merge: true),
    );
  }

  Future<TenantInvitation?> loadByToken(String token) async {
    if (token.trim().isEmpty) {
      return null;
    }

    final doc = await _firestore.collection('tenant_invitations').doc(token).get();
    if (!doc.exists) {
      return null;
    }

    return TenantInvitation.fromMap(doc.data() ?? <String, Object?>{});
  }

  Future<TenantMembership> acceptInvitation({
    required User user,
    required String token,
  }) async {
    final invitation = await loadByToken(token.trim());
    if (invitation == null) {
      throw StateError('Convite nao encontrado.');
    }

    if (invitation.status != TenantInvitationStatus.pending) {
      throw StateError('Convite nao esta pendente.');
    }

    if (invitation.isExpired) {
      throw StateError('Convite expirado.');
    }

    final invitedEmail = invitation.invitedEmail?.trim().toLowerCase();
    final userEmail = user.email?.trim().toLowerCase();
    if (invitedEmail != null && invitedEmail.isNotEmpty) {
      if (userEmail == null || userEmail.isEmpty || invitedEmail != userEmail) {
        throw StateError('Este convite foi emitido para outro e-mail.');
      }
    }

    final now = DateTime.now();
    final membershipId = '${invitation.tenantId}_${user.uid}';
    final membership = TenantMembership(
      membershipId: membershipId,
      tenantId: invitation.tenantId,
      uid: user.uid,
      role: invitation.role,
      ativo: true,
      defaultTenant: invitation.defaultTenant,
      ownerId: invitation.role == 'owner' ? user.uid : '',
      gerenteId: invitation.role == 'gerente' ? user.uid : '',
      representanteId: invitation.role == 'representante' ? user.uid : '',
      vendedorId: invitation.role == 'vendedor' ? user.uid : '',
      state: TenantMembershipState.active,
      lastSyncedAt: now,
    );

    await _firestore.collection('tenant_memberships').doc(membershipId).set(
          membership.toMap(),
          SetOptions(merge: true),
        );

    await _firestore.collection('usuarios').doc(user.uid).set(
      {
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'ativoGlobal': true,
        'lastSelectedTenantId': invitation.tenantId,
        'defaultTenantId': invitation.defaultTenant ? invitation.tenantId : null,
        'updatedAt': now.toIso8601String(),
      },
      SetOptions(merge: true),
    );

    await _firestore.collection('tenant_invitations').doc(invitation.token).set(
      {
        'status': TenantInvitationStatus.accepted.value,
        'acceptedByUid': user.uid,
        'acceptedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      },
      SetOptions(merge: true),
    );

    return membership;
  }

  Future<void> _requireOwnerMembership({
    required String tenantId,
    required String uid,
  }) async {
    final memberships = await _firestore
        .collection('tenant_memberships')
        .where('tenantId', isEqualTo: tenantId)
        .where('uid', isEqualTo: uid)
        .where('ativo', isEqualTo: true)
        .where('state', isEqualTo: 'active')
        .limit(1)
        .get();

    if (memberships.docs.isEmpty) {
      throw StateError('Apenas owner pode gerenciar convites deste tenant.');
    }

    final data = memberships.docs.first.data();
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    if (role != 'owner') {
      throw StateError('Apenas owner pode gerenciar convites deste tenant.');
    }
  }
}