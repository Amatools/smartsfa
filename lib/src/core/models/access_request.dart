enum AccessRequestStatus {
  pending('pendente', 'Pendente'),
  approved('aprovado', 'Aprovado'),
  rejected('rejeitado', 'Rejeitado');

  const AccessRequestStatus(this.value, this.label);

  final String value;
  final String label;

  static AccessRequestStatus fromValue(String value) {
    return AccessRequestStatus.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AccessRequestStatus.pending,
    );
  }
}

class AccessRequest {
  const AccessRequest({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.status,
    this.tenantSlugOuConvite,
    this.reviewedBy,
    this.motivo,
    this.createdAt,
    this.updatedAt,
  });

  factory AccessRequest.fromMap(Map<String, Object?> map) {
    return AccessRequest(
      uid: map['uid'] as String? ?? '',
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      tenantSlugOuConvite: map['tenantSlugOuConvite'] as String?,
      status: AccessRequestStatus.fromValue(
        map['status'] as String? ?? AccessRequestStatus.pending.value,
      ),
      reviewedBy: map['reviewedBy'] as String?,
      motivo: map['motivo'] as String?,
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  final String uid;
  final String email;
  final String displayName;
  final String? tenantSlugOuConvite;
  final AccessRequestStatus status;
  final String? reviewedBy;
  final String? motivo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'tenantSlugOuConvite': tenantSlugOuConvite,
      'status': status.value,
      'reviewedBy': reviewedBy,
      'motivo': motivo,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }

  if (value is String) {
    return DateTime.tryParse(value);
  }

  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  return null;
}