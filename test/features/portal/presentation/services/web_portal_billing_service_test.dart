import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartsfa/src/features/portal/presentation/services/web_portal_billing_service.dart';

void main() {
  test('createCheckoutSession keeps Stripe flow without quote pre-step', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.url.path.endsWith('/createBillingCheckoutSession'), isTrue);
      return _jsonResponse(<String, Object?>{
        'checkoutUrl': 'https://checkout.example/1',
        'checkoutSessionId': 'sess_1',
        'stripeCustomerId': 'cus_1',
        'activeEnvironment': 'sandbox',
      });
    });

    final service = WebPortalBillingService(
      httpClient: client,
      idTokenProvider: () async => 'token_123',
    );

    final result = await service.createCheckoutSession(
      tenantId: ' tenant_1 ',
      billingPlanKey: ' plan_base ',
      successUrl: 'https://app.example/success',
      cancelUrl: 'https://app.example/cancel',
      addonSeats: -4,
      generateQuoteBeforeCheckout: false,
    );

    expect(result.checkoutSessionId, 'sess_1');
    expect(result.checkoutUrl, 'https://checkout.example/1');
    expect(result.stripeCustomerId, 'cus_1');
    expect(requests, hasLength(1));

    final requestBody =
        jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(requestBody['tenantId'], 'tenant_1');
    expect(requestBody['billingPlanKey'], 'plan_base');
    expect(requestBody['addonSeats'], 0);
    expect(requestBody.containsKey('quoteId'), isFalse);
    expect(requests.single.headers['authorization'], 'Bearer token_123');
  });

  test('createCheckoutSession sends quoteId when quote succeeds for Asaas', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);

      if (request.url.path.endsWith('/createBillingQuote')) {
        return _jsonResponse(<String, Object?>{'quoteId': 'quote_abc'});
      }

      if (request.url.path.endsWith('/createBillingCheckoutSession')) {
        return _jsonResponse(<String, Object?>{
          'checkoutUrl': 'https://checkout.example/2',
          'checkoutSessionId': 'sess_2',
          'activeEnvironment': 'production',
        });
      }

      fail('Unexpected URL ${request.url}');
    });

    final service = WebPortalBillingService(
      httpClient: client,
      idTokenProvider: () async => 'token_456',
    );

    final result = await service.createCheckoutSession(
      tenantId: 'tenant_2',
      billingPlanKey: 'plan_upgrade',
      successUrl: 'https://app.example/success',
      cancelUrl: 'https://app.example/cancel',
      addonSeats: 3,
      generateQuoteBeforeCheckout: true,
    );

    expect(result.checkoutSessionId, 'sess_2');
    expect(requests, hasLength(2));
    expect(requests[0].url.path.endsWith('/createBillingQuote'), isTrue);
    expect(
      requests[1].url.path.endsWith('/createBillingCheckoutSession'),
      isTrue,
    );

    final checkoutBody =
        jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(checkoutBody['quoteId'], 'quote_abc');
    expect(checkoutBody['addonSeats'], 3);
  });

  test(
    'createCheckoutSession falls back when provider quote is not supported',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);

        if (request.url.path.endsWith('/createBillingQuote')) {
          return _jsonResponse(
            <String, Object?>{
              'error': 'provider_quote_not_supported',
              'message': 'Provider sem quote',
            },
            statusCode: 409,
          );
        }

        if (request.url.path.endsWith('/createBillingCheckoutSession')) {
          return _jsonResponse(<String, Object?>{
            'checkoutUrl': 'https://checkout.example/3',
            'checkoutSessionId': 'sess_3',
          });
        }

        fail('Unexpected URL ${request.url}');
      });

      final service = WebPortalBillingService(
        httpClient: client,
        idTokenProvider: () async => 'token_789',
      );

      final result = await service.createCheckoutSession(
        tenantId: 'tenant_3',
        billingPlanKey: 'plan_plus',
        successUrl: 'https://app.example/success',
        cancelUrl: 'https://app.example/cancel',
        generateQuoteBeforeCheckout: true,
      );

      expect(result.checkoutSessionId, 'sess_3');
      expect(requests, hasLength(2));
      final checkoutBody =
          jsonDecode(requests[1].body) as Map<String, dynamic>;
      expect(checkoutBody.containsKey('quoteId'), isFalse);
    },
  );

  test('createCheckoutSession aborts when quote endpoint fails', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);

      if (request.url.path.endsWith('/createBillingQuote')) {
        return _jsonResponse(
          <String, Object?>{
            'error': 'internal_error',
            'message': 'Falha na geração de quote',
          },
          statusCode: 500,
        );
      }

      fail('Checkout call should not happen when quote fails');
    });

    final service = WebPortalBillingService(
      httpClient: client,
      idTokenProvider: () async => 'token_999',
    );

    await expectLater(
      service.createCheckoutSession(
        tenantId: 'tenant_4',
        billingPlanKey: 'plan_pro',
        successUrl: 'https://app.example/success',
        cancelUrl: 'https://app.example/cancel',
        generateQuoteBeforeCheckout: true,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Falha na geração de quote'),
        ),
      ),
    );

    expect(requests, hasLength(1));
    expect(requests.single.url.path.endsWith('/createBillingQuote'), isTrue);
  });
}

http.Response _jsonResponse(
  Map<String, Object?> payload, {
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(payload),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
