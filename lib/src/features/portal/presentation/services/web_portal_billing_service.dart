import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

String _readPortalString(Object? raw) {
  return (raw ?? '').toString().trim();
}

class WebPortalCheckoutSessionResult {
  const WebPortalCheckoutSessionResult({
    required this.checkoutUrl,
    required this.checkoutSessionId,
    required this.stripeCustomerId,
    required this.activeEnvironment,
  });

  final String checkoutUrl;
  final String checkoutSessionId;
  final String stripeCustomerId;
  final String activeEnvironment;
}

class WebPortalPortalSessionResult {
  const WebPortalPortalSessionResult({
    required this.portalUrl,
    required this.activeEnvironment,
  });

  final String portalUrl;
  final String activeEnvironment;
}

class WebPortalAvailableBillingPlan {
  const WebPortalAvailableBillingPlan({
    required this.mappingId,
    required this.billingPlanKey,
    required this.planDisplayName,
    required this.planDisplayAmount,
    required this.stripePriceId,
    required this.stripeProductId,
    required this.stripeProductName,
  });

  final String mappingId;
  final String billingPlanKey;
  final String planDisplayName;
  final String planDisplayAmount;
  final String stripePriceId;
  final String stripeProductId;
  final String stripeProductName;

  factory WebPortalAvailableBillingPlan.fromMap(Map<String, dynamic> data) {
    return WebPortalAvailableBillingPlan(
      mappingId: _readPortalString(data['mappingId']),
      billingPlanKey: _readPortalString(data['billingPlanKey']),
      planDisplayName: _readPortalString(data['planDisplayName']),
      planDisplayAmount: _readPortalString(data['planDisplayAmount']),
      stripePriceId: _readPortalString(data['stripePriceId']),
      stripeProductId: _readPortalString(data['stripeProductId']),
      stripeProductName: _readPortalString(data['stripeProductName']),
    );
  }
}

class WebPortalBillingService {
  WebPortalBillingService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const String _defaultCreateCheckoutSessionUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/createStripeCheckoutSession';
  static const String _defaultCreatePortalSessionUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/createStripePortalSession';
    static const String _defaultListCheckoutPlansUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/listStripeCheckoutPlans';

  static const String _functionsBaseUrlOverride = String.fromEnvironment(
    'STRIPE_BILLING_FUNCTIONS_BASE_URL',
    defaultValue: '',
  );

  static const String _createCheckoutSessionUrlOverride =
      String.fromEnvironment(
        'STRIPE_CHECKOUT_SESSION_URL',
        defaultValue: '',
      );

  static const String _createPortalSessionUrlOverride = String.fromEnvironment(
    'STRIPE_PORTAL_SESSION_URL',
    defaultValue: '',
  );
  static const String _listCheckoutPlansUrlOverride = String.fromEnvironment(
    'STRIPE_CHECKOUT_PLANS_URL',
    defaultValue: '',
  );

  static String get createCheckoutSessionUrl => _resolveUrl(
    explicitOverride: _createCheckoutSessionUrlOverride,
    functionName: 'createStripeCheckoutSession',
    defaultUrl: _defaultCreateCheckoutSessionUrl,
  );

  static String get createPortalSessionUrl => _resolveUrl(
    explicitOverride: _createPortalSessionUrlOverride,
    functionName: 'createStripePortalSession',
    defaultUrl: _defaultCreatePortalSessionUrl,
  );

  static String get listCheckoutPlansUrl => _resolveUrl(
    explicitOverride: _listCheckoutPlansUrlOverride,
    functionName: 'listStripeCheckoutPlans',
    defaultUrl: _defaultListCheckoutPlansUrl,
  );

  static String _resolveUrl({
    required String explicitOverride,
    required String functionName,
    required String defaultUrl,
  }) {
    final direct = explicitOverride.trim();
    if (direct.isNotEmpty) {
      return direct;
    }

    final base = _functionsBaseUrlOverride.trim();
    if (base.isEmpty) {
      return defaultUrl;
    }

    final normalizedBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$normalizedBase/$functionName';
  }

