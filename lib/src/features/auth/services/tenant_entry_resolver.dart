import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/models/domain_types.dart';
import '../../../core/models/tenant_entry_decision.dart';

class TenantEntryResolver {
  TenantEntryResolver(this._firestore);

  final FirebaseFirestore _firestore;

  Future<TenantEntryDecision?> resolve(User user) async {
    final userDoc = await _firestore.collection('usuarios').doc(user.uid).get();
    if (!userDoc.exists) {
      return TenantEntryDecision.personalWorkspace(uid: user.uid);
    }

    final userData = userDoc.data() ?? <String, dynamic>{};
    const personalWorkspaceEnabled = true;
    if (userData['ativoGlobal'] != true) {
      return TenantEntryDecision.requestAccess(
        uid: user.uid,
        personalWorkspaceEnabled: personalWorkspaceEnabled,
      );
    }

    final membershipsSnapshot = await _firestore
        .collection('tenant_memberships')
        .where('uid', isEqualTo: user.uid)
        .where('ativo', isEqualTo: true)
        .get();

    final seeds = <TenantEntryOption>[];
    for (final doc in membershipsSnapshot.docs) {
      final seed = await _readMembership(doc);
      if (seed != null) {
        seeds.add(seed);
      }
    }

    if (seeds.isEmpty) {
      return TenantEntryDecision.personalWorkspace(uid: user.uid);
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
      defaultTenant: data['defaultTenant'] == true,
    );
  }
}