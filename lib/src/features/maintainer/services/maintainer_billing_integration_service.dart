import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class MaintainerStripeCatalogPrice {
  const MaintainerStripeCatalogPrice({
    required this.priceId,
    required this.lookupKey,
    required this.nickname,
    required this.active,
    required this.currency,
    required this.type,
    required this.recurringInterval,
    required this.recurringIntervalCount,
    required this.unitAmount,
    required this.unitAmountDecimal,
    required this.taxBehavior,
  });

  final String priceId;
  final String lookupKey;
  final String nickname;
  final bool active;
  final String currency;
  final String type;
  final String recurringInterval;
  final int recurringIntervalCount;
  final int unitAmount;
  final String unitAmountDecimal;
  final String taxBehavior;

  factory MaintainerStripeCatalogPrice.fromMap(Map<String, dynamic> data) {
    return MaintainerStripeCatalogPrice(
      priceId: _readString(data['priceId']),
      lookupKey: _readString(data['lookupKey']),
      nickname: _readString(data['nickname']),
      active: data['active'] != false,
      currency: _readString(data['currency']),
      type: _readString(data['type']),
      recurringInterval: _readString(data['recurringInterval']),
      recurringIntervalCount: _readInt(data['recurringIntervalCount']) ?? 0,
      unitAmount: _readInt(data['unitAmount']) ?? 0,
      unitAmountDecimal: _readString(data['unitAmountDecimal']),
      taxBehavior: _readString(data['taxBehavior']),
    );
  }
}

class MaintainerStripeCatalogProduct {
  const MaintainerStripeCatalogProduct({
    required this.productId,
    required this.productName,
    required this.productDescription,
    required this.active,
    required this.defaultPriceId,
    required this.prices,
  });

  final String productId;
  final String productName;
  final String productDescription;
  final bool active;
  final String defaultPriceId;
  final List<MaintainerStripeCatalogPrice> prices;

