import 'package:cloud_firestore/cloud_firestore.dart';

class MaintainerOverviewSnapshot {
  const MaintainerOverviewSnapshot({
    required this.totalTenants,
    required this.activeTenants,
    required this.totalMemberships,
    required this.activeMemberships,
    required this.pendingInvites,
    required this.pendingAccessRequests,
  });

  final int? totalTenants;
  final int? activeTenants;
  final int? totalMemberships;
  final int? activeMemberships;
  final int? pendingInvites;
  final int? pendingAccessRequests;
}

class MaintainerOverviewService {
  MaintainerOverviewService(this._firestore);

  final FirebaseFirestore _firestore;

  Future<MaintainerOverviewSnapshot> loadSnapshot() async {
    final totalTenants = await _safeCount(_firestore.collection('tenants'));
    final activeTenants = await _safeCount(
      _firestore.collection('tenants').where('ativo', isEqualTo: true),
    );
    final totalMemberships = await _safeCount(
      _firestore.collection('tenant_memberships'),
    );
    final activeMemberships = await _safeCount(
      _firestore
          .collection('tenant_memberships')
          .where('ativo', isEqualTo: true)
          .where('state', isEqualTo: 'active'),
    );
    final pendingInvites = await _safeCount(
      _firestore
          .collection('tenant_invitations')
          .where('status', isEqualTo: 'pending'),
    );
    final pendingAccessRequests = await _safeCount(
      _firestore
          .collection('solicitacoes_acesso')
          .where('status', isEqualTo: 'pendente'),
    );

    return MaintainerOverviewSnapshot(
      totalTenants: totalTenants,
      activeTenants: activeTenants,
      totalMemberships: totalMemberships,
      activeMemberships: activeMemberships,
      pendingInvites: pendingInvites,
      pendingAccessRequests: pendingAccessRequests,
    );
  }

  Future<int?> _safeCount(Query<Map<String, dynamic>> query) async {
    try {
      final aggregate = await query.count().get();
      return aggregate.count;
    } catch (_) {
      return null;
    }
  }
}
