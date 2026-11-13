import 'package:cloud_firestore/cloud_firestore.dart';

class MaintainerUserAccount {
  const MaintainerUserAccount({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.platformRole,
    required this.maintainerRole,
    required this.activeGlobal,
    required this.maintainerConsoleEnabled,
    required this.maintainerMfaRequired,
    required this.maintainerPermissions,
    required this.maintainerDeniedPermissions,
    required this.billingAccountState,
    required this.billingGraceUntilAt,
    required this.billingSuspendedAt,
    required this.updatedAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final String platformRole;
  final String maintainerRole;
  final bool activeGlobal;
  final bool maintainerConsoleEnabled;
  final bool maintainerMfaRequired;
  final Set<String> maintainerPermissions;
  final Set<String> maintainerDeniedPermissions;
  final String billingAccountState;
  final DateTime? billingGraceUntilAt;
  final DateTime? billingSuspendedAt;
  final DateTime? updatedAt;

  static MaintainerUserAccount fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return MaintainerUserAccount(
      uid: doc.id,
      email: (data['email'] ?? '').toString().trim(),
      displayName: (data['displayName'] ?? data['name'] ?? '')
          .toString()
          .trim(),
      platformRole: (data['platformRole'] ?? 'none').toString().trim(),
      maintainerRole: _resolveMaintainerRole(data),
      activeGlobal: data['ativoGlobal'] == true,
      maintainerConsoleEnabled: data['maintainerConsoleEnabled'] != false,
      maintainerMfaRequired: data['maintainerMfaRequired'] == true,
      maintainerPermissions: _readStringSet(data['maintainerPermissions']),
      maintainerDeniedPermissions: _readStringSet(
        data['maintainerDeniedPermissions'],
      ),
      billingAccountState: (data['billingAccountState'] ?? 'active')
          .toString()
          .trim(),
      billingGraceUntilAt: _readDateTime(data['billingGraceUntilAt']),
      billingSuspendedAt: _readDateTime(data['billingSuspendedAt']),
      updatedAt: _readDateTime(data['updatedAt']),
    );
  }

  static String _resolveMaintainerRole(Map<String, dynamic> data) {
    final candidates = <Object?>[
      data['maintainerRole'],
      data['maintainer_role'],
      data['roleGlobal'],
      data['globalRole'],
      data['platformRole'],
      data['role'],
    ];

    for (final candidate in candidates) {
      final normalized = (candidate ?? '').toString().trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    return 'none';
  }

  static Set<String> _readStringSet(Object? value) {
    if (value is! Iterable) {
      return const <String>{};
    }

    final parsed = <String>{};
    for (final item in value) {
      final text = (item ?? '').toString().trim();
      if (text.isNotEmpty) {
        parsed.add(text);
      }
    }
    return parsed;
  }

  static DateTime? _readDateTime(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }
}

class MaintainerUserTenantMembership {
  const MaintainerUserTenantMembership({
    required this.membershipId,
    required this.uid,
    required this.tenantId,
    required this.role,
    required this.active,
    required this.state,
  });

  final String membershipId;
  final String uid;
  final String tenantId;
  final String role;
  final bool active;
  final String state;

  bool get isActiveMembership {
    return active && state.trim().toLowerCase() == 'active';
  }

  static MaintainerUserTenantMembership fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return MaintainerUserTenantMembership(
      membershipId: doc.id,
      uid: (data['uid'] ?? '').toString().trim(),
      tenantId: (data['tenantId'] ?? '').toString().trim(),
      role: (data['role'] ?? '').toString().trim(),
      active: data['ativo'] == true,
      state: (data['state'] ?? 'active').toString().trim(),
    );
  }
}

class MaintainerTenantBillingWorkspace {
  const MaintainerTenantBillingWorkspace({
    required this.tenantId,
    required this.tenantName,
    required this.workspaceType,
    required this.billingStatus,
    required this.billingPlanKey,
    required this.billingCycle,
    required this.billingUpdatedAt,
    required this.billingGraceUntilAt,
    required this.stripeCustomerId,
  });

