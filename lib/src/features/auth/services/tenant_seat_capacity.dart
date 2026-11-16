class TenantSeatCapacitySnapshot {
  const TenantSeatCapacitySnapshot({
    required this.includedSeats,
    required this.addonSeats,
    required this.configuredLimit,
    required this.effectiveLimit,
    required this.activeMembers,
    required this.autoAdjustedToCurrentUsage,
  });

  factory TenantSeatCapacitySnapshot.fromTenantData({
    required Map<String, dynamic> tenantData,
    required int activeMembers,
  }) {
    final workspaceType = _normalize(tenantData['workspaceType']);
    final billingPlanKey = _normalize(tenantData['billingPlanKey']);
    final planTier = _normalize(tenantData['planTier']);

    final includedSeats = _intFromValue(
      tenantData['billingSeatsIncluded'],
      fallback: _defaultIncludedSeats(
        workspaceType: workspaceType,
        billingPlanKey: billingPlanKey,
        planTier: planTier,
      ),
    );
    final addonSeats = _intFromValue(
      tenantData['billingSeatsAddon'],
      fallback: _intFromValue(tenantData['billingSeatAddons']),
    );

    final configuredLimit = (includedSeats + addonSeats).clamp(1, 99999);
    final normalizedActiveMembers = activeMembers < 0 ? 0 : activeMembers;
    final autoAdjustedToCurrentUsage = normalizedActiveMembers > configuredLimit;
    final effectiveLimit = autoAdjustedToCurrentUsage
        ? normalizedActiveMembers
        : configuredLimit;

    return TenantSeatCapacitySnapshot(
      includedSeats: includedSeats,
      addonSeats: addonSeats,
      configuredLimit: configuredLimit,
      effectiveLimit: effectiveLimit,
      activeMembers: normalizedActiveMembers,
      autoAdjustedToCurrentUsage: autoAdjustedToCurrentUsage,
    );
  }

  final int includedSeats;
  final int addonSeats;
  final int configuredLimit;
  final int effectiveLimit;
  final int activeMembers;
  final bool autoAdjustedToCurrentUsage;

  int get remainingSeats {
    final remaining = effectiveLimit - activeMembers;
    return remaining < 0 ? 0 : remaining;
  }

  bool get hasAvailableSeats => remainingSeats > 0;
}

int _defaultIncludedSeats({
  required String workspaceType,
  required String billingPlanKey,
  required String planTier,
}) {
  if (workspaceType == 'seller_solo_workspace') {
    return 1;
  }

  final tierSeatMatch = RegExp(r'(\d+)').firstMatch(planTier);
  if (tierSeatMatch != null) {
    final parsed = int.tryParse(tierSeatMatch.group(1) ?? '');
    if (parsed != null && parsed > 0) {
      return parsed;
    }
  }

  if (billingPlanKey == 'solo') {
    return 1;
  }

  if (billingPlanKey == 'team') {
    return 1;
  }

  if (billingPlanKey == 'enterprise') {
    return 3;
  }

  if (workspaceType == 'rep_workspace') {
    return 1;
  }

  if (workspaceType == 'brand_owner_workspace') {
    return 3;
  }

  return 1;
}

int _intFromValue(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value < 0 ? 0 : value;
  }

  if (value is num) {
    final number = value.toInt();
    return number < 0 ? 0 : number;
  }

  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) {
      return parsed < 0 ? 0 : parsed;
    }
  }

  return fallback < 0 ? 0 : fallback;
}

String _normalize(Object? value) {
  return (value ?? '').toString().trim().toLowerCase();
}