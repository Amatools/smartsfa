import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/tenant_membership.dart';

class TenantMembershipService {
  TenantMembershipService(this._firestore);

  final FirebaseFirestore _firestore;
  static const Set<String> _allowedRoles = {
    'owner',
    'gerente',
    'representante',
    'vendedor',
  };

  Stream<List<TenantMembership>> watchMembershipsForTenant(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const []);
    }

    return _firestore
        .collection('tenant_memberships')
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map((snapshot) {
      final memberships = snapshot.docs
          .map((doc) {
            final data = doc.data();
            data.putIfAbsent('membershipId', () => doc.id);
            return TenantMembership.fromMap(data);
          })
          .toList();

      memberships.sort((a, b) {
        if (a.isActive != b.isActive) {
          return a.isActive ? -1 : 1;
        }

        if (a.defaultTenant != b.defaultTenant) {
          return a.defaultTenant ? -1 : 1;
        }

        return a.uid.compareTo(b.uid);
      });

      return memberships;
    });
  }

  Stream<List<Map<String, dynamic>>> watchAuditForTenant(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const []);
    }

    return _firestore
        .collection('tenant_membership_audit')
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map((snapshot) {
      final entries = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();

      entries.sort((a, b) {
        final aTime = DateTime.tryParse((a['createdAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = DateTime.tryParse((b['createdAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      return entries;
    });
  }

  Future<TenantMembership?> loadById(String membershipId) async {
    final doc = await _firestore.collection('tenant_memberships').doc(membershipId).get();
    if (!doc.exists) {
      return null;
    }

    return TenantMembership.fromMap(doc.data() ?? <String, Object?>{});
  }

  Future<TenantMembership> revokeMembership({
    required String membershipId,
    required String revokedByUid,
    String? reason,
  }) async {
    final current = await loadById(membershipId);
    if (current == null) {
      throw StateError('Membership nao encontrado.');
    }

    final updated = current.revoke(
      revokedByUid: revokedByUid,
      reason: reason,
    );

    await _firestore.collection('tenant_memberships').doc(membershipId).set(
          updated.toMap(),
          SetOptions(merge: true),
        );

    await _writeAudit(
      tenantId: updated.tenantId,
      membershipId: updated.membershipId,
      action: 'membership_revoked',
      actorUid: revokedByUid,
      details: {
        'reason': reason,
      },
    );

    return updated;
  }

  Future<TenantMembership> revokeMembershipByActor({
    required String membershipId,
    required String actorUid,
  }) async {
    final target = await loadById(membershipId);
    if (target == null) {
      throw StateError('Membership nao encontrado.');
    }

    if (!await _canActorManageTarget(
      tenantId: target.tenantId,
      actorUid: actorUid,
      target: target,
    )) {
      throw StateError('Actor sem permissao para revogar este membership.');
    }

    return revokeMembership(
      membershipId: membershipId,
      revokedByUid: actorUid,
      reason: 'Revogado por politica de governanca do tenant.',
    );
  }

  Future<TenantMembership> reactivateMembership({
    required String membershipId,
    String? reactivatedByUid,
  }) async {
    final current = await loadById(membershipId);
    if (current == null) {
      throw StateError('Membership nao encontrado.');
    }

    final updated = current.reactivate();

    await _firestore.collection('tenant_memberships').doc(membershipId).set(
          updated.toMap(),
          SetOptions(merge: true),
        );

    await _writeAudit(
      tenantId: updated.tenantId,
      membershipId: updated.membershipId,
      action: 'membership_reactivated',
      actorUid: reactivatedByUid ?? 'system',
    );

    return updated;
  }

  Future<TenantMembership> reactivateMembershipByActor({
    required String membershipId,
    required String actorUid,
  }) async {
    final target = await loadById(membershipId);
    if (target == null) {
      throw StateError('Membership nao encontrado.');
    }

    if (!await _canActorManageTarget(
      tenantId: target.tenantId,
      actorUid: actorUid,
      target: target,
    )) {
      throw StateError('Actor sem permissao para reativar este membership.');
    }

    return reactivateMembership(
      membershipId: membershipId,
      reactivatedByUid: actorUid,
    );
  }

  Future<TenantMembership> leaveTenant({
    required String membershipId,
    required String actorUid,
  }) async {
    final target = await loadById(membershipId);
    if (target == null) {
      throw StateError('Membership nao encontrado.');
    }

    if (target.uid != actorUid) {
      throw StateError('Somente o proprio usuario pode sair deste tenant.');
    }

    final actorRole = target.role.trim().toLowerCase();
    if (actorRole == 'owner') {
      throw StateError('Owner nao pode sair via autoatendimento.');
    }

    return revokeMembership(
      membershipId: membershipId,
      revokedByUid: actorUid,
      reason: 'Saida voluntaria do usuario no app.',
    );
  }

  Future<TenantMembership> changeRole({
    required String membershipId,
    required String newRole,
    required String changedByUid,
  }) async {
    final normalizedRole = newRole.trim().toLowerCase();
    if (!_allowedRoles.contains(normalizedRole)) {
      throw StateError('Perfil invalido para membership.');
    }

    final current = await loadById(membershipId);
    if (current == null) {
      throw StateError('Membership nao encontrado.');
    }

    if (current.role.trim().toLowerCase() == normalizedRole) {
      return current;
    }

    final updated = current.copyWith(
      role: normalizedRole,
      ownerId: _ownerIdForRole(current: current, role: normalizedRole),
      gerenteId: _gerenteIdForRole(current: current, role: normalizedRole),
      representanteId: _representanteIdForRole(
        current: current,
        role: normalizedRole,
      ),
      vendedorId: _vendedorIdForRole(current: current, role: normalizedRole),
    );

    await _firestore.collection('tenant_memberships').doc(membershipId).set(
          updated.toMap(),
          SetOptions(merge: true),
        );

    await _writeAudit(
      tenantId: updated.tenantId,
      membershipId: updated.membershipId,
      action: 'membership_role_changed',
      actorUid: changedByUid,
      details: {
        'oldRole': current.role,
        'newRole': updated.role,
      },
    );

    return updated;
  }

  Future<TenantMembership> changeRoleByActor({
    required String membershipId,
    required String newRole,
    required String actorUid,
  }) async {
    final target = await loadById(membershipId);
    if (target == null) {
      throw StateError('Membership nao encontrado.');
    }

    if (!await _canActorManageTarget(
      tenantId: target.tenantId,
      actorUid: actorUid,
      target: target,
    )) {
      throw StateError('Actor sem permissao para alterar este membership.');
    }

    return changeRole(
      membershipId: membershipId,
      newRole: newRole,
      changedByUid: actorUid,
    );
  }

  Future<Map<String, bool>> loadGovernancePolicy(String tenantId) async {
    final tenantDoc = await _firestore.collection('tenants').doc(tenantId).get();
    if (!tenantDoc.exists) {
      return _defaultGovernancePolicy();
    }

    final data = tenantDoc.data() ?? <String, dynamic>{};
    final policy = data['policy'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return {
      'allowManagerDisableRepresentative':
          policy['allowManagerDisableRepresentative'] as bool? ?? false,
      'allowRepresentativeDisableSeller':
          policy['allowRepresentativeDisableSeller'] as bool? ?? true,
      // Personal workspace is controlled by user preference, not tenant policy.
      'allowPersonalWorkspace': true,
    };
  }

  Future<void> updateGovernancePolicy({
    required String tenantId,
    required bool allowManagerDisableRepresentative,
    required bool allowRepresentativeDisableSeller,
    required bool allowPersonalWorkspace,
    required String updatedByUid,
  }) async {
    await _firestore.collection('tenants').doc(tenantId).set(
      {
        'policy': {
          'allowManagerDisableRepresentative':
              allowManagerDisableRepresentative,
          'allowRepresentativeDisableSeller':
              allowRepresentativeDisableSeller,
          // Keep as true for backward compatibility with existing documents.
          'allowPersonalWorkspace': true,
        },
        'updatedAt': DateTime.now().toIso8601String(),
      },
      SetOptions(merge: true),
    );

    await _firestore.collection('tenant_membership_audit').add({
      'tenantId': tenantId,
      'membershipId': '',
      'action': 'tenant_policy_updated',
      'actorUid': updatedByUid,
      'details': {
        'allowManagerDisableRepresentative': allowManagerDisableRepresentative,
        'allowRepresentativeDisableSeller': allowRepresentativeDisableSeller,
        'allowPersonalWorkspace': true,
      },
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<TenantMembership> syncMembershipState({
    required String membershipId,
    required bool activeInErp,
    String? revokedByUid,
    String? reason,
  }) async {
    if (activeInErp) {
      return reactivateMembership(
        membershipId: membershipId,
        reactivatedByUid: revokedByUid ?? 'erp_sync',
      );
    }

    return revokeMembership(
      membershipId: membershipId,
      revokedByUid: revokedByUid ?? 'erp_sync',
      reason: reason ?? 'Desligamento detectado no ERP.',
    );
  }

  String _ownerIdForRole({
    required TenantMembership current,
    required String role,
  }) {
    if (role == 'owner') {
      return current.uid;
    }

    return current.ownerId;
  }

  String _gerenteIdForRole({
    required TenantMembership current,
    required String role,
  }) {
    if (role == 'owner') {
      return '';
    }

    if (role == 'gerente') {
      return current.uid;
    }

    return current.gerenteId;
  }

  String _representanteIdForRole({
    required TenantMembership current,
    required String role,
  }) {
    if (role == 'owner' || role == 'gerente') {
      return '';
    }

    if (role == 'representante') {
      return current.uid;
    }

    return current.representanteId;
  }

  String _vendedorIdForRole({
    required TenantMembership current,
    required String role,
  }) {
    if (role != 'vendedor') {
      return '';
    }

    return current.uid;
  }

  Future<void> _writeAudit({
    required String tenantId,
    required String membershipId,
    required String action,
    required String actorUid,
    Map<String, Object?>? details,
  }) {
    return _firestore.collection('tenant_membership_audit').add({
      'tenantId': tenantId,
      'membershipId': membershipId,
      'action': action,
      'actorUid': actorUid,
      'details': details,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> _canActorManageTarget({
    required String tenantId,
    required String actorUid,
    required TenantMembership target,
  }) async {
    if (target.uid == actorUid) {
      return false;
    }

    final actorUserDoc =
        await _firestore.collection('usuarios').doc(actorUid).get();
    final actorUserData = actorUserDoc.data() ?? <String, dynamic>{};
    final platformRole =
        (actorUserData['platformRole'] ?? '').toString().trim().toLowerCase();
    if (platformRole == 'platform_admin') {
      return true;
    }

    final actorSnapshot = await _firestore
        .collection('tenant_memberships')
        .where('tenantId', isEqualTo: tenantId)
        .where('uid', isEqualTo: actorUid)
        .where('ativo', isEqualTo: true)
        .where('state', isEqualTo: 'active')
        .limit(1)
        .get();

    if (actorSnapshot.docs.isEmpty) {
      return false;
    }

    final actorRole =
        (actorSnapshot.docs.first.data()['role'] ?? '').toString().toLowerCase();
    final targetRole = target.role.trim().toLowerCase();

    if (actorRole == 'owner') {
      return targetRole == 'gerente' ||
          targetRole == 'representante' ||
          targetRole == 'vendedor';
    }

    final policy = await loadGovernancePolicy(tenantId);
    if (actorRole == 'gerente') {
      return policy['allowManagerDisableRepresentative'] == true &&
          targetRole == 'representante';
    }

    if (actorRole == 'representante') {
      return policy['allowRepresentativeDisableSeller'] == true &&
          targetRole == 'vendedor';
    }

    return false;
  }

  Map<String, bool> _defaultGovernancePolicy() {
    return {
      'allowManagerDisableRepresentative': false,
      'allowRepresentativeDisableSeller': true,
      'allowPersonalWorkspace': true,
    };
  }
}