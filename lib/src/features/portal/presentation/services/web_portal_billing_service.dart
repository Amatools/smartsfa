import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

String _readPortalString(Object? raw) {
  return (raw ?? '').toString().trim();
}

int _readPortalNonNegativeInt(Object? raw, {int fallback = 0}) {
  if (raw is int) {
    return raw < 0 ? 0 : raw;
  }
  if (raw is num) {
    final parsed = raw.toInt();
    return parsed < 0 ? 0 : parsed;
  }
  if (raw is String) {
    final parsed = int.tryParse(raw.trim());
    if (parsed != null) {
      return parsed < 0 ? 0 : parsed;
    }
  }
  return fallback < 0 ? 0 : fallback;
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

class WebPortalBillingSelfServiceResult {
  const WebPortalBillingSelfServiceResult({
    required this.billingProvider,
    required this.requestedAction,
    required this.providerAction,
    required this.message,
  });

  final String billingProvider;
  final String requestedAction;
  final String providerAction;
  final String message;
}

class WebPortalSeatAddonUpdateResult {
  const WebPortalSeatAddonUpdateResult({
    required this.billingProvider,
    required this.billingPlanKey,
    required this.addedSeats,
    required this.previousAddonSeats,
    required this.currentAddonSeats,
    required this.message,
    required this.invoiceUrl,
  });

  final String billingProvider;
  final String billingPlanKey;
  final int addedSeats;
  final int previousAddonSeats;
  final int currentAddonSeats;
  final String message;
  final String invoiceUrl;
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
    required this.includedSeats,
    required this.seatAddonPlanKey,
    required this.seatAddonUnitPriceCents,
    required this.seatAddonDisplayAmount,
  });

  final String mappingId;
  final String billingPlanKey;
  final String planDisplayName;
  final String planDisplayAmount;
  final String stripePriceId;
  final String stripeProductId;
  final String stripeProductName;
  final int includedSeats;
  final String seatAddonPlanKey;
  final int seatAddonUnitPriceCents;
  final String seatAddonDisplayAmount;

  factory WebPortalAvailableBillingPlan.fromMap(Map<String, dynamic> data) {
    return WebPortalAvailableBillingPlan(
      mappingId: _readPortalString(data['mappingId']),
      billingPlanKey: _readPortalString(data['billingPlanKey']),
      planDisplayName: _readPortalString(data['planDisplayName']),
      planDisplayAmount: _readPortalString(data['planDisplayAmount']),
      stripePriceId: _readPortalString(data['stripePriceId']),
      stripeProductId: _readPortalString(data['stripeProductId']),
      stripeProductName: _readPortalString(data['stripeProductName']),
      includedSeats: _readPortalNonNegativeInt(data['includedSeats']),
      seatAddonPlanKey: _readPortalString(data['seatAddonPlanKey']),
      seatAddonUnitPriceCents: _readPortalNonNegativeInt(
        data['seatAddonUnitPriceCents'],
      ),
      seatAddonDisplayAmount: _readPortalString(data['seatAddonDisplayAmount']),
    );
  }
}

class WebPortalBillingService {
  WebPortalBillingService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const String _defaultCreateCheckoutSessionUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/createBillingCheckoutSession';
  static const String _defaultCreatePortalSessionUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/createBillingPortalSession';
  static const String _defaultListCheckoutPlansUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/listBillingCheckoutPlans';
  static const String _defaultManageBillingSelfServiceUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/manageTenantBillingSelfService';
  static const String _defaultUpdateBillingSeatAddonsUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/updateBillingSeatAddons';

  static const String _billingFunctionsBaseUrlOverride = String.fromEnvironment(
    'BILLING_FUNCTIONS_BASE_URL',
    defaultValue: '',
  );

  static const String _functionsBaseUrlOverride = String.fromEnvironment(
    'STRIPE_BILLING_FUNCTIONS_BASE_URL',
    defaultValue: '',
  );

  static const String _billingCreateCheckoutSessionUrlOverride =
      String.fromEnvironment('BILLING_CHECKOUT_SESSION_URL', defaultValue: '');

  static const String _createCheckoutSessionUrlOverride =
      String.fromEnvironment('STRIPE_CHECKOUT_SESSION_URL', defaultValue: '');

  static const String _billingCreatePortalSessionUrlOverride =
      String.fromEnvironment('BILLING_PORTAL_SESSION_URL', defaultValue: '');

  static const String _createPortalSessionUrlOverride = String.fromEnvironment(
    'STRIPE_PORTAL_SESSION_URL',
    defaultValue: '',
  );

  static const String _billingListCheckoutPlansUrlOverride =
      String.fromEnvironment('BILLING_CHECKOUT_PLANS_URL', defaultValue: '');

  static const String _billingManageSelfServiceUrlOverride =
      String.fromEnvironment('BILLING_MANAGE_SELF_SERVICE_URL', defaultValue: '');

  static const String _billingUpdateSeatAddonsUrlOverride =
      String.fromEnvironment('BILLING_UPDATE_SEAT_ADDONS_URL', defaultValue: '');

  static const String _listCheckoutPlansUrlOverride = String.fromEnvironment(
    'STRIPE_CHECKOUT_PLANS_URL',
    defaultValue: '',
  );

  static String _firstNonEmpty(String first, String second) {
    final normalizedFirst = first.trim();
    if (normalizedFirst.isNotEmpty) {
      return normalizedFirst;
    }
    return second.trim();
  }