  Future<WebPortalCheckoutSessionResult> createCheckoutSession({
    required String tenantId,
    required String billingPlanKey,
    required String successUrl,
    required String cancelUrl,
  }) async {
    final idToken = await _requireIdToken();

    final response = await _httpClient
        .post(
          Uri.parse(createCheckoutSessionUrl),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode(<String, Object?>{
            'tenantId': tenantId.trim(),
            'billingPlanKey': billingPlanKey.trim(),
            'successUrl': successUrl.trim(),
            'cancelUrl': cancelUrl.trim(),
          }),
        )
        .timeout(const Duration(seconds: 40));

    final payload = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw StateError(_readErrorMessage(
        payload,
        fallback:
            'Falha ao iniciar checkout Stripe (HTTP ${response.statusCode}).',
      ));
    }

    final checkoutUrl = _readString(payload['checkoutUrl']);
    final checkoutSessionId = _readString(payload['checkoutSessionId']);
    if (checkoutUrl.isEmpty || checkoutSessionId.isEmpty) {
      throw StateError('Resposta inválida ao criar sessão de checkout.');
    }

    return WebPortalCheckoutSessionResult(
      checkoutUrl: checkoutUrl,
      checkoutSessionId: checkoutSessionId,
      stripeCustomerId: _readString(payload['stripeCustomerId']),
      activeEnvironment: _readString(payload['activeEnvironment']),
    );
  }

  Future<WebPortalPortalSessionResult> createPortalSession({
    required String tenantId,
    required String returnUrl,
  }) async {
    final idToken = await _requireIdToken();

    final response = await _httpClient
        .post(
          Uri.parse(createPortalSessionUrl),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode(<String, Object?>{
            'tenantId': tenantId.trim(),
            'returnUrl': returnUrl.trim(),
          }),
        )
        .timeout(const Duration(seconds: 30));

    final payload = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw StateError(_readErrorMessage(
        payload,
        fallback:
            'Falha ao abrir portal de cobrança Stripe (HTTP ${response.statusCode}).',
      ));
    }

    final portalUrl = _readString(payload['portalUrl']);
    if (portalUrl.isEmpty) {
      throw StateError('Resposta inválida ao criar sessão do portal Stripe.');
    }

    return WebPortalPortalSessionResult(
      portalUrl: portalUrl,
      activeEnvironment: _readString(payload['activeEnvironment']),
    );
  }

  Future<List<WebPortalAvailableBillingPlan>> listAvailableCheckoutPlans({
    required String tenantId,
  }) async {
    final idToken = await _requireIdToken();

    final response = await _httpClient
        .post(
          Uri.parse(listCheckoutPlansUrl),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode(<String, Object?>{'tenantId': tenantId.trim()}),
        )
        .timeout(const Duration(seconds: 30));

    final payload = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw StateError(_readErrorMessage(
        payload,
        fallback:
            'Falha ao listar planos disponíveis de checkout (HTTP ${response.statusCode}).',
      ));
    }

    final rawPlans = payload['plans'];
    if (rawPlans is! List) {
      return const <WebPortalAvailableBillingPlan>[];
    }

    return rawPlans
        .whereType<Map>()
        .map(
          (item) => WebPortalAvailableBillingPlan.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((plan) => plan.billingPlanKey.isNotEmpty)
        .toList(growable: false);
  }

  Future<String> _requireIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    final normalized = (idToken ?? '').trim();
    if (normalized.isEmpty) {
      throw StateError('Sessão inválida. Faça login novamente.');
    }
    return normalized;
  }

  static Map<String, dynamic> _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      // Ignore parse error and return empty map.
    }
    return const <String, dynamic>{};
  }

  static String _readErrorMessage(
    Map<String, dynamic> payload, {
    required String fallback,
  }) {
    final message = _readString(payload['message']);
    if (message.isNotEmpty) {
      return message;
    }

    final error = _readString(payload['error']);
    if (error.isNotEmpty) {
      return '$fallback [$error]';
    }

    return fallback;
  }

  static String _readString(Object? raw) {
    return (raw ?? '').toString().trim();
  }
}
