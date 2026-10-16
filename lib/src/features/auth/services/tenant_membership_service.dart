import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/tenant_entry_decision.dart';
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
          final memberships = snapshot.docs.map((doc) {
            final data = doc.data();
            data.putIfAbsent('membershipId', () => doc.id);
            return TenantMembership.fromMap(data);
          }).toList();

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

  Stream<List<TenantEntryOption>> watchTenantChoicesForUser(String uid) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return Stream.value(const []);
    }

    return _firestore
        .collection('tenant_memberships')
        .where('uid', isEqualTo: normalizedUid)
        .where('ativo', isEqualTo: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final options = <TenantEntryOption>[];

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final tenantId = (data['tenantId'] ?? '').toString().trim();
            if (tenantId.isEmpty) {
              continue;
            }

            final tenantDoc = await _firestore
                .collection('tenants')
                .doc(tenantId)
                .get();
            if (!tenantDoc.exists) {
              continue;
            }

            final tenantData = tenantDoc.data() ?? <String, dynamic>{};
            if (tenantData['ativo'] != true) {
              continue;
            }

            final supersededBy = (tenantData['supersededByTenantId'] ?? '')
                .toString()
                .trim();
            if (supersededBy.isNotEmpty) {
              continue;
            }

            options.add(
              TenantEntryOption(
                membershipId: doc.id,
                tenantId: tenantId,
                tenantName: (tenantData['nomeFantasia'] ?? tenantId).toString(),
                role: (data['role'] ?? 'member').toString(),
                workspaceType:
                    (tenantData['workspaceType'] ?? 'brand_owner_workspace')
                        .toString(),
                defaultTenant: data['defaultTenant'] == true,
              ),
            );
          }

          options.sort((a, b) {
            if (a.defaultTenant != b.defaultTenant) {
              return a.defaultTenant ? -1 : 1;
            }

            return a.tenantName.toLowerCase().compareTo(
              b.tenantName.toLowerCase(),
            );
          });

          return options;
        });
  }

  Future<void> setDefaultTenantForUser({
    required String uid,
    required String membershipId,
    required String tenantId,
  }) async {
    final normalizedUid = uid.trim();
    final normalizedMembershipId = membershipId.trim();
    final normalizedTenantId = tenantId.trim();
    if (normalizedUid.isEmpty ||
        normalizedMembershipId.isEmpty ||
        normalizedTenantId.isEmpty) {
      throw StateError('Contexto invalido para definir tenant padrao.');
    }

    final memberships = await _firestore
        .collection('tenant_memberships')
        .where('uid', isEqualTo: normalizedUid)
        .get();

    final batch = _firestore.batch();
    for (final doc in memberships.docs) {
      batch.set(doc.reference, {
        'defaultTenant': doc.id == normalizedMembershipId,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    }

    batch.set(_firestore.collection('usuarios').doc(normalizedUid), {
      'defaultTenantId': normalizedTenantId,
      'lastSelectedTenantId': normalizedTenantId,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    await batch.commit();
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
            final aTime =
                DateTime.tryParse((a['createdAt'] ?? '').toString()) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bTime =
                DateTime.tryParse((b['createdAt'] ?? '').toString()) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });

          return entries;
        });
  }

  Future<TenantMembership?> loadById(String membershipId) async {
    final doc = await _firestore
        .collection('tenant_memberships')
        .doc(membershipId)
        .get();
    if (!doc.exists) {
      return null;
    }

    return TenantMembership.fromMap(doc.data() ?? <String, Object?>{});
  }

  Future<TenantMembership?> loadActiveByTenantAndUid({
    required String tenantId,
    required String uid,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedUid = uid.trim();
    if (normalizedTenantId.isEmpty || normalizedUid.isEmpty) {
      return null;
    }

    final byPatternId = await loadById('${normalizedTenantId}_$normalizedUid');
    if (byPatternId != null &&
        byPatternId.tenantId == normalizedTenantId &&
        byPatternId.uid == normalizedUid &&
        byPatternId.isActive) {
      return byPatternId;
    }

    final snapshot = await _firestore
        .collection('tenant_memberships')
        .where('tenantId', isEqualTo: normalizedTenantId)
        .where('uid', isEqualTo: normalizedUid)
        .where('ativo', isEqualTo: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    final data = snapshot.docs.first.data();
    data.putIfAbsent('membershipId', () => snapshot.docs.first.id);
    final membership = TenantMembership.fromMap(data);
    if (!membership.isActive) {
      return null;
    }
    return membership;
  }

  Future<TenantMembership> revokeMembership({
    required String membershipId,
    required String revokedByUid,
    String? reason,
  }) async {
    final actorIdentity = await _resolveAuditActorIdentity(revokedByUid);
    final updated = await _firestore.runTransaction<TenantMembership>((tx) async {
      final membershipRef = _firestore
          .collection('tenant_memberships')
          .doc(membershipId);
      final snapshot = await tx.get(membershipRef);
      if (!snapshot.exists) {
        throw StateError('Membership nao encontrado.');
      }

      final currentData = snapshot.data() ?? <String, dynamic>{};
      currentData.putIfAbsent('membershipId', () => snapshot.id);
      final current = TenantMembership.fromMap(currentData);
      final updated = current.revoke(revokedByUid: revokedByUid, reason: reason);

      await _applyHierarchyAggregateDelta(
        tx: tx,
        previous: current,
        next: updated,
      );

      _setAuditInTransaction(
        tx: tx,
        tenantId: updated.tenantId,
        membershipId: updated.membershipId,
        action: 'membership_revoked',
        actorUid: actorIdentity.uid,
        actorLabel: actorIdentity.label,
        actorEmail: actorIdentity.email,
        details: {'reason': reason},
      );

      tx.set(membershipRef, updated.toMap(), SetOptions(merge: true));
      return updated;
    });

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

    final normalizedRole = target.role.trim().toLowerCase();
    if (normalizedRole == 'gerente' || normalizedRole == 'representante') {
      await _assertNoActiveSubordinates(target);
    }

    return revokeMembership(
      membershipId: membershipId,
      revokedByUid: actorUid,
      reason: 'Revogado por política de governança do tenant.',
    );
  }

  Future<TenantMembership> deactivateMembership({
    required String membershipId,
    required String deactivatedByUid,
    String? reason,
  }) async {
    final actorIdentity = await _resolveAuditActorIdentity(deactivatedByUid);
    final updated = await _firestore.runTransaction<TenantMembership>((tx) async {
      final membershipRef = _firestore
          .collection('tenant_memberships')
          .doc(membershipId);
      final snapshot = await tx.get(membershipRef);
      if (!snapshot.exists) {
        throw StateError('Membership nao encontrado.');
      }

      final currentData = snapshot.data() ?? <String, dynamic>{};
      currentData.putIfAbsent('membershipId', () => snapshot.id);
      final current = TenantMembership.fromMap(currentData);
      final updated = current.deactivate(
        deactivatedByUid: deactivatedByUid,
        reason: reason,
      );

      await _applyHierarchyAggregateDelta(
        tx: tx,
        previous: current,
        next: updated,
      );

      _setAuditInTransaction(
        tx: tx,
        tenantId: updated.tenantId,
        membershipId: updated.membershipId,
        action: 'membership_deactivated',
        actorUid: actorIdentity.uid,
        actorLabel: actorIdentity.label,
        actorEmail: actorIdentity.email,
        details: {'reason': reason},
      );

      tx.set(membershipRef, updated.toMap(), SetOptions(merge: true));
      return updated;
    });

    return updated;
  }

  Future<TenantMembership> deactivateMembershipByActor({
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
      throw StateError('Actor sem permissao para inativar este membership.');
    }

    final normalizedRole = target.role.trim().toLowerCase();
    if (normalizedRole == 'gerente' || normalizedRole == 'representante') {
      await _assertNoActiveSubordinates(target);
    }

    return deactivateMembership(
      membershipId: membershipId,
      deactivatedByUid: actorUid,
      reason: 'Inativado temporariamente por governança do tenant.',
    );
  }

  Future<TenantMembership> reactivateMembership({
    required String membershipId,
    String? reactivatedByUid,
    String? reason,
  }) async {
    final actorUidForAudit = reactivatedByUid ?? 'system';
    final actorIdentity = await _resolveAuditActorIdentity(actorUidForAudit);
    final updated = await _firestore.runTransaction<TenantMembership>((tx) async {
      final membershipRef = _firestore
          .collection('tenant_memberships')
          .doc(membershipId);
      final snapshot = await tx.get(membershipRef);
      if (!snapshot.exists) {
        throw StateError('Membership nao encontrado.');
      }

      final currentData = snapshot.data() ?? <String, dynamic>{};
      currentData.putIfAbsent('membershipId', () => snapshot.id);
      final current = TenantMembership.fromMap(currentData);
      final updated = current.reactivate();

      await _applyHierarchyAggregateDelta(
        tx: tx,
        previous: current,
        next: updated,
      );

      _setAuditInTransaction(
        tx: tx,
        tenantId: updated.tenantId,
        membershipId: updated.membershipId,
        action: 'membership_reactivated',
        actorUid: actorIdentity.uid,
        actorLabel: actorIdentity.label,
        actorEmail: actorIdentity.email,
        details: {'reason': reason},
      );

      tx.set(membershipRef, updated.toMap(), SetOptions(merge: true));
      return updated;
    });

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
      reason: 'Reativado por governança do tenant.',
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

    final updated = await _firestore.runTransaction<TenantMembership>((tx) async {
      final membershipRef = _firestore
          .collection('tenant_memberships')
          .doc(membershipId);
      final snapshot = await tx.get(membershipRef);
      if (!snapshot.exists) {
        throw StateError('Membership nao encontrado.');
      }

      final currentData = snapshot.data() ?? <String, dynamic>{};
      currentData.putIfAbsent('membershipId', () => snapshot.id);
      final currentInTx = TenantMembership.fromMap(currentData);
      final roleInTx = currentInTx.role.trim().toLowerCase();
      if (roleInTx == normalizedRole) {
        return currentInTx;
      }

      final updatedInTx = currentInTx.copyWith(
        role: normalizedRole,
        ownerId: _ownerIdForRole(current: currentInTx, role: normalizedRole),
        gerenteId: _gerenteIdForRole(current: currentInTx, role: normalizedRole),
        representanteId: _representanteIdForRole(
          current: currentInTx,
          role: normalizedRole,
        ),
        vendedorId: _vendedorIdForRole(current: currentInTx, role: normalizedRole),
      );

      await _applyHierarchyAggregateDelta(
        tx: tx,
        previous: currentInTx,
        next: updatedInTx,
      );

      tx.set(membershipRef, updatedInTx.toMap(), SetOptions(merge: true));
      return updatedInTx;
    });

    await _writeHierarchyMovement(
      tenantId: updated.tenantId,
      subjectUid: updated.uid,
      subjectRole: updated.role,
      fromMembership: current,
      toMembership: updated,
      reason:
          'membership_role_changed:${current.role.trim().toLowerCase()}->${updated.role.trim().toLowerCase()}',
      actorUid: changedByUid,
    );

    final actorIdentity = await _resolveAuditActorIdentity(changedByUid);

    await _writeAudit(
      tenantId: updated.tenantId,
      membershipId: updated.membershipId,
      action: 'membership_role_changed',
      actorUid: actorIdentity.uid,
      actorLabel: actorIdentity.label,
      actorEmail: actorIdentity.email,
      details: {'oldRole': current.role, 'newRole': updated.role},
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

    await _assertRoleChangeKeepsHierarchy(
      current: target,
      requestedRole: newRole,
    );

    return changeRole(
      membershipId: membershipId,
      newRole: newRole,
      changedByUid: actorUid,
    );
  }

  Future<Map<String, bool>> loadGovernancePolicy(String tenantId) async {
    final tenantDoc = await _firestore
        .collection('tenants')
        .doc(tenantId)
        .get();
    if (!tenantDoc.exists) {
      return _defaultGovernancePolicy();
    }

    final data = tenantDoc.data() ?? <String, dynamic>{};
    final policy =
        data['policy'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return {
      'allowManagerDisableRepresentative':
          policy['allowManagerDisableRepresentative'] as bool? ?? false,
      'allowRepresentativeDisableSeller':
          policy['allowRepresentativeDisableSeller'] as bool? ?? true,
      'allowManagerSendInvites':
          policy['allowManagerSendInvites'] as bool? ?? false,
      'allowRepresentativeSendInvites':
          policy['allowRepresentativeSendInvites'] as bool? ?? false,
      // Personal workspace is controlled by user preference, not tenant policy.
      'allowPersonalWorkspace': true,
    };
  }

  Future<void> updateGovernancePolicy({
    required String tenantId,
    required bool allowManagerDisableRepresentative,
    required bool allowRepresentativeDisableSeller,
    required bool allowManagerSendInvites,
    required bool allowRepresentativeSendInvites,
    required bool allowPersonalWorkspace,
    required String updatedByUid,
  }) async {
    final actorIdentity = await _resolveAuditActorIdentity(updatedByUid);
    await _firestore.collection('tenants').doc(tenantId).set({
      'policy': {
        'allowManagerDisableRepresentative': allowManagerDisableRepresentative,
        'allowRepresentativeDisableSeller': allowRepresentativeDisableSeller,
        'allowManagerSendInvites': allowManagerSendInvites,
        'allowRepresentativeSendInvites': allowRepresentativeSendInvites,
        // Keep as true for backward compatibility with existing documents.
        'allowPersonalWorkspace': true,
      },
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    await _writeAudit(
      tenantId: tenantId,
      membershipId: '',
      action: 'tenant_policy_updated',
      actorUid: actorIdentity.uid,
      actorLabel: actorIdentity.label,
      actorEmail: actorIdentity.email,
      details: {
        'allowManagerDisableRepresentative': allowManagerDisableRepresentative,
        'allowRepresentativeDisableSeller': allowRepresentativeDisableSeller,
        'allowManagerSendInvites': allowManagerSendInvites,
        'allowRepresentativeSendInvites': allowRepresentativeSendInvites,
        'allowPersonalWorkspace': true,
      },
    );
  }

  Future<void> _writeHierarchyMovement({
    required String tenantId,
    required String subjectUid,
    required String subjectRole,
    required TenantMembership fromMembership,
    required TenantMembership toMembership,
    required String reason,
    required String actorUid,
  }) async {
    final movementRef = _firestore
        .collection('tenant_hierarchy_movements')
        .doc();
    final now = DateTime.now().toIso8601String();

    await movementRef.set({
      'movementId': movementRef.id,
      'tenantId': tenantId,
      'subjectUid': subjectUid,
      'subjectRole': subjectRole,
      'fromOwnerId': fromMembership.ownerId,
      'fromGerenteId': fromMembership.gerenteId,
      'fromRepresentanteId': fromMembership.representanteId,
      'fromVendedorId': fromMembership.vendedorId,
      'toOwnerId': toMembership.ownerId,
      'toGerenteId': toMembership.gerenteId,
      'toRepresentanteId': toMembership.representanteId,
      'toVendedorId': toMembership.vendedorId,
      'reason': reason,
      'actorUid': actorUid,
      'createdAt': now,
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
        reason: reason ?? 'Reativado por sincronização do ERP.',
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

    if (role == 'vendedor' && current.ownerId.trim().isEmpty) {
      return '';
    }

    if (current.ownerId.trim().isNotEmpty) {
      return current.ownerId;
    }

    return current.uid;
  }

  String _gerenteIdForRole({
    required TenantMembership current,
    required String role,
  }) {
    if (role == 'owner' || role == 'gerente') {
      return current.uid;
    }

    if (role == 'representante') {
      if (current.gerenteId.trim().isNotEmpty) {
        return current.gerenteId;
      }
      if (current.ownerId.trim().isNotEmpty) {
        return current.ownerId;
      }
      return current.uid;
    }

    if (role == 'vendedor') {
      if (current.ownerId.trim().isEmpty) {
        return '';
      }
      if (current.gerenteId.trim().isNotEmpty) {
        return current.gerenteId;
      }
      return current.ownerId;
    }

    return current.gerenteId;
  }

  String _representanteIdForRole({
    required TenantMembership current,
    required String role,
  }) {
    if (role == 'owner' || role == 'gerente' || role == 'representante') {
      return current.uid;
    }

    if (role == 'vendedor') {
      if (current.ownerId.trim().isEmpty) {
        return '';
      }
      if (current.representanteId.trim().isNotEmpty) {
        return current.representanteId;
      }
      return current.uid;
    }

    return current.representanteId;
  }

  String _vendedorIdForRole({
    required TenantMembership current,
    required String role,
  }) {
    if (role == 'owner' || role == 'gerente' || role == 'representante') {
      return current.uid;
    }

    if (role == 'vendedor') {
      return current.uid;
    }

    return current.vendedorId;
  }

  Future<void> _writeAudit({
    required String tenantId,
    required String membershipId,
    required String action,
    required String actorUid,
    String? actorLabel,
    String? actorEmail,
    Map<String, Object?>? details,
  }) {
    final payload = <String, Object?>{
      'tenantId': tenantId,
      'membershipId': membershipId,
      'action': action,
      'actorUid': actorUid,
      'details': details,
      'createdAt': DateTime.now().toIso8601String(),
    };
    if (actorLabel != null && actorLabel.trim().isNotEmpty) {
      payload['actorLabel'] = actorLabel.trim();
    }
    if (actorEmail != null && actorEmail.trim().isNotEmpty) {
      payload['actorEmail'] = actorEmail.trim();
    }
    return _firestore.collection('tenant_membership_audit').add(payload);
  }

  void _setAuditInTransaction({
    required Transaction tx,
    required String tenantId,
    required String membershipId,
    required String action,
    required String actorUid,
    String? actorLabel,
    String? actorEmail,
    Map<String, Object?>? details,
  }) {
    final auditRef = _firestore.collection('tenant_membership_audit').doc();
    final payload = <String, Object?>{
      'tenantId': tenantId,
      'membershipId': membershipId,
      'action': action,
      'actorUid': actorUid,
      'details': details,
      'createdAt': DateTime.now().toIso8601String(),
    };
    if (actorLabel != null && actorLabel.trim().isNotEmpty) {
      payload['actorLabel'] = actorLabel.trim();
    }
    if (actorEmail != null && actorEmail.trim().isNotEmpty) {
      payload['actorEmail'] = actorEmail.trim();
    }
    tx.set(auditRef, payload);
  }

  Future<_AuditActorIdentity> _resolveAuditActorIdentity(String actorUid) async {
    final normalizedUid = actorUid.trim();
    if (normalizedUid.isEmpty) {
      return const _AuditActorIdentity(uid: 'unknown', label: 'Desconhecido');
    }

    if (normalizedUid == 'system') {
      return const _AuditActorIdentity(uid: 'system', label: 'Sistema');
    }

    if (normalizedUid == 'erp_sync') {
      return const _AuditActorIdentity(
        uid: 'erp_sync',
        label: 'Sincronização ERP',
      );
    }

    try {
      final userDoc = await _firestore.collection('usuarios').doc(normalizedUid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final displayName =
          (userData['displayName'] ?? userData['userName'] ?? userData['nome'] ?? '')
              .toString()
              .trim();
      final email = (userData['email'] ?? userData['userEmail'] ?? '')
          .toString()
          .trim();

      if (displayName.isNotEmpty && email.isNotEmpty) {
        return _AuditActorIdentity(
          uid: normalizedUid,
          label: '$displayName <$email>',
          email: email,
        );
      }

      if (displayName.isNotEmpty) {
        return _AuditActorIdentity(
          uid: normalizedUid,
          label: displayName,
          email: email.isEmpty ? null : email,
        );
      }

      if (email.isNotEmpty) {
        return _AuditActorIdentity(
          uid: normalizedUid,
          label: email,
          email: email,
        );
      }
    } catch (_) {
      // Best effort: fallback to uid when profile lookup is unavailable.
    }

    return _AuditActorIdentity(uid: normalizedUid, label: normalizedUid);
  }

  Future<bool> _canActorManageTarget({
    required String tenantId,
    required String actorUid,
    required TenantMembership target,
  }) async {
    if (target.uid == actorUid) {
      return false;
    }

    final actorUserDoc = await _firestore
        .collection('usuarios')
        .doc(actorUid)
        .get();
    final actorUserData = actorUserDoc.data() ?? <String, dynamic>{};
    final platformRole = (actorUserData['platformRole'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
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

    final actorRole = (actorSnapshot.docs.first.data()['role'] ?? '')
        .toString()
        .toLowerCase();
    final actorData = actorSnapshot.docs.first.data();
    final targetRole = target.role.trim().toLowerCase();
    final tenantDoc = await _firestore
        .collection('tenants')
        .doc(tenantId)
        .get();
    final workspaceType =
        (tenantDoc.data()?['workspaceType'] ?? 'brand_owner_workspace')
            .toString()
            .trim()
            .toLowerCase();
    final policy = await loadGovernancePolicy(tenantId);

    if (workspaceType == 'rep_workspace') {
      if (actorRole == 'owner') {
        return targetRole != 'owner' && target.ownerId == actorUid;
      }

      if (actorRole == 'representante') {
        return policy['allowRepresentativeDisableSeller'] == true &&
            targetRole == 'vendedor' &&
            target.representanteId == actorUid &&
            target.gerenteId == (actorData['gerenteId'] ?? '').toString() &&
            target.ownerId == (actorData['ownerId'] ?? '').toString();
      }

      return false;
    }

    if (workspaceType == 'brand_owner_workspace' && actorRole == 'owner') {
      final targetBelongsToOwner = target.ownerId == actorUid;
      return targetRole != 'owner' && targetBelongsToOwner;
    }

    if (workspaceType == 'brand_owner_workspace' && actorRole == 'gerente') {
      return policy['allowManagerDisableRepresentative'] == true &&
          targetRole == 'representante' &&
          target.gerenteId == actorUid &&
          target.ownerId == (actorData['ownerId'] ?? '').toString();
    }

    if (workspaceType == 'brand_owner_workspace' &&
        actorRole == 'representante') {
      return policy['allowRepresentativeDisableSeller'] == true &&
          targetRole == 'vendedor' &&
          target.representanteId == actorUid &&
          target.gerenteId == (actorData['gerenteId'] ?? '').toString() &&
          target.ownerId == (actorData['ownerId'] ?? '').toString();
    }

    return false;
  }

  Future<void> _assertNoActiveSubordinates(TenantMembership target) async {
    final normalizedRole = target.role.trim().toLowerCase();
    if (normalizedRole != 'gerente' && normalizedRole != 'representante') {
      return;
    }

    final hasTrackedSubordinates =
        target.activeSubordinateCount > 0 ||
        target.activeSellerChildrenCount > 0 ||
        target.activeRepresentativeChildrenCount > 0;
    if (hasTrackedSubordinates) {
      if (normalizedRole == 'gerente') {
        throw StateError(
          'Nao e possivel inativar ou alterar gerente com equipe ativa. Realoque representantes/vendedores antes.',
        );
      }
      throw StateError(
        'Nao e possivel inativar ou alterar representante com vendedores ativos. Realoque vendedores antes.',
      );
    }

    final query = _firestore
        .collection('tenant_memberships')
        .where('tenantId', isEqualTo: target.tenantId)
        .where('ativo', isEqualTo: true)
        .where('state', isEqualTo: 'active')
        .where(
          normalizedRole == 'gerente' ? 'gerenteId' : 'representanteId',
          isEqualTo: target.uid,
        );

    final snapshot = await query.get();
    final hasSubordinate = snapshot.docs.any((doc) {
      final data = doc.data();
      final uid = (data['uid'] ?? '').toString();
      if (uid == target.uid) {
        return false;
      }
      final role = (data['role'] ?? '').toString().trim().toLowerCase();
      if (normalizedRole == 'gerente') {
        return role == 'representante' || role == 'vendedor';
      }
      return role == 'vendedor';
    });

    if (!hasSubordinate) {
      return;
    }

    if (normalizedRole == 'gerente') {
      throw StateError(
        'Nao e possivel inativar ou alterar gerente com equipe ativa. Realoque representantes/vendedores antes.',
      );
    }

    throw StateError(
      'Nao e possivel inativar ou alterar representante com vendedores ativos. Realoque vendedores antes.',
    );
  }

  Future<void> _assertRoleChangeKeepsHierarchy({
    required TenantMembership current,
    required String requestedRole,
  }) async {
    final normalizedCurrentRole = current.role.trim().toLowerCase();
    final normalizedRequestedRole = requestedRole.trim().toLowerCase();
    if (normalizedCurrentRole == normalizedRequestedRole) {
      return;
    }

    if (normalizedCurrentRole == 'gerente' || normalizedCurrentRole == 'representante') {
      await _assertNoActiveSubordinates(current);
    }
  }

  Future<void> _applyHierarchyAggregateDelta({
    required Transaction tx,
    required TenantMembership previous,
    required TenantMembership next,
  }) async {
    final deltasByParentUid = <String, _AggregateDelta>{};

    void applyDelta(TenantMembership membership, int signal) {
      if (!membership.isActive) {
        return;
      }

      final role = membership.role.trim().toLowerCase();
      if (role == 'vendedor') {
        final parentUid = membership.representanteId.trim();
        if (parentUid.isEmpty || parentUid == membership.uid) {
          return;
        }
        final delta = deltasByParentUid.putIfAbsent(
          parentUid,
          () => _AggregateDelta(),
        );
        delta.sellerChildren += signal;
        return;
      }

      if (role == 'representante') {
        final parentUid = membership.gerenteId.trim();
        if (parentUid.isEmpty || parentUid == membership.uid) {
          return;
        }
        final delta = deltasByParentUid.putIfAbsent(
          parentUid,
          () => _AggregateDelta(),
        );
        delta.representativeChildren += signal;
      }
    }

    applyDelta(previous, -1);
    applyDelta(next, 1);

    for (final entry in deltasByParentUid.entries) {
      final parentUid = entry.key;
      final delta = entry.value;
      if (delta.sellerChildren == 0 && delta.representativeChildren == 0) {
        continue;
      }

      final parentMembershipId = '${next.tenantId}_$parentUid';
      final parentRef = _firestore
          .collection('tenant_memberships')
          .doc(parentMembershipId);
      final parentSnapshot = await tx.get(parentRef);
      if (!parentSnapshot.exists) {
        continue;
      }

      final parentData = parentSnapshot.data() ?? <String, dynamic>{};
      parentData.putIfAbsent('membershipId', () => parentSnapshot.id);
      final parent = TenantMembership.fromMap(parentData);
      final parentRole = parent.role.trim().toLowerCase();

      var sellerCount = parent.activeSellerChildrenCount;
      var representativeCount = parent.activeRepresentativeChildrenCount;

      if (parentRole == 'representante') {
        sellerCount = _clampToNonNegative(sellerCount + delta.sellerChildren);
      }

      if (parentRole == 'gerente') {
        representativeCount = _clampToNonNegative(
          representativeCount + delta.representativeChildren,
        );
      }

      final subordinateCount = _clampToNonNegative(
        sellerCount + representativeCount,
      );

      tx.set(parentRef, {
        'activeSellerChildrenCount': sellerCount,
        'activeRepresentativeChildrenCount': representativeCount,
        'activeSubordinateCount': subordinateCount,
      }, SetOptions(merge: true));
    }
  }

  int _clampToNonNegative(int value) {
    if (value < 0) {
      return 0;
    }
    return value;
  }

  Map<String, bool> _defaultGovernancePolicy() {
    return {
      'allowManagerDisableRepresentative': false,
      'allowRepresentativeDisableSeller': true,
      'allowManagerSendInvites': false,
      'allowRepresentativeSendInvites': false,
      'allowPersonalWorkspace': true,
    };
  }
}

class _AggregateDelta {
  int sellerChildren = 0;
  int representativeChildren = 0;
}

class _AuditActorIdentity {
  const _AuditActorIdentity({
    required this.uid,
    required this.label,
    this.email,
  });

  final String uid;
  final String label;
  final String? email;
}