  final String tenantId;
  final String tenantName;
  final String workspaceType;
  final String billingStatus;
  final String billingPlanKey;
  final String billingCycle;
  final DateTime? billingUpdatedAt;
  final DateTime? billingGraceUntilAt;
  final String stripeCustomerId;

  String get normalizedBillingStatus => billingStatus.trim().toLowerCase();

  static MaintainerTenantBillingWorkspace fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final fallbackName = (data['slug'] ?? '').toString().trim();
    final tenantName = (data['nomeFantasia'] ?? fallbackName).toString().trim();
    return MaintainerTenantBillingWorkspace(
      tenantId: doc.id.trim(),
      tenantName: tenantName.isEmpty ? doc.id.trim() : tenantName,
      workspaceType: (data['workspaceType'] ?? '').toString().trim(),
      billingStatus: (data['billingStatus'] ?? 'active').toString().trim(),
      billingPlanKey: (data['billingPlanKey'] ?? '').toString().trim(),
      billingCycle: (data['billingCycle'] ?? '').toString().trim(),
      billingUpdatedAt: _readDateTimeRaw(data['billingUpdatedAt']),
      billingGraceUntilAt: _readDateTimeRaw(data['billingGraceUntilAt']),
      stripeCustomerId: (data['stripeCustomerId'] ?? '').toString().trim(),
    );
  }

  static DateTime? _readDateTimeRaw(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }
}

class MaintainerUserAdminService {
  MaintainerUserAdminService(this._firestore);

  final FirebaseFirestore _firestore;

  static const Set<String> _allowedPlatformRoles = {'none', 'platform_admin'};
  static const Set<String> _allowedMaintainerRoles = {
    'none',
    'platform_observer',
    'platform_operator',
    'platform_admin',
  };

