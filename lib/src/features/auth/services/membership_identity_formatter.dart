String buildMembershipUserName({
  required String uid,
  String? authDisplayName,
  String? email,
  String? tenantName,
}) {
  final normalizedDisplayName = _sanitizeDisplayName(
    authDisplayName ?? '',
    tenantName: tenantName ?? '',
  );
  if (normalizedDisplayName.isNotEmpty) {
    return normalizedDisplayName;
  }

  final normalizedEmail = (email ?? '').trim().toLowerCase();
  if (normalizedEmail.isNotEmpty) {
    return _nameFromEmail(normalizedEmail);
  }

  return uid.trim();
}

String _sanitizeDisplayName(String rawName, {required String tenantName}) {
  var normalized = rawName.trim();
  if (normalized.isEmpty) {
    return '';
  }

  final cleanedTenantName = tenantName.trim();
  if (cleanedTenantName.isNotEmpty) {
    normalized = normalized.replaceAll(
      RegExp(RegExp.escape(cleanedTenantName), caseSensitive: false),
      ' ',
    );
  }

  normalized = normalized.replaceFirst(
    RegExp(
      r'^(owner|gerente|representante|vendedor|administrador|admin)\s*[:\-]?\s+',
      caseSensitive: false,
    ),
    '',
  );

  normalized = normalized.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  normalized = normalized
      .replaceAll(RegExp(r'^[\-:;,|\s]+'), '')
      .replaceAll(RegExp(r'[\-:;,|\s]+$'), '')
      .trim();

  final normalizedLower = normalized.toLowerCase();
  if (normalizedLower == 'owner' ||
      normalizedLower == 'gerente' ||
      normalizedLower == 'representante' ||
      normalizedLower == 'vendedor' ||
      normalizedLower == 'administrador' ||
      normalizedLower == 'admin') {
    return '';
  }

  return normalized;
}

String _nameFromEmail(String email) {
  final localPart = email.split('@').first.trim();
  if (localPart.isEmpty) {
    return email;
  }

  final normalized = localPart
      .replaceAll(RegExp(r'[._\-]+'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  if (normalized.isEmpty) {
    return localPart;
  }

  return normalized
      .split(' ')
      .where((token) => token.trim().isNotEmpty)
      .map(_capitalizeToken)
      .join(' ');
}

String _capitalizeToken(String token) {
  if (token.isEmpty) {
    return token;
  }
  final first = token.substring(0, 1).toUpperCase();
  if (token.length == 1) {
    return first;
  }
  return '$first${token.substring(1).toLowerCase()}';
}