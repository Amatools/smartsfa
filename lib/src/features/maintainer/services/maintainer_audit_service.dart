import 'package:cloud_firestore/cloud_firestore.dart';

class MaintainerCriticalAuditEntry {
  const MaintainerCriticalAuditEntry({
    required this.id,
    required this.source,
    required this.action,
    required this.actorUid,
    required this.actorLabel,
    required this.actorEmail,
    required this.targetUid,
    required this.targetLabel,
    required this.targetEmail,
    required this.createdAt,
    required this.details,
  });

  final String id;
  final String source;
  final String action;
  final String actorUid;
  final String actorLabel;
  final String actorEmail;
  final String targetUid;
  final String targetLabel;
  final String targetEmail;
  final DateTime? createdAt;
  final Map<String, dynamic> details;

  String get sourceLabel {
    if (source == 'platform_admin') {
      return 'Admin';
    }
    return source;
  }

  String get actionLabel {
    switch (action) {
      case 'admin_user_created':
        return 'Usuario admin criado';
      case 'admin_user_updated':
        return 'Usuario admin atualizado';
      case 'admin_user_deleted':
        return 'Usuario excluido';
      case 'account_activated':
        return 'Conta ativada';
      case 'account_deactivated':
        return 'Conta desativada';
      case 'billing_grace_set':
        return 'Billing em graca';
      case 'billing_normalized':
        return 'Billing normalizado';
      case 'billing_suspended':
        return 'Billing suspenso';
      case 'impersonation_session_started':
        return 'Acesso assistido iniciado';
      case 'impersonation_session_consumed':
        return 'Acesso assistido consumido';
      default:
        return action;
    }
  }

  static MaintainerCriticalAuditEntry fromPlatformDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return MaintainerCriticalAuditEntry(
      id: doc.id,
      source: 'platform_admin',
      action: (data['action'] ?? '').toString().trim(),
      actorUid: (data['actorUid'] ?? '').toString().trim(),
      actorLabel: (data['actorLabel'] ?? '').toString().trim(),
      actorEmail: (data['actorEmail'] ?? '').toString().trim(),
      targetUid: (data['targetUid'] ?? '').toString().trim(),
      targetLabel: (data['targetDisplayName'] ?? '').toString().trim(),
      targetEmail: (data['targetEmail'] ?? '').toString().trim(),
      createdAt: _readDateTime(data['createdAt']),
      details: _readMap(data['details']),
    );
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

  static Map<String, dynamic> _readMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }
}

class MaintainerAuditService {
  MaintainerAuditService(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<MaintainerCriticalAuditEntry>> watchCriticalEvents({
    int limit = 350,
  }) {
    final effectiveLimit = limit < 50 ? 50 : limit;
    return _firestore
        .collection('platform_admin_audit')
        .orderBy('createdAt', descending: true)
        .limit(effectiveLimit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(MaintainerCriticalAuditEntry.fromPlatformDoc)
              .toList(growable: false),
        );
  }
}
