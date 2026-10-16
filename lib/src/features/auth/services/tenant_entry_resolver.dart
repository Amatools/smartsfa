import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/models/domain_types.dart';
import '../../../core/models/tenant_entry_decision.dart';

class TenantEntryResolver {
  TenantEntryResolver(this._firestore);

  final FirebaseFirestore _firestore;

  Future<TenantEntryDecision?> resolve(User user) async {
    return _resolveWithRetry(user, shouldRefreshToken: true);
  }

  Future<TenantEntryDecision?> _resolveWithRetry(
    User user, {
    required bool shouldRefreshToken,
  }) async {
    try {
      final decision = await _resolveInternal(user);
      if (shouldRefreshToken &&
          decision != null &&
          decision.path == TenantEntryPath.requestAccess) {
        await user.getIdToken(true);
        return await _resolveWithRetry(user, shouldRefreshToken: false);
      }
      return decision;
    } on FirebaseException catch (error) {
      if (!_isPermissionDenied(error)) {
        rethrow;
      }

      if (shouldRefreshToken) {
        await user.getIdToken(true);
        return await _resolveWithRetry(user, shouldRefreshToken: false);
      }

      throw const TenantEntryResolverException(
        code: 'permission-denied',
        message:
            'Sem permissao temporaria para validar memberships. Tente novamente em instantes.',
      );
    }
  }

  Future<TenantEntryDecision?> _resolveInternal(User user) async {
    final userDoc = await _firestore.collection('usuarios').doc(user.uid).get();

    final membershipsSnapshot = await _firestore
        .collection('tenant_memberships')
        .where('uid', isEqualTo: user.uid)
        .where('ativo', isEqualTo: true)
        .get();

    final userData = userDoc.data() ?? <String, dynamic>{};
    final ativoGlobal = userData['ativoGlobal'];
    if (userDoc.exists && ativoGlobal is bool && ativoGlobal == false) {
      return TenantEntryDecision.requestAccess(
        uid: user.uid,
        personalWorkspaceEnabled: true,
      );
    }

    final seeds = <TenantEntryOption>[];
    for (final doc in membershipsSnapshot.docs) {
      final seed = await _readMembership(doc);
      if (seed != null) {
        seeds.add(seed);
      }
    }

    if (seeds.isEmpty) {
      return TenantEntryDecision.requestAccess(
        uid: user.uid,
        personalWorkspaceEnabled: true,
      );
    }

    if (seeds.length == 1) {
      final selected = seeds.first;
      return TenantEntryDecision.direct(
        uid: user.uid,
        tenantId: selected.tenantId,
        tenantName: selected.tenantName,
        role: selected.role,
        defaultTenantId: selected.defaultTenant ? selected.tenantId : selected.tenantId,
      );
    }

    final defaultOption = seeds.where((item) => item.defaultTenant).toList();
    return TenantEntryDecision(
      uid: user.uid,
      path: TenantEntryPath.selector,
      options: seeds,
      defaultTenantId: defaultOption.isNotEmpty ? defaultOption.first.tenantId : null,
    );
  }

  Future<TenantEntryOption?> _readMembership(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final tenantId = data['tenantId']?.toString();
    final role = data['role']?.toString();
    if (tenantId == null || tenantId.isEmpty || role == null || role.isEmpty) {
      return null;
    }

    final membershipState = data['state']?.toString();
    final ativo = data['ativo'] == true;
    if (membershipState != null && membershipState.isNotEmpty) {
      if (membershipState != 'active') {
        return null;
      }
    } else if (!ativo) {
      return null;
    }

    try {
      final tenantDoc = await _firestore.collection('tenants').doc(tenantId).get();
      if (!tenantDoc.exists) {
        return null;
      }

      final tenantData = tenantDoc.data() ?? <String, dynamic>{};
      if (tenantData['ativo'] != true) {
        return null;
      }

      return TenantEntryOption(
        membershipId: doc.id,
        tenantId: tenantId,
        tenantName: (tenantData['nomeFantasia'] ?? tenantId).toString(),
        role: role,
        workspaceType: (tenantData['workspaceType'] ?? 'brand_owner_workspace')
            .toString(),
        defaultTenant: data['defaultTenant'] == true,
      );
    } on FirebaseException catch (error) {
      if (!_isPermissionDenied(error)) {
        rethrow;
      }

      // Keep access path functional when tenant document read is temporarily
      // denied. The shell will re-validate tenant details with live streams.
      return TenantEntryOption(
        membershipId: doc.id,
        tenantId: tenantId,
        tenantName: tenantId,
        role: role,
        workspaceType:
            (data['workspaceType'] ?? 'brand_owner_workspace').toString(),
        defaultTenant: data['defaultTenant'] == true,
      );
    }
  }

  bool _isPermissionDenied(FirebaseException error) {
    return error.code == 'permission-denied' || error.code == 'failed-precondition';
  }
}

class TenantEntryResolverException implements Exception {
  const TenantEntryResolverException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() {
    return 'TenantEntryResolverException($code): $message';
  }
}