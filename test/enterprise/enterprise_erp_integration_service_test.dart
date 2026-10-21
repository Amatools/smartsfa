import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartsfa/src/features/enterprise/erp_integration/services/enterprise_erp_integration_service.dart';

void main() {
  test(
    'uses the authentication proxy with the production request contract',
    () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode(<String, Object>{
            'access_token': 'received-bearer-token',
            'token_type': 'Bearer',
            'expires_in': 300,
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final service = EnterpriseErpIntegrationService(
        FakeFirebaseFirestore(),
        httpClient: client,
      );

      final result = await service.testConnection(
        apiBaseUrl: 'https://amatools.sankhyacloud.com.br',
        environment: 'prod',
        username: 'client-id',
        password: 'client-secret',
        accessToken: 'x-token-value',
      );

      expect(
        capturedRequest.url.toString(),
        EnterpriseErpIntegrationService.authenticationProxyUrl,
      );
      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.headers['content-type'], 'application/json');
      expect(jsonDecode(capturedRequest.body), <String, dynamic>{
        'environment': 'prod',
        'clientId': 'client-id',
        'clientSecret': 'client-secret',
        'xToken': 'x-token-value',
      });
      expect(result.success, isTrue);
      expect(result.bearerReceived, isTrue);
      expect(result.expiresInSeconds, 300);
    },
  );

  test('sends homologation environment to the authentication proxy', () async {
    late Map<String, dynamic> capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        'access_token=received-token&token_type=Bearer&expires_in=300',
        200,
      );
    });
    final service = EnterpriseErpIntegrationService(
      FakeFirebaseFirestore(),
      httpClient: client,
    );

    final result = await service.testConnection(
      apiBaseUrl: '',
      environment: 'homolog',
      username: 'client-id',
      password: 'client-secret',
      accessToken: 'x-token-value',
    );

    expect(capturedBody['environment'], 'homolog');
    expect(result.success, isTrue);
  });

  test('syncs products module via catalog sync proxy contract', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        jsonEncode(<String, Object>{
          'success': true,
          'message': 'Sincronizacao concluida.',
          'importedCount': 5,
          'filteredOutZeroCodeCount': 1,
          'sourceCount': 50,
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final service = EnterpriseErpIntegrationService(
      FakeFirebaseFirestore(),
      httpClient: client,
    );
    final module = EnterpriseErpIntegrationService.supportedSyncModules.first;

    final result = await service.syncCatalogModule(
      tenantId: 'tenant_demo',
      module: module,
      environment: 'prod',
      username: 'client-id',
      password: 'client-secret',
      accessToken: 'x-token-value',
    );

    expect(
      capturedRequest.url.toString(),
      EnterpriseErpIntegrationService.syncCatalogModuleProxyUrl,
    );
    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.headers['content-type'], 'application/json');
    expect(jsonDecode(capturedRequest.body), <String, dynamic>{
      'tenantId': 'tenant_demo',
      'module': 'produtos',
      'environment': 'prod',
      'clientId': 'client-id',
      'clientSecret': 'client-secret',
      'xToken': 'x-token-value',
    });
    expect(result.success, isTrue);
    expect(result.importedCount, 5);
    expect(result.filteredOutZeroCodeCount, 1);
    expect(result.sourceCount, 50);
  });
}
