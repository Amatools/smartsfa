enum TenantInvitationStatus {
  pending('pending', 'Pendente'),
  accepted('accepted', 'Aceito'),
  declined('declined', 'Recusado'),
  expired('expired', 'Expirado'),
  revoked('revoked', 'Revogado');

  const TenantInvitationStatus(this.value, this.label);

  final String value;
  final String label;

  static TenantInvitationStatus fromValue(String value) {
    return TenantInvitationStatus.values.firstWhere(
      (item) => item.value == value,
      orElse: () => TenantInvitationStatus.pending,
    );
  }
}

class TenantInvitation {
  const TenantInvitation({
    required this.token,
    required this.tenantId,
    required this.role,
    required this.status,
    this.invitedEmail,
    this.defaultTenant = false,
    this.expiresAt,
    this.acceptedByUid,
    this.acceptedAt,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  factory TenantInvitation.fromMap(Map<String, Object?> map) {
    return TenantInvitation(
      token: map['token'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      role: map['role'] as String? ?? 'vendedor',
      status: TenantInvitationStatus.fromValue(
        map['status'] as String? ?? TenantInvitationStatus.pending.value,
      ),
      invitedEmail: map['invitedEmail'] as String?,
      defaultTenant: map['defaultTenant'] as bool? ?? false,
      expiresAt: _readDateTime(map['expiresAt']),
      acceptedByUid: map['acceptedByUid'] as String?,
      acceptedAt: _readDateTime(map['acceptedAt']),
      createdByUid: map['createdByUid'] as String?,
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  final String token;
  final String tenantId;
  final String role;
  final TenantInvitationStatus status;
  final String? invitedEmail;
  final bool defaultTenant;
  final DateTime? expiresAt;
  final String? acceptedByUid;
  final DateTime? acceptedAt;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) {
      return false;
    }

    return DateTime.now().isAfter(expiry);
  }

  Map<String, Object?> toMap() {
    return {
      'token': token,
      'tenantId': tenantId,
      'role': role,
      'status': status.value,
      'invitedEmail': invitedEmail,
      'defaultTenant': defaultTenant,
      'expiresAt': expiresAt?.toIso8601String(),
      'acceptedByUid': acceptedByUid,
      'acceptedAt': acceptedAt?.toIso8601String(),
      'createdByUid': createdByUid,
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