  Stream<List<MaintainerUserAccount>> watchUsers({int limit = 120}) {
    return _firestore
        .collection('usuarios')
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final users = snapshot.docs
              .map(MaintainerUserAccount.fromDoc)
              .toList(growable: false);
          users.sort((a, b) {
            final aEmail = a.email.toLowerCase();
            final bEmail = b.email.toLowerCase();
            if (aEmail != bEmail) {
              return aEmail.compareTo(bEmail);
            }
            return a.uid.compareTo(b.uid);
          });
          return users;
        });
  }

  Stream<List<MaintainerUserTenantMembership>> watchTenantMemberships({
    int limit = 1500,
  }) {
    return _firestore
        .collection('tenant_memberships')
        .where('ativo', isEqualTo: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final memberships = snapshot.docs
              .map(MaintainerUserTenantMembership.fromDoc)
              .where(
                (membership) =>
                    membership.uid.isNotEmpty && membership.tenantId.isNotEmpty,
              )
              .toList(growable: false);

          memberships.sort((a, b) {
            final tenantOrder = a.tenantId.compareTo(b.tenantId);
            if (tenantOrder != 0) {
              return tenantOrder;
            }
            return a.uid.compareTo(b.uid);
          });

          return memberships;
        });
  }

  Stream<Map<String, String>> watchTenantNamesById({int limit = 1500}) {
    return _firestore.collection('tenants').limit(limit).snapshots().map((
      snapshot,
    ) {
      final namesById = <String, String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final tenantId = doc.id.trim();
        if (tenantId.isEmpty) {
          continue;
        }

        final rawName = (data['nomeFantasia'] ?? data['slug'] ?? '')
            .toString()
            .trim();
        namesById[tenantId] = rawName.isEmpty ? tenantId : rawName;
      }
      return namesById;
    });
  }

  Stream<List<MaintainerTenantBillingWorkspace>> watchTenantBillingWorkspaces({
    int limit = 1500,
  }) {
    return _firestore.collection('tenants').limit(limit).snapshots().map((
      snapshot,
    ) {
      final workspaces = snapshot.docs
          .map(MaintainerTenantBillingWorkspace.fromDoc)
          .where((workspace) => workspace.tenantId.isNotEmpty)
          .toList(growable: false);

      workspaces.sort((a, b) {
        final nameOrder = a.tenantName.toLowerCase().compareTo(
          b.tenantName.toLowerCase(),
        );
        if (nameOrder != 0) {
          return nameOrder;
        }
        return a.tenantId.compareTo(b.tenantId);
      });

      return workspaces;
    });
  }

  Future<void> setGlobalActive({
    required String uid,
    required bool active,
    String actorUid = '',
    String actorEmail = '',
    String actorLabel = '',
  }) async {
    final normalizedUid = uid.trim();
    await _patchUser(normalizedUid, {'ativoGlobal': active});
    await _appendPlatformAdminAudit(
      action: active ? 'account_activated' : 'account_deactivated',
      actorUid: actorUid,
      actorEmail: actorEmail,
      actorLabel: actorLabel,
      targetUid: normalizedUid,
      details: {'activeGlobal': active},
    );
  }

  Future<void> setBillingState({
    required String uid,
    required String state,
    DateTime? graceUntil,
    DateTime? suspendedAt,
    String auditReason = 'manual',
    String actorUid = '',
    String actorEmail = '',
    String actorLabel = '',
  }) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw StateError('Uid invalido para atualizar billing.');
    }

    final payload = {
      'billingAccountState': state,
      'billingGraceUntilAt': graceUntil?.toUtc().toIso8601String(),
      'billingSuspendedAt': suspendedAt?.toUtc().toIso8601String(),
      'billingUpdatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _patchUser(normalizedUid, payload);

    final normalizedState = state.trim().toLowerCase();
    var action = 'billing_state_updated';
    if (normalizedState == 'grace') {
      action = 'billing_grace_set';
    } else if (normalizedState == 'active') {
      action = 'billing_normalized';
    } else if (normalizedState == 'suspended') {
      action = 'billing_suspended';
    }

    await _appendPlatformAdminAudit(
      action: action,
      actorUid: actorUid,
      actorEmail: actorEmail,
      actorLabel: actorLabel,
      targetUid: normalizedUid,
      details: {
        'billingAccountState': state,
        'billingGraceUntilAt': payload['billingGraceUntilAt'],
        'billingSuspendedAt': payload['billingSuspendedAt'],
        'reason': auditReason,
      },
    );
  }

  Future<void> grantGracePeriod({
    required String uid,
    required Duration duration,
    String actorUid = '',
    String actorEmail = '',
    String actorLabel = '',
  }) async {
    final days = duration.inDays;
    await setBillingState(
      uid: uid,
      state: 'grace',
      graceUntil: DateTime.now().add(duration),
      suspendedAt: null,
      auditReason: 'grant_${days}_days',
      actorUid: actorUid,
      actorEmail: actorEmail,
      actorLabel: actorLabel,
    );
  }

  Future<void> normalizeBilling({
    required String uid,
    String actorUid = '',
    String actorEmail = '',
    String actorLabel = '',
  }) async {
    await setBillingState(
      uid: uid,
      state: 'active',
      graceUntil: null,
      suspendedAt: null,
      auditReason: 'normalize',
      actorUid: actorUid,
      actorEmail: actorEmail,
      actorLabel: actorLabel,
    );
  }

  Future<void> suspendBilling({
    required String uid,
    String actorUid = '',
    String actorEmail = '',
    String actorLabel = '',
  }) async {
    await setBillingState(
      uid: uid,
      state: 'suspended',
      graceUntil: null,
      suspendedAt: DateTime.now(),
      auditReason: 'suspend',
      actorUid: actorUid,
      actorEmail: actorEmail,
      actorLabel: actorLabel,
    );
  }

  Future<void> saveUserProfile({
    required String uid,
    required String email,
    required String displayName,
    required String platformRole,
    required String maintainerRole,
    required bool activeGlobal,
    required bool maintainerConsoleEnabled,
    required bool maintainerMfaRequired,
    Set<String> maintainerPermissions = const <String>{},
    Set<String> maintainerDeniedPermissions = const <String>{},
    bool isCreate = false,
    String actorUid = '',
    String actorEmail = '',
    String actorLabel = '',
  }) async {
    final normalizedUid = uid.trim();
    final normalizedEmail = email.trim();
    final normalizedDisplayName = displayName.trim();
    final normalizedPlatformRole = _normalizePlatformRole(platformRole);
    final normalizedMaintainerRole = _normalizeMaintainerRole(maintainerRole);

    if (normalizedUid.isEmpty) {
      throw StateError('UID e obrigatorio para salvar o usuario.');
    }

    final safeDisplayName = normalizedDisplayName.isEmpty
        ? (normalizedEmail.isEmpty
              ? normalizedUid
              : normalizedEmail.split('@').first)
        : normalizedDisplayName;

    final granted =
        maintainerPermissions
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final denied =
        maintainerDeniedPermissions
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await _firestore.collection('usuarios').doc(normalizedUid).set({
      'uid': normalizedUid,
      'email': normalizedEmail,
      'displayName': safeDisplayName,
      'name': safeDisplayName,
      'platformRole': normalizedPlatformRole,
      'roleGlobal': normalizedMaintainerRole,
      'maintainerRole': normalizedMaintainerRole,
      'ativoGlobal': activeGlobal,
      'maintainerConsoleEnabled': maintainerConsoleEnabled,
      'maintainerMfaRequired': maintainerMfaRequired,
      'maintainerPermissions': granted,
      'maintainerDeniedPermissions': denied,
      'updatedAt': nowIso,
    }, SetOptions(merge: true));

    await _firestore
        .collection('platform_user_admin_profiles')
        .doc(normalizedUid)
        .set({
          'uid': normalizedUid,
          'maintainerRole': normalizedMaintainerRole,
          'maintainerConsoleEnabled': maintainerConsoleEnabled,
          'maintainerMfaRequired': maintainerMfaRequired,
          'maintainerPermissions': granted,
          'maintainerDeniedPermissions': denied,
          'updatedAt': nowIso,
        }, SetOptions(merge: true));

    await _appendPlatformAdminAudit(
      action: isCreate ? 'admin_user_created' : 'admin_user_updated',
      actorUid: actorUid,
      actorEmail: actorEmail,
      actorLabel: actorLabel,
      targetUid: normalizedUid,
      targetEmail: normalizedEmail,
      targetDisplayName: safeDisplayName,
      details: {
        'platformRole': normalizedPlatformRole,
        'maintainerRole': normalizedMaintainerRole,
        'activeGlobal': activeGlobal,
        'maintainerConsoleEnabled': maintainerConsoleEnabled,
        'maintainerMfaRequired': maintainerMfaRequired,
      },
    );
  }

  Future<void> deleteUser(
    String uid, {
    String actorUid = '',
    String actorEmail = '',
    String actorLabel = '',
  }) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw StateError('UID invalido para exclusao.');
    }

    final userSnapshot = await _firestore
        .collection('usuarios')
        .doc(normalizedUid)
        .get();
    final userData = userSnapshot.data() ?? const <String, dynamic>{};
    final targetEmail = (userData['email'] ?? '').toString().trim();
    final targetDisplayName =
        (userData['displayName'] ?? userData['name'] ?? '').toString().trim();

    await _firestore
        .collection('platform_user_admin_profiles')
        .doc(normalizedUid)
        .delete();
    await _firestore.collection('usuarios').doc(normalizedUid).delete();

    await _appendPlatformAdminAudit(
      action: 'admin_user_deleted',
      actorUid: actorUid,
      actorEmail: actorEmail,
      actorLabel: actorLabel,
      targetUid: normalizedUid,
      targetEmail: targetEmail,
      targetDisplayName: targetDisplayName,
    );
  }

  Future<void> requestUserLifecycleAction({
    required String targetUid,
    required String actionType,
    String reason = '',
    String actorUid = '',
    String actorEmail = '',
    String actorLabel = '',
  }) async {
    final normalizedTargetUid = targetUid.trim();
    final normalizedActionType = actionType.trim().toLowerCase();
    if (normalizedTargetUid.isEmpty) {
      throw StateError(
        'UID alvo invalido para solicitar acao de ciclo de vida.',
      );
    }
    if (normalizedActionType.isEmpty) {
      throw StateError('actionType e obrigatorio.');
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _firestore.collection('workspace_deletion_requests').add({
      'targetUid': normalizedTargetUid,
      'tenantId': '',
      'actionType': normalizedActionType,
      'status': 'requested',
      'requestedByUid': actorUid.trim(),
      'requestedByEmail': actorEmail.trim(),
      'reason': reason.trim(),
      'source': 'maintainer_console',
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtIso': nowIso,
    });

    await _appendPlatformAdminAudit(
      action: 'user_lifecycle_action_requested',
      actorUid: actorUid,
      actorEmail: actorEmail,
      actorLabel: actorLabel,
      targetUid: normalizedTargetUid,
      details: {'actionType': normalizedActionType, 'reason': reason.trim()},
    );
  }

  Future<void> requestWorkspaceLifecycleAction({
    required String tenantId,
    required String actionType,
    String targetUid = '',
    String reason = '',
    String actorUid = '',
    String actorEmail = '',
    String actorLabel = '',
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedActionType = actionType.trim().toLowerCase();
    if (normalizedTenantId.isEmpty) {
      throw StateError(
        'tenantId e obrigatorio para solicitar acao de workspace.',
      );
    }
    if (normalizedActionType.isEmpty) {
      throw StateError('actionType e obrigatorio.');
    }

    final normalizedTargetUid = targetUid.trim();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _firestore.collection('workspace_deletion_requests').add({
      'tenantId': normalizedTenantId,
      'targetUid': normalizedTargetUid,
      'actionType': normalizedActionType,
      'status': 'requested',
      'requestedByUid': actorUid.trim(),
      'requestedByEmail': actorEmail.trim(),
      'reason': reason.trim(),
      'breakGlass': true,
      'source': 'maintainer_console',
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtIso': nowIso,
    });

    await _appendPlatformAdminAudit(
      action: 'workspace_lifecycle_action_requested',
      actorUid: actorUid,
      actorEmail: actorEmail,
      actorLabel: actorLabel,
      targetUid: actorUid,
      details: {
        'tenantId': normalizedTenantId,
        'targetUid': normalizedTargetUid,
        'actionType': normalizedActionType,
        'reason': reason.trim(),
        'breakGlass': true,
      },
    );
  }

  String _normalizePlatformRole(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (_allowedPlatformRoles.contains(normalized)) {
      return normalized;
    }
    return 'none';
  }

  String _normalizeMaintainerRole(String raw) {
    final normalized = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (_allowedMaintainerRoles.contains(normalized)) {
      return normalized;
    }
    return 'none';
  }

  Future<void> _patchUser(String uid, Map<String, dynamic> fields) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw StateError('Uid invalido para atualizar conta.');
    }

    final payload = <String, dynamic>{
      ...fields,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

    await _firestore
        .collection('usuarios')
        .doc(normalizedUid)
        .set(payload, SetOptions(merge: true));
  }

  Future<void> _appendPlatformAdminAudit({
    required String action,
    required String actorUid,
    String actorEmail = '',
    String actorLabel = '',
    required String targetUid,
    String targetEmail = '',
    String targetDisplayName = '',
    Map<String, dynamic>? details,
  }) async {
    final normalizedActorUid = actorUid.trim();
    final normalizedTargetUid = targetUid.trim();
    if (normalizedActorUid.isEmpty || normalizedTargetUid.isEmpty) {
      return;
    }

    final payload = <String, dynamic>{
      'action': action.trim(),
      'actorUid': normalizedActorUid,
      if (actorEmail.trim().isNotEmpty) 'actorEmail': actorEmail.trim(),
      if (actorLabel.trim().isNotEmpty) 'actorLabel': actorLabel.trim(),
      'targetUid': normalizedTargetUid,
      if (targetEmail.trim().isNotEmpty) 'targetEmail': targetEmail.trim(),
      if (targetDisplayName.trim().isNotEmpty)
        'targetDisplayName': targetDisplayName.trim(),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (details != null) {
      payload['details'] = details;
    }

    await _firestore.collection('platform_admin_audit').add(payload);
  }
}