  static String get createCheckoutSessionUrl => _resolveUrl(
    explicitOverride: _firstNonEmpty(
      _billingCreateCheckoutSessionUrlOverride,
      _createCheckoutSessionUrlOverride,
    ),
    functionName: 'createBillingCheckoutSession',
    defaultUrl: _defaultCreateCheckoutSessionUrl,
  );

  static String get createPortalSessionUrl => _resolveUrl(
    explicitOverride: _firstNonEmpty(
      _billingCreatePortalSessionUrlOverride,
      _createPortalSessionUrlOverride,
    ),
    functionName: 'createBillingPortalSession',
    defaultUrl: _defaultCreatePortalSessionUrl,
  );

  static String get listCheckoutPlansUrl => _resolveUrl(
    explicitOverride: _firstNonEmpty(
      _billingListCheckoutPlansUrlOverride,
      _listCheckoutPlansUrlOverride,
    ),
    functionName: 'listBillingCheckoutPlans',
    defaultUrl: _defaultListCheckoutPlansUrl,
  );

  static String get manageBillingSelfServiceUrl => _resolveUrl(
    explicitOverride: _billingManageSelfServiceUrlOverride,
    functionName: 'manageTenantBillingSelfService',
    defaultUrl: _defaultManageBillingSelfServiceUrl,
  );

  static String get updateBillingSeatAddonsUrl => _resolveUrl(
    explicitOverride: _billingUpdateSeatAddonsUrlOverride,
    functionName: 'updateBillingSeatAddons',
    defaultUrl: _defaultUpdateBillingSeatAddonsUrl,
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

    final base = _firstNonEmpty(
      _billingFunctionsBaseUrlOverride,
      _functionsBaseUrlOverride,
    );
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
    int addonSeats = 0,
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
            'addonSeats': addonSeats < 0 ? 0 : addonSeats,
          }),
        )
        .timeout(const Duration(seconds: 40));

    final payload = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw StateError(
        _readErrorMessage(
          payload,
          fallback:
              'Falha ao iniciar checkout de billing (HTTP ${response.statusCode}).',
        ),
      );
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
      throw StateError(
        _readErrorMessage(
          payload,
          fallback:
              'Falha ao abrir portal de cobranca (HTTP ${response.statusCode}).',
        ),
      );
    }

    final portalUrl = _readString(payload['portalUrl']);
    if (portalUrl.isEmpty) {
      throw StateError('Resposta invalida ao criar sessao de portal.');
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
      throw StateError(
        _readErrorMessage(
          payload,
          fallback:
              'Falha ao listar planos disponíveis de checkout (HTTP ${response.statusCode}).',
        ),
      );
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

  Future<WebPortalBillingSelfServiceResult> manageBillingSelfService({
    required String tenantId,
    required String action,
    String reason = '',
  }) async {
    final idToken = await _requireIdToken();

    final response = await _httpClient
        .post(
          Uri.parse(manageBillingSelfServiceUrl),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode(<String, Object?>{
            'tenantId': tenantId.trim(),
            'action': action.trim(),
            if (reason.trim().isNotEmpty) 'reason': reason.trim(),
          }),
        )
        .timeout(const Duration(seconds: 35));

    final payload = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw StateError(
        _readErrorMessage(
          payload,
          fallback:
              'Falha ao atualizar assinatura/plano (HTTP ${response.statusCode}).',
        ),
      );
    }

    return WebPortalBillingSelfServiceResult(
      billingProvider: _readString(payload['billingProvider']),
      requestedAction: _readString(payload['requestedAction']),
      providerAction: _readString(payload['providerAction']),
      message:
          _readString(payload['message']).isNotEmpty
          ? _readString(payload['message'])
          : 'Ação de billing executada com sucesso.',
    );
  }

  Future<WebPortalSeatAddonUpdateResult> updateSeatAddons({
    required String tenantId,
    required String billingPlanKey,
    required int addonSeatsDelta,
  }) async {
    final idToken = await _requireIdToken();

    final response = await _httpClient
        .post(
          Uri.parse(updateBillingSeatAddonsUrl),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode(<String, Object?>{
            'tenantId': tenantId.trim(),
            'billingPlanKey': billingPlanKey.trim(),
            'addonSeatsDelta': addonSeatsDelta < 0 ? 0 : addonSeatsDelta,
          }),
        )
        .timeout(const Duration(seconds: 40));

    final payload = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw StateError(
        _readErrorMessage(
          payload,
          fallback:
              'Falha ao atualizar seats extras (HTTP ${response.statusCode}).',
        ),
      );
    }

    return WebPortalSeatAddonUpdateResult(
      billingProvider: _readString(payload['billingProvider']),
      billingPlanKey: _readString(payload['billingPlanKey']),
      addedSeats: _readPortalNonNegativeInt(payload['addedSeats']),
      previousAddonSeats: _readPortalNonNegativeInt(
        payload['previousAddonSeats'],
      ),
      currentAddonSeats: _readPortalNonNegativeInt(payload['currentAddonSeats']),
      message:
          _readString(payload['message']).isNotEmpty
          ? _readString(payload['message'])
          : 'Seats extras atualizados com sucesso.',
      invoiceUrl: _readString(payload['invoiceUrl']),
    );
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
