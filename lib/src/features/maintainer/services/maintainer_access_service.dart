import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/maintainer_access_decision.dart';

class MaintainerAccessService {
  MaintainerAccessService(this._firestore);

  final FirebaseFirestore _firestore;

  static const Set<String> _allowedRoles = {
    'platform_observer',
    'platform_operator',
    'platform_admin',
  };

  static const Map<String, Set<String>> _defaultPermissionsByRole = {
    'platform_observer': {
      MaintainerPermission.viewHome,
      MaintainerPermission.viewOverview,
    },
    'platform_operator': {
      MaintainerPermission.viewHome,
      MaintainerPermission.viewOverview,
      MaintainerPermission.viewUsers,
      MaintainerPermission.manageUserStatus,
    },
    'platform_admin': MaintainerPermission.all,
  };

  static const Set<String> _requiresPlatformAdminPermissions = {
    MaintainerPermission.viewUsers,
    MaintainerPermission.viewBillingIntegrations,
    MaintainerPermission.manageUserStatus,
    MaintainerPermission.manageUserBilling,
    MaintainerPermission.manageUserCrud,
    MaintainerPermission.manageUserPermissions,
    MaintainerPermission.manageImpersonation,
    MaintainerPermission.manageBillingIntegrations,
  };

  static String normalizeRole(String rawRole) {
    return rawRole.trim().toLowerCase().replaceAll(' ', '_');
  }

  static bool isPotentialMaintainerRole(String rawRole) {
    return _allowedRoles.contains(normalizeRole(rawRole));
  }

  Future<MaintainerAccessDecision> evaluateAccess({
    required String uid,
    String membershipRole = '',
  }) async {
    final normalizedMembershipRole = normalizeRole(membershipRole);
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return const MaintainerAccessDecision(
        granted: false,
        effectiveRole: '',
        reason: 'Sessao invalida. Faca login novamente.',
        grantedPermissions: {},
      );
    }

    final doc = await _loadUserDoc(normalizedUid);
    if (!doc.exists) {
      return const MaintainerAccessDecision(
        granted: false,
        effectiveRole: '',
        reason: 'Usuario nao encontrado na base de seguranca.',
        grantedPermissions: {},
      );
    }

    final userData = doc.data() ?? <String, dynamic>{};
    final platformDoc = await _loadPlatformAdminProfileDoc(normalizedUid);
    final platformData = platformDoc.data() ?? userData;

    if (userData['ativo'] == false || userData['ativoGlobal'] == false) {
      return const MaintainerAccessDecision(
        granted: false,
        effectiveRole: '',
        reason: 'Conta inativa para acesso de mantenedor.',
        grantedPermissions: {},
      );
    }

    if (platformData['maintainerConsoleEnabled'] == false) {
      return const MaintainerAccessDecision(
        granted: false,
        effectiveRole: '',
        reason: 'Acesso ao painel de mantenedor foi desabilitado.',
        grantedPermissions: {},
      );
    }

    final normalizedGlobalRole = _resolveGlobalRole(platformData);
    final globalRoleAllowed = _allowedRoles.contains(normalizedGlobalRole);
    final membershipRoleAllowed = _allowedRoles.contains(
      normalizedMembershipRole,
    );

    if (!globalRoleAllowed && !membershipRoleAllowed) {
      final debugRole = normalizedGlobalRole.isEmpty
          ? normalizedMembershipRole
          : normalizedGlobalRole;
      return MaintainerAccessDecision(
        granted: false,
        effectiveRole: '',
        reason:
            'Sem permissao de plataforma (observer/operator/admin) para o painel de mantenedor. Papel atual: ${debugRole.isEmpty ? 'none' : debugRole}.',
        grantedPermissions: const {},
      );
    }

    final effectiveRole = globalRoleAllowed
        ? normalizedGlobalRole
        : normalizedMembershipRole;

    final mfaRequired = platformData['maintainerMfaRequired'] == true;
    final mfaVerified = platformData['maintainerMfaVerified'] == true;
    if (mfaRequired && !mfaVerified) {
      return MaintainerAccessDecision(
        granted: false,
        effectiveRole: effectiveRole,
        reason: 'Acesso bloqueado: MFA obrigatorio para painel de mantenedor (pendente de verificacao).',
        grantedPermissions: const {},
      );
    }

    final userPlatformRole = _resolveGlobalRole(platformData);
    final basePermissions =
        _defaultPermissionsByRole[effectiveRole] ??
        const <String>{MaintainerPermission.viewHome};
    final grantedPermissions = _resolveGrantedPermissions(
      basePermissions: basePermissions,
      userData: platformData,
      isPlatformAdminDoc: userPlatformRole == 'platform_admin',
    );

    return MaintainerAccessDecision(
      granted: true,
      effectiveRole: effectiveRole,
      reason: 'Acesso autorizado para operacao de mantenedor.',
      grantedPermissions: grantedPermissions,
    );
  }

  Set<String> _resolveGrantedPermissions({
    required Set<String> basePermissions,
    required Map<String, dynamic> userData,
    required bool isPlatformAdminDoc,
  }) {
    final permissions = Set<String>.from(basePermissions);
    permissions.addAll(_readPermissionList(userData['maintainerPermissions']));
    permissions.removeAll(
      _readPermissionList(userData['maintainerDeniedPermissions']),
    );
    permissions.retainAll(MaintainerPermission.all);

    if (!isPlatformAdminDoc) {
      permissions.removeAll(_requiresPlatformAdminPermissions);
    }

    if (permissions.isEmpty) {
      permissions.add(MaintainerPermission.viewHome);
    }

    return permissions;
  }

  Set<String> _readPermissionList(Object? rawValue) {
    if (rawValue is! Iterable) {
      return const <String>{};
    }

    final normalized = <String>{};
    for (final item in rawValue) {
      final permission = (item ?? '').toString().trim();
      if (permission.isNotEmpty) {
        normalized.add(permission);
      }
    }
    return normalized;
  }

  String _resolveGlobalRole(Map<String, dynamic> userData) {
    final candidates = <Object?>[
      userData['maintainerRole'],
      userData['maintainer_role'],
      userData['roleGlobal'],
      userData['globalRole'],
      userData['platformRole'],
      userData['platform_role'],
      userData['role'],
    ];

    for (final candidate in candidates) {
      final normalized = normalizeRole((candidate ?? '').toString());
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    return '';
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadUserDoc(
    String uid,
  ) async {
    final ref = _firestore.collection('usuarios').doc(uid);
    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 250),
      Duration(milliseconds: 700),
    ];

    for (final delay in retryDelays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }

      try {
        return await ref.get(const GetOptions(source: Source.server));
      } catch (_) {
        // Ignore and retry - auth/session hydration right after refresh may lag.
      }
    }

    try {
      return await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      return ref.get();
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadPlatformAdminProfileDoc(
    String uid,
  ) async {
    final ref = _firestore.collection('platform_user_admin_profiles').doc(uid);
    try {
      return await ref.get(const GetOptions(source: Source.server));
    } catch (_) {
      try {
        return await ref.get(const GetOptions(source: Source.cache));
      } catch (_) {
        try {
          return await ref.get();
        } catch (_) {
          // If platform profile read is not available, continue with usuarios data.
          return _loadUserDoc(uid);
        }
      }
    }
  }
}
