import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SoloWorkspaceService {
  SoloWorkspaceService(this._firestore);

  final FirebaseFirestore _firestore;

  Future<SoloWorkspaceResult> bootstrapOwnerWorkspace(User user) async {
    return createOwnerWorkspace(
      user: user,
      plan: OnboardingPlan.solo,
      workspaceName: _soloTenantName(user),
    );
  }

  Future<SoloWorkspaceResult> createOwnerWorkspace({
    required User user,
    required OnboardingPlan plan,
    required String workspaceName,
    String? cnpj,
  }) async {
    final normalizedName = workspaceName.trim();
    if (normalizedName.isEmpty) {
      throw StateError('Informe um nome para o workspace.');
    }

    final tenantId = _tenantIdForPlan(
      uid: user.uid,
      plan: plan,
      workspaceName: normalizedName,
    );
    final tenantName = normalizedName;
    final membershipId = '${tenantId}_${user.uid}';

    final tenantRef = _firestore.collection('tenants').doc(tenantId);
    final userRef = _firestore.collection('usuarios').doc(user.uid);
    final membershipRef = _firestore.collection('tenant_memberships').doc(membershipId);
    final requestRef = _firestore.collection('solicitacoes_acesso').doc(user.uid);

    await _firestore.runTransaction((tx) async {
      tx.set(
        tenantRef,
        {
          'tenantId': tenantId,
          'slug': tenantId,
          'nomeFantasia': tenantName,
          'ativo': true,
          'operationMode': 'manual',
          'erpProvider': 'none',
          'plan': plan.value,
          'ownerUid': user.uid,
          if (cnpj != null && cnpj.trim().isNotEmpty) 'cnpj': cnpj.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        userRef,
        {
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName': user.displayName ?? (user.email ?? user.uid),
          'platformRole': 'none',
          'ativoGlobal': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        membershipRef,
        {
          'membershipId': membershipId,
          'tenantId': tenantId,
          'uid': user.uid,
          'role': 'owner',
          'ativo': true,
          'defaultTenant': true,
          'state': 'active',
          'ownerId': user.uid,
          'gerenteId': '',
          'representanteId': '',
          'vendedorId': '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Remove pending request to avoid keeping user stuck in access-request state.
      tx.delete(requestRef);
    });

    return SoloWorkspaceResult(
      tenantId: tenantId,
      tenantName: tenantName,
      membershipId: membershipId,
    );
  }

  String _soloTenantName(User user) {
    final preferred = (user.displayName ?? '').trim();
    if (preferred.isNotEmpty) {
      return '$preferred (Solo)';
    }

    final email = (user.email ?? '').trim();
    if (email.isNotEmpty) {
      return '${email.split('@').first} (Solo)';
    }

    return 'Workspace Solo';
  }

  String _tenantIdForPlan({
    required String uid,
    required OnboardingPlan plan,
    required String workspaceName,
  }) {
    if (plan == OnboardingPlan.solo) {
      return 'solo_$uid';
    }

    final slug = _slugify(workspaceName);
    return 'self_${uid}_$slug';
  }

  String _slugify(String value) {
    final lowered = value.toLowerCase();
    final slug = lowered
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    if (slug.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch.toString();
    }

    if (slug.length <= 48) {
      return slug;
    }

    return slug.substring(0, 48);
  }
}

enum OnboardingPlan {
  solo('solo'),
  team('team'),
  enterprise('enterprise');

  const OnboardingPlan(this.value);
  final String value;
}

class SoloWorkspaceResult {
  const SoloWorkspaceResult({
    required this.tenantId,
    required this.tenantName,
    required this.membershipId,
  });

  final String tenantId;
  final String tenantName;
  final String membershipId;
}
