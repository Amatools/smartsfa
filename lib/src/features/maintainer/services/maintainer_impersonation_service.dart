import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class MaintainerImpersonationSession {
  const MaintainerImpersonationSession({
    required this.sessionId,
    required this.sessionKey,
    required this.launchUrl,
    required this.targetUid,
    required this.targetTenantId,
    required this.targetMembershipId,
    required this.adminRestoreCustomToken,
    required this.expiresAt,
  });

  final String sessionId;
  final String sessionKey;
  final String launchUrl;
  final String targetUid;
  final String targetTenantId;
  final String targetMembershipId;
  final String adminRestoreCustomToken;
  final DateTime? expiresAt;
}

class MaintainerImpersonationConsumeResult {
  const MaintainerImpersonationConsumeResult({
    required this.customToken,
    required this.targetUid,
    required this.targetTenantId,
    required this.targetMembershipId,
    required this.expiresAt,
  });

  final String customToken;
  final String targetUid;
  final String targetTenantId;
  final String targetMembershipId;
  final DateTime? expiresAt;
}

class MaintainerImpersonationService {
  MaintainerImpersonationService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  static _PendingAdminRestoreSession? _pendingAdminRestoreSession;

  static const String _defaultCreateSessionUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/createImpersonationSession';
  static const String _defaultConsumeSessionUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/consumeImpersonationSession';

  static const String _functionsBaseUrlOverride = String.fromEnvironment(
    'IMPERSONATION_FUNCTIONS_BASE_URL',
    defaultValue: '',
  );
  static const String _createSessionUrlOverride = String.fromEnvironment(
    'IMPERSONATION_CREATE_SESSION_URL',
    defaultValue: '',
  );
  static const String _consumeSessionUrlOverride = String.fromEnvironment(
    'IMPERSONATION_CONSUME_SESSION_URL',
    defaultValue: '',
  );

  static String get createSessionUrl => _resolveUrl(
    explicitOverride: _createSessionUrlOverride,
    functionName: 'createImpersonationSession',
    defaultUrl: _defaultCreateSessionUrl,
  );

  static String get consumeSessionUrl => _resolveUrl(
    explicitOverride: _consumeSessionUrlOverride,
    functionName: 'consumeImpersonationSession',
    defaultUrl: _defaultConsumeSessionUrl,
  );

  static String _resolveUrl({
    required String explicitOverride,
    required String functionName,
    required String defaultUrl,
  }) {
    final override = explicitOverride.trim();
    if (override.isNotEmpty) {
      return override;
    }

    final base = _functionsBaseUrlOverride.trim();
    if (base.isNotEmpty) {
      final normalizedBase = base.endsWith('/')
          ? base.substring(0, base.length - 1)
          : base;
      return '$normalizedBase/$functionName';
    }

    return defaultUrl;
  }

  static void cacheAdminRestoreSession({
    required String uid,
    required String customToken,
  }) {
    final normalizedUid = uid.trim();
    final normalizedToken = customToken.trim();
    if (normalizedUid.isEmpty || normalizedToken.isEmpty) {
      return;
    }

    _pendingAdminRestoreSession = _PendingAdminRestoreSession(
      uid: normalizedUid,
      customToken: normalizedToken,
      issuedAt: DateTime.now().toUtc(),
    );
  }

  static String takePendingAdminRestoreTokenIfNeeded({String? currentUid}) {
    final pending = _pendingAdminRestoreSession;
    if (pending == null) {
      return '';
    }

    final elapsed = DateTime.now().toUtc().difference(pending.issuedAt);
    if (elapsed > const Duration(minutes: 2)) {
      _pendingAdminRestoreSession = null;
      return '';
    }

    if ((currentUid ?? '').trim() == pending.uid) {
      return '';
    }

    _pendingAdminRestoreSession = null;
    return pending.customToken;
  }

  Future<MaintainerImpersonationSession> createSession({
    required String targetUid,
    required String targetTenantId,
    required String targetMembershipId,
    required String reason,
    required int durationMinutes,
    String launchOrigin = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if ((idToken ?? '').trim().isEmpty) {
      throw StateError('Sessao invalida. Faca login novamente.');
    }

    final body = jsonEncode(<String, Object?>{
      'targetUid': targetUid.trim(),
      'targetTenantId': targetTenantId.trim(),
      'targetMembershipId': targetMembershipId.trim(),
      'reason': reason.trim(),
      'durationMinutes': durationMinutes,
      if (launchOrigin.trim().isNotEmpty) 'launchOrigin': launchOrigin.trim(),
    });

    final response = await _httpClient
        .post(
          Uri.parse(createSessionUrl),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${idToken!.trim()}',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    final payload = _decodeMap(response.body);
    if (response.statusCode != 200) {
      final message = _readString(payload['message']);
      throw StateError(
        message.isEmpty
            ? 'Falha ao iniciar sessao assistida (${response.statusCode}).'
            : message,
      );
    }

    final sessionId = _readString(payload['sessionId']);
    final sessionKey = _readString(payload['sessionKey']);
    final launchUrl = _readString(payload['launchUrl']);
    if (sessionId.isEmpty || sessionKey.isEmpty || launchUrl.isEmpty) {
      throw StateError('Resposta invalida ao criar sessao assistida.');
    }

    return MaintainerImpersonationSession(
      sessionId: sessionId,
      sessionKey: sessionKey,
      launchUrl: launchUrl,
      targetUid: _readString(payload['targetUid']),
      targetTenantId: _readString(payload['targetTenantId']),
      targetMembershipId: _readString(payload['targetMembershipId']),
      adminRestoreCustomToken: _readString(payload['adminRestoreCustomToken']),
      expiresAt: _readDateTime(payload['expiresAt']),
    );
  }

  Future<MaintainerImpersonationConsumeResult> consumeSession({
    required String sessionId,
    required String sessionKey,
  }) async {
    final body = jsonEncode(<String, Object?>{
      'sessionId': sessionId.trim(),
      'sessionKey': sessionKey.trim(),
    });

    final response = await _httpClient
        .post(
          Uri.parse(consumeSessionUrl),
          headers: const <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    final payload = _decodeMap(response.body);
    if (response.statusCode != 200) {
      final message = _readString(payload['message']);
      throw StateError(
        message.isEmpty
            ? 'Falha ao consumir sessao assistida (${response.statusCode}).'
            : message,
      );
    }

    final customToken = _readString(payload['customToken']);
    if (customToken.isEmpty) {
      throw StateError('Resposta invalida ao consumir sessao assistida.');
    }

    return MaintainerImpersonationConsumeResult(
      customToken: customToken,
      targetUid: _readString(payload['targetUid']),
      targetTenantId: _readString(payload['targetTenantId']),
      targetMembershipId: _readString(payload['targetMembershipId']),
      expiresAt: _readDateTime(payload['expiresAt']),
    );
  }

  static Map<String, dynamic> _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      // Ignore parse errors and use empty payload.
    }
    return const <String, dynamic>{};
  }

  static String _readString(Object? value) {
    return (value ?? '').toString().trim();
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class _PendingAdminRestoreSession {
  const _PendingAdminRestoreSession({
    required this.uid,
    required this.customToken,
    required this.issuedAt,
  });

  final String uid;
  final String customToken;
  final DateTime issuedAt;
}
