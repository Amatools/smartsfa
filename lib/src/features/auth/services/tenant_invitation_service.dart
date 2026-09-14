import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/models/tenant_invitation.dart';
import '../../../core/models/tenant_membership.dart';
import 'solo_workspace_service.dart';

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

    await _requireInvitationPermission(
      tenantId: normalizedTenantId,
      uid: normalizedCreatedByUid,
      invitedRole: normalizedRole,
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

    await _requireInvitationPermission(
      tenantId: invitation.tenantId,
      uid: normalizedRevokedByUid,
      invitedRole: invitation.role,
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

    final userDoc = await _firestore.collection('usuarios').doc(user.uid).get();
    final accountContractLock = AccountContractLock.fromValue(
      (userDoc.data()?['accountContractLock'] ?? '').toString().trim(),
    );

    await _assertInvitationAcceptanceAllowed(
      user: user,
      invitation: invitation,
      accountContractLock: accountContractLock,
    );

    final now = DateTime.now();
    final membershipId = '${invitation.tenantId}_${user.uid}';
    final scope = await _membershipScopeForAcceptedInvite(
      tenantId: invitation.tenantId,
      invitedRole: invitation.role,
      invitedUid: user.uid,
      createdByUid: invitation.createdByUid ?? '',
    );
    final membership = TenantMembership(
      membershipId: membershipId,
      tenantId: invitation.tenantId,
      uid: user.uid,
      role: invitation.role,
      ativo: true,
      defaultTenant: invitation.defaultTenant,
      ownerId: scope.ownerId,
      gerenteId: scope.gerenteId,
      representanteId: scope.representanteId,
      vendedorId: scope.vendedorId,
      state: TenantMembershipState.active,
      lastSyncedAt: now,
    );

    await _firestore.collection('tenant_memberships').doc(membershipId).set(
          {
            ...membership.toMap(),
            'invitationToken': invitation.token,
          },
          SetOptions(merge: true),
        );

    await _firestore.collection('usuarios').doc(user.uid).set(
      {
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': user.displayName ?? user.email ?? user.uid,
        'platformRole': 'none',
        'ativoGlobal': true,
        'accountContractLock': accountContractLock.value,
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

    await _syncTenantSelectionAfterInvitation(
      uid: user.uid,
      membershipId: membershipId,
      tenantId: invitation.tenantId,
      makeDefault: invitation.defaultTenant,
    );

    return membership;
  }

  Future<void> _assertInvitationAcceptanceAllowed({
    required User user,
    required TenantInvitation invitation,
    required AccountContractLock accountContractLock,
  }) async {
    if (accountContractLock != AccountContractLock.enterpriseOnly) {
      return;
    }

    final tenantDoc = await _firestore.collection('tenants').doc(invitation.tenantId).get();
    final workspaceType =
        (tenantDoc.data()?['workspaceType'] ?? 'brand_owner_workspace')
            .toString()
            .trim();
    if (workspaceType != WorkspaceType.brandOwnerWorkspace.value) {
      throw StateError(
        'Conta enterprise e exclusiva e nao pode aceitar convites fora de tenants enterprise.',
      );
    }
  }

  Future<void> _syncTenantSelectionAfterInvitation({
    required String uid,
    required String membershipId,
    required String tenantId,
    required bool makeDefault,
  }) async {
    final batch = _firestore.batch();

    if (makeDefault) {
      final memberships = await _firestore
          .collection('tenant_memberships')
          .where('uid', isEqualTo: uid)
          .get();
      for (final doc in memberships.docs) {
        batch.set(
          doc.reference,
          {'defaultTenant': doc.id == membershipId},
          SetOptions(merge: true),
        );
      }
    }

    batch.set(
      _firestore.collection('usuarios').doc(uid),
      {
        'lastSelectedTenantId': tenantId,
        if (makeDefault) 'defaultTenantId': tenantId,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Future<_InvitationMembershipScope> _membershipScopeForAcceptedInvite({
    required String tenantId,
    required String invitedRole,
    required String invitedUid,
    required String createdByUid,
  }) async {
    final normalizedRole = invitedRole.trim().toLowerCase();
    final tenantDoc = await _firestore.collection('tenants').doc(tenantId).get();
    final workspaceType =
        (tenantDoc.data()?['workspaceType'] ?? 'brand_owner_workspace').toString();

    final inviterMembership = createdByUid.trim().isEmpty
        ? null
        : await _firestore
            .collection('tenant_memberships')
            .doc('${tenantId}_${createdByUid.trim()}')
            .get();
    final inviterData = inviterMembership?.data() ?? <String, dynamic>{};

    if (workspaceType == 'seller_solo_workspace') {
      throw StateError('Workspace seller solo nao aceita convites.');
    }

    if (workspaceType == 'rep_workspace') {
      if (normalizedRole == 'representante') {
        return _InvitationMembershipScope(
          ownerId: _pickOwnerId(inviterData, createdByUid),
          gerenteId: '',
          representanteId: invitedUid,
          vendedorId: '',
        );
      }

      if (normalizedRole == 'vendedor') {
        return _InvitationMembershipScope(
          ownerId: _pickOwnerId(inviterData, createdByUid),
          gerenteId: '',
          representanteId: _pickRepresentativeId(inviterData, createdByUid),
          vendedorId: invitedUid,
        );
      }

      throw StateError('Workspace de representacao exige hierarquia owner > representante > vendedor.');
    }

    if (normalizedRole == 'gerente') {
      return _InvitationMembershipScope(
        ownerId: _pickOwnerId(inviterData, createdByUid),
        gerenteId: invitedUid,
        representanteId: '',
        vendedorId: '',
      );
    }

    if (normalizedRole == 'representante') {
      return _InvitationMembershipScope(
        ownerId: _pickOwnerId(inviterData, createdByUid),
        gerenteId: _pickManagerId(inviterData),
        representanteId: invitedUid,
        vendedorId: '',
      );
    }

    if (normalizedRole == 'vendedor') {
      return _InvitationMembershipScope(
        ownerId: _pickOwnerId(inviterData, createdByUid),
        gerenteId: _pickManagerId(inviterData),
        representanteId: _pickRepresentativeId(inviterData, createdByUid),
        vendedorId: invitedUid,
      );
    }

    throw StateError('Perfil de convite invalido para este tenant.');
  }

  String _pickOwnerId(Map<String, dynamic> inviterData, String createdByUid) {
    final ownerId = (inviterData['ownerId'] ?? '').toString().trim();
    if (ownerId.isNotEmpty) {
      return ownerId;
    }
    return createdByUid.trim();
  }

  String _pickManagerId(Map<String, dynamic> inviterData) {
    return (inviterData['gerenteId'] ?? '').toString().trim();
  }

  String _pickRepresentativeId(
    Map<String, dynamic> inviterData,
    String createdByUid,
  ) {
    final representativeId =
        (inviterData['representanteId'] ?? '').toString().trim();
    if (representativeId.isNotEmpty) {
      return representativeId;
    }

    final inviterRole = (inviterData['role'] ?? '').toString().trim().toLowerCase();
    if (inviterRole == 'representante' || inviterRole == 'owner') {
      return createdByUid.trim();
    }

    return '';
  }

  Future<void> _requireInvitationPermission({
    required String tenantId,
    required String uid,
    required String invitedRole,
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
      throw StateError('Sem permissao para gerenciar convites neste tenant.');
    }

    final actorData = memberships.docs.first.data();
    final actorRole = (actorData['role'] ?? '').toString().trim().toLowerCase();
    final targetRole = invitedRole.trim().toLowerCase();

    final tenantDoc = await _firestore.collection('tenants').doc(tenantId).get();
    final tenantData = tenantDoc.data() ?? <String, dynamic>{};
    final workspaceType =
        (tenantData['workspaceType'] ?? 'brand_owner_workspace')
            .toString()
            .trim()
            .toLowerCase();

    final allowed = _canInvite(
      workspaceType: workspaceType,
      actorRole: actorRole,
      targetRole: targetRole,
    );

    if (!allowed) {
      throw StateError('Sem permissao para este convite neste tipo de workspace.');
    }
  }

  bool _canInvite({
    required String workspaceType,
    required String actorRole,
    required String targetRole,
  }) {
    if (workspaceType == 'seller_solo_workspace') {
      return false;
    }

    if (workspaceType == 'rep_workspace') {
      if (actorRole == 'owner') {
        return targetRole == 'representante' || targetRole == 'vendedor';
      }

      if (actorRole == 'representante') {
        return targetRole == 'vendedor';
      }

      return false;
    }

    if (workspaceType == 'brand_owner_workspace') {
      if (actorRole == 'owner') {
        return targetRole == 'gerente';
      }

      if (actorRole == 'gerente') {
        return targetRole == 'representante';
      }

      if (actorRole == 'representante') {
        return targetRole == 'vendedor';
      }

      return false;
    }

    return false;
  }
}

class _InvitationMembershipScope {
  const _InvitationMembershipScope({
    required this.ownerId,
    required this.gerenteId,
    required this.representanteId,
    required this.vendedorId,
  });

  final String ownerId;
  final String gerenteId;
  final String representanteId;
  final String vendedorId;
}