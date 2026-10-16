enum TenantMembershipState {
  active('active', 'Ativo'),
  inactive('inactive', 'Inativo'),
  revoked('revoked', 'Revogado');

  const TenantMembershipState(this.value, this.label);

  final String value;
  final String label;

  static TenantMembershipState fromValue(String value) {
    return TenantMembershipState.values.firstWhere(
      (item) => item.value == value,
      orElse: () => TenantMembershipState.active,
    );
  }
}

class TenantMembership {
  const TenantMembership({
    required this.membershipId,
    required this.tenantId,
    required this.uid,
    required this.role,
    required this.ativo,
    required this.defaultTenant,
    required this.ownerId,
    required this.gerenteId,
    required this.representanteId,
    required this.vendedorId,
    this.activeSellerChildrenCount = 0,
    this.activeRepresentativeChildrenCount = 0,
    this.activeSubordinateCount = 0,
    this.userName,
    this.userEmail,
    this.state = TenantMembershipState.active,
    this.revokedByUid,
    this.revokedReason,
    this.revokedAt,
    this.lastSyncedAt,
  });

  final String membershipId;
  final String tenantId;
  final String uid;
  final String role;
  final bool ativo;
  final bool defaultTenant;
  final String ownerId;
  final String gerenteId;
  final String representanteId;
  final String vendedorId;
  final int activeSellerChildrenCount;
  final int activeRepresentativeChildrenCount;
  final int activeSubordinateCount;
  final String? userName;
  final String? userEmail;
  final TenantMembershipState state;
  final String? revokedByUid;
  final String? revokedReason;
  final DateTime? revokedAt;
  final DateTime? lastSyncedAt;

  bool get isActive => ativo && state == TenantMembershipState.active;

  TenantMembership copyWith({
    String? membershipId,
    String? tenantId,
    String? uid,
    String? role,
    bool? ativo,
    bool? defaultTenant,
    String? ownerId,
    String? gerenteId,
    String? representanteId,
    String? vendedorId,
    int? activeSellerChildrenCount,
    int? activeRepresentativeChildrenCount,
    int? activeSubordinateCount,
    String? userName,
    String? userEmail,
    TenantMembershipState? state,
    String? revokedByUid,
    String? revokedReason,
    DateTime? revokedAt,
    DateTime? lastSyncedAt,
  }) {
    return TenantMembership(
      membershipId: membershipId ?? this.membershipId,
      tenantId: tenantId ?? this.tenantId,
      uid: uid ?? this.uid,
      role: role ?? this.role,
      ativo: ativo ?? this.ativo,
      defaultTenant: defaultTenant ?? this.defaultTenant,
      ownerId: ownerId ?? this.ownerId,
      gerenteId: gerenteId ?? this.gerenteId,
      representanteId: representanteId ?? this.representanteId,
      vendedorId: vendedorId ?? this.vendedorId,
        activeSellerChildrenCount:
          activeSellerChildrenCount ?? this.activeSellerChildrenCount,
        activeRepresentativeChildrenCount:
          activeRepresentativeChildrenCount ??
          this.activeRepresentativeChildrenCount,
        activeSubordinateCount:
          activeSubordinateCount ?? this.activeSubordinateCount,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      state: state ?? this.state,
      revokedByUid: revokedByUid ?? this.revokedByUid,
      revokedReason: revokedReason ?? this.revokedReason,
      revokedAt: revokedAt ?? this.revokedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  TenantMembership revoke({
    required String revokedByUid,
    String? reason,
    DateTime? revokedAt,
  }) {
    return copyWith(
      ativo: false,
      state: TenantMembershipState.revoked,
      revokedByUid: revokedByUid,
      revokedReason: reason,
      revokedAt: revokedAt ?? DateTime.now(),
    );
  }

  TenantMembership deactivate({
    String? deactivatedByUid,
    String? reason,
    DateTime? deactivatedAt,
  }) {
    return copyWith(
      ativo: false,
      state: TenantMembershipState.inactive,
      revokedByUid: deactivatedByUid,
      revokedReason: reason,
      revokedAt: deactivatedAt ?? DateTime.now(),
    );
  }

  TenantMembership reactivate({DateTime? lastSyncedAt}) {
    return copyWith(
      ativo: true,
      state: TenantMembershipState.active,
      revokedByUid: null,
      revokedReason: null,
      revokedAt: null,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'membershipId': membershipId,
      'tenantId': tenantId,
      'uid': uid,
      'role': role,
      'ativo': ativo,
      'defaultTenant': defaultTenant,
      'ownerId': ownerId,
      'gerenteId': gerenteId,
      'representanteId': representanteId,
      'vendedorId': vendedorId,
      'activeSellerChildrenCount': activeSellerChildrenCount,
      'activeRepresentativeChildrenCount': activeRepresentativeChildrenCount,
      'activeSubordinateCount': activeSubordinateCount,
      'userName': userName,
      'userEmail': userEmail,
      'state': state.value,
      'revokedByUid': revokedByUid,
      'revokedReason': revokedReason,
      'revokedAt': revokedAt?.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }

  factory TenantMembership.fromMap(Map<String, Object?> map) {
    return TenantMembership(
      membershipId: map['membershipId'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      uid: map['uid'] as String? ?? '',
      role: map['role'] as String? ?? '',
      ativo: map['ativo'] as bool? ?? true,
      defaultTenant: map['defaultTenant'] as bool? ?? false,
      ownerId: map['ownerId'] as String? ?? '',
      gerenteId: map['gerenteId'] as String? ?? '',
      representanteId: map['representanteId'] as String? ?? '',
      vendedorId: map['vendedorId'] as String? ?? '',
      activeSellerChildrenCount: _readInt(map['activeSellerChildrenCount']),
      activeRepresentativeChildrenCount: _readInt(
        map['activeRepresentativeChildrenCount'],
      ),
      activeSubordinateCount: _readInt(map['activeSubordinateCount']),
      userName:
          map['userName'] as String? ??
          map['displayName'] as String? ??
          map['name'] as String?,
      userEmail:
          map['userEmail'] as String? ?? map['email'] as String?,
      state: TenantMembershipState.fromValue(
        map['state'] as String? ?? TenantMembershipState.active.value,
      ),
      revokedByUid: map['revokedByUid'] as String?,
      revokedReason: map['revokedReason'] as String?,
      revokedAt: _readDateTime(map['revokedAt']),
      lastSyncedAt: _readDateTime(map['lastSyncedAt']),
    );
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

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(value) ?? 0;
  }

  return 0;
}