  factory MaintainerStripeCatalogProduct.fromMap(Map<String, dynamic> data) {
    final rawPrices = data['prices'];
    final prices = rawPrices is List
        ? rawPrices
              .whereType<Map>()
              .map(
                (item) => MaintainerStripeCatalogPrice.fromMap(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList(growable: false)
        : const <MaintainerStripeCatalogPrice>[];

    return MaintainerStripeCatalogProduct(
      productId: _readString(data['productId']),
      productName: _readString(data['productName']),
      productDescription: _readString(data['productDescription']),
      active: data['active'] != false,
      defaultPriceId: _readString(data['defaultPriceId']),
      prices: prices,
    );
  }
}

class MaintainerStripeCatalogSnapshot {
  const MaintainerStripeCatalogSnapshot({
    required this.activeEnvironment,
    required this.stripeAccountId,
    required this.totalProducts,
    required this.hasMoreProducts,
    required this.products,
  });

  final String activeEnvironment;
  final String stripeAccountId;
  final int totalProducts;
  final bool hasMoreProducts;
  final List<MaintainerStripeCatalogProduct> products;

  factory MaintainerStripeCatalogSnapshot.fromMap(Map<String, dynamic> data) {
    final rawProducts = data['products'];
    final products = rawProducts is List
        ? rawProducts
              .whereType<Map>()
              .map(
                (item) => MaintainerStripeCatalogProduct.fromMap(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList(growable: false)
        : const <MaintainerStripeCatalogProduct>[];

    return MaintainerStripeCatalogSnapshot(
      activeEnvironment: _readString(data['activeEnvironment']),
      stripeAccountId: _readString(data['stripeAccountId']),
      totalProducts: _readInt(data['totalProducts']) ?? products.length,
      hasMoreProducts: data['hasMoreProducts'] == true,
      products: products,
    );
  }
}

class MaintainerStripeCreatedPlan {
  const MaintainerStripeCreatedPlan({
    required this.activeEnvironment,
    required this.stripeAccountId,
    required this.productId,
    required this.productName,
    required this.productDescription,
    required this.priceId,
    required this.priceNickname,
    required this.lookupKey,
    required this.currency,
    required this.unitAmount,
    required this.recurringInterval,
    required this.recurringIntervalCount,
    required this.billingPlanKey,
  });

  final String activeEnvironment;
  final String stripeAccountId;
  final String productId;
  final String productName;
  final String productDescription;
  final String priceId;
  final String priceNickname;
  final String lookupKey;
  final String currency;
  final int unitAmount;
  final String recurringInterval;
  final int recurringIntervalCount;
  final String billingPlanKey;

  factory MaintainerStripeCreatedPlan.fromMap(Map<String, dynamic> data) {
    return MaintainerStripeCreatedPlan(
      activeEnvironment: _readString(data['activeEnvironment']),
      stripeAccountId: _readString(data['stripeAccountId']),
      productId: _readString(data['productId']),
      productName: _readString(data['productName']),
      productDescription: _readString(data['productDescription']),
      priceId: _readString(data['priceId']),
      priceNickname: _readString(data['priceNickname']),
      lookupKey: _readString(data['lookupKey']),
      currency: _readString(data['currency']),
      unitAmount: _readInt(data['unitAmount']) ?? 0,
      recurringInterval: _readString(data['recurringInterval']),
      recurringIntervalCount: _readInt(data['recurringIntervalCount']) ?? 0,
      billingPlanKey: _readString(data['billingPlanKey']),
    );
  }
}

class MaintainerStripePlanMapping {
  const MaintainerStripePlanMapping({
    required this.mappingId,
    required this.billingPlanKey,
    required this.planDisplayName,
    required this.planDisplayAmount,
    required this.stripeProductId,
    required this.stripeProductName,
    required this.stripePriceId,
    required this.stripePriceNickname,
    required this.stripeUnitAmount,
    required this.stripeCurrency,
    required this.stripeRecurringInterval,
    required this.stripeRecurringIntervalCount,
    required this.mappingType,
    required this.overageMetric,
    required this.active,
    required this.updatedAt,
    required this.updatedBy,
  });

  final String mappingId;
  final String billingPlanKey;
  final String planDisplayName;
  final String planDisplayAmount;
  final String stripeProductId;
  final String stripeProductName;
  final String stripePriceId;
  final String stripePriceNickname;
  final int stripeUnitAmount;
  final String stripeCurrency;
  final String stripeRecurringInterval;
  final int stripeRecurringIntervalCount;
  final String mappingType;
  final String overageMetric;
  final bool active;
  final DateTime? updatedAt;
  final String updatedBy;

  factory MaintainerStripePlanMapping.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final explicitPlanName = _readString(data['planDisplayName']);
    final fallbackPlanName = _firstNonEmptyString(<String>[
      _readString(data['stripeProductName']),
      _readString(data['stripePriceNickname']),
      _readString(data['billingPlanKey']),
    ]);

    final explicitAmount = _readString(data['planDisplayAmount']);
    final fallbackAmount = _formatPlanAmountLabel(
      amountMinorUnits: _readInt(data['stripeUnitAmount']) ?? 0,
      currency: _readString(data['stripeCurrency']),
      recurringInterval: _readString(data['stripeRecurringInterval']),
      recurringIntervalCount:
          _readInt(data['stripeRecurringIntervalCount']) ?? 0,
    );

    return MaintainerStripePlanMapping(
      mappingId: doc.id,
      billingPlanKey: _readString(data['billingPlanKey']),
      planDisplayName: explicitPlanName.isEmpty
          ? fallbackPlanName
          : explicitPlanName,
      planDisplayAmount: explicitAmount.isEmpty
          ? fallbackAmount
          : explicitAmount,
      stripeProductId: _readString(data['stripeProductId']),
      stripeProductName: _readString(data['stripeProductName']),
      stripePriceId: _readString(data['stripePriceId']),
      stripePriceNickname: _readString(data['stripePriceNickname']),
      stripeUnitAmount: _readInt(data['stripeUnitAmount']) ?? 0,
      stripeCurrency: _readString(data['stripeCurrency']),
      stripeRecurringInterval: _readString(data['stripeRecurringInterval']),
      stripeRecurringIntervalCount:
          _readInt(data['stripeRecurringIntervalCount']) ?? 0,
      mappingType: _readString(data['mappingType'], fallback: 'base'),
      overageMetric: _readString(data['overageMetric']),
      active: data['active'] != false,
      updatedAt: _readDateTime(data['updatedAt']),
      updatedBy: _readString(data['updatedBy']),
    );
  }
}

class MaintainerStripeIntegrationConfig {
  const MaintainerStripeIntegrationConfig({
    required this.activeEnvironment,
    required this.accountIdTest,
    required this.accountIdLive,
    required this.webhookEndpointTest,
    required this.webhookEndpointLive,
    required this.webhookEvents,
    required this.updatedAt,
    required this.updatedBy,
  });

  final String activeEnvironment;
  final String accountIdTest;
  final String accountIdLive;
  final String webhookEndpointTest;
  final String webhookEndpointLive;
  final List<String> webhookEvents;
  final DateTime? updatedAt;
  final String updatedBy;

  bool get hasAnyAccountId =>
      accountIdTest.trim().isNotEmpty || accountIdLive.trim().isNotEmpty;

  static const MaintainerStripeIntegrationConfig empty =
      MaintainerStripeIntegrationConfig(
        activeEnvironment: 'test',
        accountIdTest: '',
        accountIdLive: '',
        webhookEndpointTest: '',
        webhookEndpointLive: '',
        webhookEvents: <String>[],
        updatedAt: null,
        updatedBy: '',
      );

  factory MaintainerStripeIntegrationConfig.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final environment = _readString(
      data['activeEnvironment'],
      fallback: 'test',
    ).toLowerCase();

    return MaintainerStripeIntegrationConfig(
      activeEnvironment: environment == 'live' ? 'live' : 'test',
      accountIdTest: _readString(data['accountIdTest']),
      accountIdLive: _readString(data['accountIdLive']),
      webhookEndpointTest: _readString(data['webhookEndpointTest']),
      webhookEndpointLive: _readString(data['webhookEndpointLive']),
      webhookEvents: _readStringList(data['webhookEvents']),
      updatedAt: _readDateTime(data['updatedAt']),
      updatedBy: _readString(data['updatedBy']),
    );
  }
}

class MaintainerBillingIntegrationService {
  MaintainerBillingIntegrationService(
    this._firestore, {
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final FirebaseFirestore _firestore;
  final http.Client _httpClient;

  static const String _defaultListStripeCatalogUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/listStripeCatalog';
  static const String _defaultCreateStripeCatalogPlanUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/createStripeCatalogPlan';
  static const String _defaultManageTenantBillingStateUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/manageTenantBillingState';
  static const String _functionsBaseUrlOverride = String.fromEnvironment(
    'STRIPE_BILLING_FUNCTIONS_BASE_URL',
    defaultValue: '',
  );
  static const String _listStripeCatalogUrlOverride = String.fromEnvironment(
    'STRIPE_LIST_CATALOG_URL',
    defaultValue: '',
  );
  static const String _createStripeCatalogPlanUrlOverride =
      String.fromEnvironment(
        'STRIPE_CREATE_CATALOG_PLAN_URL',
        defaultValue: '',
      );
  static const String _manageTenantBillingStateUrlOverride =
      String.fromEnvironment(
        'STRIPE_MANAGE_TENANT_BILLING_URL',
        defaultValue: '',
      );

  static String get listStripeCatalogUrl => _resolveUrl(
    explicitOverride: _listStripeCatalogUrlOverride,
    functionName: 'listStripeCatalog',
    defaultUrl: _defaultListStripeCatalogUrl,
  );

  static String get createStripeCatalogPlanUrl => _resolveUrl(
    explicitOverride: _createStripeCatalogPlanUrlOverride,
    functionName: 'createStripeCatalogPlan',
    defaultUrl: _defaultCreateStripeCatalogPlanUrl,
  );

  static String get manageTenantBillingStateUrl => _resolveUrl(
    explicitOverride: _manageTenantBillingStateUrlOverride,
    functionName: 'manageTenantBillingState',
    defaultUrl: _defaultManageTenantBillingStateUrl,
  );

  DocumentReference<Map<String, dynamic>> get _stripeConfigRef =>
      _firestore.collection('billing_integrations').doc('stripe');

  CollectionReference<Map<String, dynamic>> get _stripePlanMappingsRef =>
      _stripeConfigRef.collection('plan_mappings');

  Stream<MaintainerStripeIntegrationConfig> watchStripeConfig() {
    return _stripeConfigRef.snapshots().map((doc) {
      if (!doc.exists) {
        return MaintainerStripeIntegrationConfig.empty;
      }
      return MaintainerStripeIntegrationConfig.fromDoc(doc);
    });
  }

  Stream<List<MaintainerStripePlanMapping>> watchStripePlanMappings() {
    return _stripePlanMappingsRef.orderBy('billingPlanKey').snapshots().map((
      snapshot,
    ) {
      final mappings = snapshot.docs
          .map(MaintainerStripePlanMapping.fromDoc)
          .toList(growable: false);
      mappings.sort((a, b) {
        final planOrder = a.billingPlanKey.compareTo(b.billingPlanKey);
        if (planOrder != 0) {
          return planOrder;
        }
        return a.mappingId.compareTo(b.mappingId);
      });
      return mappings;
    });
  }

  Future<void> upsertStripeConfig({
    required String activeEnvironment,
    required String accountIdTest,
    required String accountIdLive,
    required String webhookEndpointTest,
    required String webhookEndpointLive,
    required List<String> webhookEvents,
    required String actorUid,
  }) async {
    final environment = activeEnvironment.trim().toLowerCase() == 'live'
        ? 'live'
        : 'test';

    await _stripeConfigRef.set({
      'activeEnvironment': environment,
      'accountIdTest': accountIdTest.trim(),
      'accountIdLive': accountIdLive.trim(),
      'webhookEndpointTest': webhookEndpointTest.trim(),
      'webhookEndpointLive': webhookEndpointLive.trim(),
      'webhookEvents': webhookEvents
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false),
      'updatedBy': actorUid.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> upsertPlanMapping({
    required String billingPlanKey,
    required String planDisplayName,
    required String planDisplayAmount,
    required String stripeProductId,
    required String stripeProductName,
    required String stripePriceId,
    required String stripePriceNickname,
    required int stripeUnitAmount,
    required String stripeCurrency,
    required String stripeRecurringInterval,
    required int stripeRecurringIntervalCount,
    required String mappingType,
    required String overageMetric,
    required bool active,
    required String actorUid,
  }) async {
    final normalizedPlanKey = billingPlanKey.trim().toLowerCase();
    if (normalizedPlanKey.isEmpty) {
      throw StateError('billingPlanKey e obrigatorio.');
    }

    final mappingId = normalizedPlanKey.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    await _stripePlanMappingsRef.doc(mappingId).set({
      'billingPlanKey': normalizedPlanKey,
      'planDisplayName': planDisplayName.trim(),
      'planDisplayAmount': planDisplayAmount.trim(),
      'stripeProductId': stripeProductId.trim(),
      'stripeProductName': stripeProductName.trim(),
      'stripePriceId': stripePriceId.trim(),
      'stripePriceNickname': stripePriceNickname.trim(),
      'stripeUnitAmount': stripeUnitAmount,
      'stripeCurrency': stripeCurrency.trim().toLowerCase(),
      'stripeRecurringInterval': stripeRecurringInterval.trim().toLowerCase(),
      'stripeRecurringIntervalCount': stripeRecurringIntervalCount,
      'mappingType': mappingType.trim().toLowerCase().isEmpty
          ? 'base'
          : mappingType.trim().toLowerCase(),
      'overageMetric': overageMetric.trim().toLowerCase(),
      'active': active,
      'updatedBy': actorUid.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<int> countTenantsUsingPlan({required String billingPlanKey}) async {
    final normalizedPlanKey = billingPlanKey.trim().toLowerCase();
    if (normalizedPlanKey.isEmpty) {
      return 0;
    }

    final query = _firestore
        .collection('tenants')
        .where('billingPlanKey', isEqualTo: normalizedPlanKey);

    try {
      final aggregate = await query.count().get();
      return aggregate.count ?? 0;
    } catch (_) {
      final snapshot = await query.limit(500).get();
      return snapshot.size;
    }
  }

  Future<void> setPlanMappingActive({
    required String mappingId,
    required bool active,
    required String actorUid,
  }) async {
    final normalizedMappingId = mappingId.trim();
    if (normalizedMappingId.isEmpty) {
      throw StateError('mappingId e obrigatorio.');
    }

    await _stripePlanMappingsRef.doc(normalizedMappingId).set({
      'active': active,
      'updatedBy': actorUid.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    await _stripeConfigRef.set({
      'updatedBy': actorUid.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> deletePlanMapping({
    required String mappingId,
    required String actorUid,
  }) async {
    final normalizedMappingId = mappingId.trim();
    if (normalizedMappingId.isEmpty) {
      throw StateError('mappingId e obrigatorio.');
    }

    final mappingRef = _stripePlanMappingsRef.doc(normalizedMappingId);
    final mappingDoc = await mappingRef.get();
    if (!mappingDoc.exists) {
      throw StateError('Mapeamento nao encontrado para exclusao.');
    }

    final mappingData = mappingDoc.data() ?? const <String, dynamic>{};
    final billingPlanKey = _readString(
      mappingData['billingPlanKey'],
      fallback: normalizedMappingId,
    );
    final tenantsUsingPlan = await countTenantsUsingPlan(
      billingPlanKey: billingPlanKey,
    );
    if (tenantsUsingPlan > 0) {
      throw StateError(
        'Plano em uso por $tenantsUsingPlan tenant(s). Oculte/desative o plano em vez de excluir.',
      );
    }

    await mappingRef.delete();

    await _stripeConfigRef.set({
      'updatedBy': actorUid.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<MaintainerStripeCatalogSnapshot> listStripeCatalog({
    bool activeOnly = true,
    int limitProducts = 30,
    int limitPricesPerProduct = 20,
  }) async {
    final idToken = await _requireIdToken();

    final response = await _httpClient
        .post(
          Uri.parse(listStripeCatalogUrl),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode(<String, Object?>{
            'activeOnly': activeOnly,
            'limitProducts': limitProducts,
            'limitPricesPerProduct': limitPricesPerProduct,
          }),
        )
        .timeout(const Duration(seconds: 45));

    final payload = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw StateError(
        _readErrorMessage(
          payload,
          fallback:
              'Falha ao consultar catalogo Stripe (HTTP ${response.statusCode}).',
        ),
      );
    }

    return MaintainerStripeCatalogSnapshot.fromMap(payload);
  }

  Future<MaintainerStripeCreatedPlan> createStripeCatalogPlan({
    required String productName,
    required String productDescription,
    required int amountMinorUnits,
    required String currency,
    required String recurringInterval,
    required int recurringIntervalCount,
    required String priceNickname,
    required String lookupKey,
    required String billingPlanKey,
    String taxBehavior = '',
    bool active = true,
  }) async {
    final idToken = await _requireIdToken();

    final response = await _httpClient
        .post(
          Uri.parse(createStripeCatalogPlanUrl),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode(<String, Object?>{
            'productName': productName.trim(),
            'productDescription': productDescription.trim(),
            'amountMinorUnits': amountMinorUnits,
            'currency': currency.trim().toLowerCase(),
            'recurringInterval': recurringInterval.trim().toLowerCase(),
            'recurringIntervalCount': recurringIntervalCount,
            'priceNickname': priceNickname.trim(),
            'lookupKey': lookupKey.trim(),
            'billingPlanKey': billingPlanKey.trim().toLowerCase(),
            'taxBehavior': taxBehavior.trim().toLowerCase(),
            'active': active,
          }),
        )
        .timeout(const Duration(seconds: 45));

    final payload = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw StateError(
        _readErrorMessage(
          payload,
          fallback:
              'Falha ao criar Product/Price no Stripe (HTTP ${response.statusCode}).',
        ),
      );
    }

    final created = MaintainerStripeCreatedPlan.fromMap(payload);
    if (created.productId.isEmpty || created.priceId.isEmpty) {
      throw StateError('Resposta invalida ao criar Product/Price no Stripe.');
    }
    return created;
  }

  Future<Map<String, dynamic>> manageTenantBillingState({
    required String tenantId,
    required String action,
    String reason = '',
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedAction = action.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('tenantId e obrigatorio.');
    }
    if (normalizedAction.isEmpty) {
      throw StateError('action e obrigatoria.');
    }

    final idToken = await _requireIdToken();

    final response = await _httpClient
        .post(
          Uri.parse(manageTenantBillingStateUrl),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode(<String, Object?>{
            'tenantId': normalizedTenantId,
            'action': normalizedAction,
            'reason': reason.trim(),
          }),
        )
        .timeout(const Duration(seconds: 60));

    final payload = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw StateError(
        _readErrorMessage(
          payload,
          fallback:
              'Falha ao executar acao de billing no tenant (HTTP ${response.statusCode}).',
        ),
      );
    }

    return payload;
  }

  Future<String> _requireIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    final normalized = (idToken ?? '').trim();
    if (normalized.isEmpty) {
      throw StateError('Sessao invalida. Faca login novamente.');
    }
    return normalized;
  }

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
      // ignore parse errors
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
}

String _readString(Object? raw, {String fallback = ''}) {
  final value = (raw ?? '').toString().trim();
  return value.isEmpty ? fallback : value;
}

String _firstNonEmptyString(List<String> values) {
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return '';
}

List<String> _readStringList(Object? raw) {
  if (raw is! Iterable) {
    return const <String>[];
  }
  final values =
      raw
          .map((item) => (item ?? '').toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
  return values;
}

DateTime? _readDateTime(Object? raw) {
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

int? _readInt(Object? raw) {
  if (raw == null) {
    return null;
  }
  if (raw is int) {
    return raw;
  }
  return int.tryParse(raw.toString().trim());
}

String _formatPlanAmountLabel({
  required int amountMinorUnits,
  required String currency,
  required String recurringInterval,
  required int recurringIntervalCount,
}) {
  if (amountMinorUnits <= 0) {
    return '';
  }

  final amount = amountMinorUnits / 100;
  final normalizedCurrency = currency.trim().toLowerCase();
  final currencyLabel = normalizedCurrency == 'brl'
      ? 'R\$'
      : normalizedCurrency.isEmpty
      ? ''
      : normalizedCurrency.toUpperCase();

  var recurringLabel = '';
  final interval = recurringInterval.trim().toLowerCase();
  if (interval.isNotEmpty) {
    final count = recurringIntervalCount <= 0 ? 1 : recurringIntervalCount;
    recurringLabel = ' / $interval x$count';
  }

  if (currencyLabel.isEmpty) {
    return '${amount.toStringAsFixed(2)}$recurringLabel';
  }
  return '$currencyLabel ${amount.toStringAsFixed(2)}$recurringLabel';
}
