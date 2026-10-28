import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:smartsfa/src/core/models/domain_types.dart';
import 'package:smartsfa/src/features/auth/services/workspace_profile_service.dart';

import '../domain/models/enterprise_erp_connection_test_result.dart';
import '../domain/models/enterprise_erp_connector_option.dart';
import '../domain/models/enterprise_erp_integration_data.dart';

class EnterpriseErpSyncModuleOption {
  const EnterpriseErpSyncModuleOption({
    required this.id,
    required this.label,
    required this.description,
    required this.endpointPath,
    required this.enabled,
  });

  final String id;
  final String label;
  final String description;
  final String endpointPath;
  final bool enabled;
}

class EnterpriseErpModuleSyncResult {
  const EnterpriseErpModuleSyncResult({
    required this.success,
    required this.moduleId,
    required this.message,
    required this.statusCode,
    required this.requestUrl,
    required this.importedCount,
    required this.filteredOutZeroCodeCount,
    required this.skippedNotFoundCount,
    required this.sourceCount,
  });

  final bool success;
  final String moduleId;
  final String message;
  final int? statusCode;
  final String requestUrl;
  final int importedCount;
  final int filteredOutZeroCodeCount;
  final int skippedNotFoundCount;
  final int sourceCount;
}

class EnterpriseErpOperationType {
  const EnterpriseErpOperationType({
    required this.code,
    required this.description,
    required this.movementType,
  });

  final String code;
  final String description;
  final String movementType;

  String get displayLabel =>
      description.isEmpty ? code : '$code - $description';
}

class EnterpriseErpIntegrationService {
  EnterpriseErpIntegrationService(
    FirebaseFirestore firestore, {
    http.Client? httpClient,
  }) : _workspaceProfileService = WorkspaceProfileService(firestore),
       _httpClient = httpClient ?? http.Client();

  final WorkspaceProfileService _workspaceProfileService;
  final http.Client _httpClient;

  static const String productionApiBaseUrl = 'https://api.sankhya.com.br';
  static const String sandboxApiBaseUrl = 'https://api.sandbox.sankhya.com.br';
  static const String _defaultAuthenticationProxyUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/testSankhyaAuthentication';
  static const String _defaultSyncCatalogModuleProxyUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/syncSankhyaCatalogModule';
  static const String _defaultFetchOperationTypesProxyUrl =
      'https://us-central1-smart-sfa.cloudfunctions.net/fetchSankhyaOperationTypes';
  static const String _functionsBaseUrlOverride = String.fromEnvironment(
    'SANKHYA_FUNCTIONS_BASE_URL',
    defaultValue: '',
  );
  static const String _authenticationProxyUrlOverride = String.fromEnvironment(
    'SANKHYA_AUTH_PROXY_URL',
    defaultValue: '',
  );
  static const String _syncCatalogModuleProxyUrlOverride = String.fromEnvironment(
    'SANKHYA_SYNC_PROXY_URL',
    defaultValue: '',
  );
  static const String _fetchOperationTypesProxyUrlOverride = String.fromEnvironment(
    'SANKHYA_OPERATION_TYPES_PROXY_URL',
    defaultValue: '',
  );
  static const int temporaryModuleImportLimit = 5;

  static String get authenticationProxyUrl => _resolveProxyUrl(
    explicitOverride: _authenticationProxyUrlOverride,
    functionName: 'testSankhyaAuthentication',
    defaultUrl: _defaultAuthenticationProxyUrl,
  );

  static String get syncCatalogModuleProxyUrl => _resolveProxyUrl(
    explicitOverride: _syncCatalogModuleProxyUrlOverride,
    functionName: 'syncSankhyaCatalogModule',
    defaultUrl: _defaultSyncCatalogModuleProxyUrl,
  );

  static String get fetchOperationTypesProxyUrl => _resolveProxyUrl(
    explicitOverride: _fetchOperationTypesProxyUrlOverride,
    functionName: 'fetchSankhyaOperationTypes',
    defaultUrl: _defaultFetchOperationTypesProxyUrl,
  );

  static const List<EnterpriseErpSyncModuleOption> supportedSyncModules = [
    EnterpriseErpSyncModuleOption(
      id: 'produtos',
      label: 'Produtos',
      description: 'Sincroniza o catalogo de produtos ERP para o SaaS.',
      endpointPath: '/v1/produtos?page=0',
      enabled: true,
    ),
    EnterpriseErpSyncModuleOption(
      id: 'tax_rules',
      label: 'Regras fiscais (tributacao)',
      description:
          'Sincroniza regras fiscais completas via DbExplorer SQL para alimentar o motor tributario local.',
      endpointPath:
          '/gateway/v1/mge/service.sbr?serviceName=DbExplorerSP.executeQuery',
      enabled: true,
    ),
    EnterpriseErpSyncModuleOption(
      id: 'parceiros',
      label: 'Parceiros (clientes)',
      description:
          'Aguardando validacao final de endpoint/permissao no Gateway Sankhya.',
      endpointPath: '/v1/parceiros?page=0',
      enabled: false,
    ),
    EnterpriseErpSyncModuleOption(
      id: 'tabelas_preco',
      label: 'Tabelas de preco',
      description:
          'Sincroniza precos por codigos de tabela configurados no card de sincronizacao.',
      endpointPath: '/v1/precos/tabela/{codigoTabela}?pagina=1',
      enabled: true,
    ),
  ];

  static String sankhyaBaseUrlForEnvironment(String environment) {
    return environment.trim().toLowerCase() == 'prod'
        ? productionApiBaseUrl
        : sandboxApiBaseUrl;
  }

  static const List<EnterpriseErpConnectorOption> supportedConnectors = [
    EnterpriseErpConnectorOption(
      id: 'sankhya',
      provider: 'sankhya',
      name: 'Sankhya',
      subtitle: 'Conector oficial do piloto enterprise.',
      logoLabel: 'SK',
      enabled: true,
    ),
    EnterpriseErpConnectorOption(
      id: 'omie',
      provider: 'custom',
      name: 'Omie',
      subtitle: 'Conector planejado para proxima fase.',
      logoLabel: 'OM',
      enabled: false,
    ),
    EnterpriseErpConnectorOption(
      id: 'bling',
      provider: 'custom',
      name: 'Bling',
      subtitle: 'Conector planejado para proxima fase.',
      logoLabel: 'BL',
      enabled: false,
    ),
  ];

  Stream<EnterpriseErpIntegrationData> watchIntegration(String tenantId) {
    return _workspaceProfileService.watchWorkspace(tenantId).map((workspace) {
      return _resolveIntegrationData(workspace ?? const <String, dynamic>{});
    });
  }

  EnterpriseErpConnectorOption? resolveConnectorById(String connectorId) {
    final normalizedId = connectorId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }
    for (final item in supportedConnectors) {
      if (item.id == normalizedId) {
        return item;
      }
    }
    return null;
  }

  Future<void> activateConnector({
    required String tenantId,
    required EnterpriseErpConnectorOption connector,
  }) {
    return _workspaceProfileService.setTenantErpSelectedCompany(
      tenantId: tenantId,
      provider: connector.provider,
      companyId: connector.id,
      companyName: connector.name,
    );
  }

  Future<void> saveCredentials({
    required String tenantId,
    required String provider,
    required String environment,
    required String apiBaseUrl,
    required String username,
    required String password,
    required String accessToken,
    required List<String> priceTableCodes,
  }) {
    return _workspaceProfileService.setTenantErpCredentials(
      tenantId: tenantId,
      provider: provider,
      environment: environment,
      apiBaseUrl: apiBaseUrl,
      username: username,
      password: password,
      accessToken: accessToken,
      priceTableCodes: _normalizePriceTableCodes(priceTableCodes),
    );
  }

  Future<void> savePriceTableCodes({
    required String tenantId,
    required List<String> priceTableCodes,
  }) {
    return _workspaceProfileService.setTenantErpPriceTableCodes(
      tenantId: tenantId,
      priceTableCodes: _normalizePriceTableCodes(priceTableCodes),
    );
  }

  Future<void> saveOrderTopCodes({
    required String tenantId,
    required EnterpriseErpOrderTopCodes orderTopCodes,
  }) {
    return _workspaceProfileService.setTenantErpOrderTopCodes(
      tenantId: tenantId,
      revendaSameUf: orderTopCodes.revendaSameUf,
      revendaInterstate: orderTopCodes.revendaInterstate,
      usoConsumoContribuinteSameUf:
          orderTopCodes.usoConsumoContribuinteSameUf,
      usoConsumoContribuinteInterstate:
          orderTopCodes.usoConsumoContribuinteInterstate,
      usoConsumoNaoContribuinteSameUf:
          orderTopCodes.usoConsumoNaoContribuinteSameUf,
      usoConsumoNaoContribuinteInterstate:
          orderTopCodes.usoConsumoNaoContribuinteInterstate,
      industrializacaoSameUf: orderTopCodes.industrializacaoSameUf,
      industrializacaoInterstate: orderTopCodes.industrializacaoInterstate,
      zfmIndustrializacao: orderTopCodes.zfmIndustrializacao,
      zfmComercializacaoRevenda: orderTopCodes.zfmComercializacaoRevenda,
    );
  }

  String resolveTopCodeForOrder({
    required EnterpriseErpOrderTopCodes orderTopCodes,
    required SalePurpose salePurpose,
    required bool sameUf,
    required bool isCustomerContribuinte,
    required bool isCustomerZfmSuframa,
  }) {
    if (isCustomerZfmSuframa) {
      if (salePurpose == SalePurpose.industrializacao) {
        return orderTopCodes.zfmIndustrializacao;
      }
      return orderTopCodes.zfmComercializacaoRevenda;
    }

    switch (salePurpose) {
      case SalePurpose.revenda:
        return sameUf
            ? orderTopCodes.revendaSameUf
            : orderTopCodes.revendaInterstate;
      case SalePurpose.usoConsumo:
        if (isCustomerContribuinte) {
          return sameUf
              ? orderTopCodes.usoConsumoContribuinteSameUf
              : orderTopCodes.usoConsumoContribuinteInterstate;
        }
        return sameUf
            ? orderTopCodes.usoConsumoNaoContribuinteSameUf
            : orderTopCodes.usoConsumoNaoContribuinteInterstate;
      case SalePurpose.industrializacao:
        return sameUf
            ? orderTopCodes.industrializacaoSameUf
            : orderTopCodes.industrializacaoInterstate;
    }
  }

  Future<EnterpriseErpConnectionTestResult> testConnection({
    required String apiBaseUrl,
    required String environment,
    required String username,
    required String password,
    required String accessToken,
  }) async {
    final normalizedEnvironment = environment.trim().toLowerCase();
    if (normalizedEnvironment != 'homolog' && normalizedEnvironment != 'prod') {
      return const EnterpriseErpConnectionTestResult(
        success: false,
        statusCode: null,
        message: 'Ambiente invalido para teste. Use homolog ou prod.',
        requestUrl: '',
        requestMethod: '',
        latencyMs: 0,
        bearerReceived: false,
      );
    }

    final xToken = accessToken.trim();
    final clientId = username.trim();
    final clientSecret = password.trim();

    if (xToken.isEmpty || clientId.isEmpty || clientSecret.isEmpty) {
      return const EnterpriseErpConnectionTestResult(
        success: false,
        statusCode: null,
        message:
            'Informe Client Id, Client Secret e Token de integracao (X-Token).',
        requestUrl: '',
        requestMethod: '',
        latencyMs: 0,
        bearerReceived: false,
      );
    }

    final normalizedBaseUrl = sankhyaBaseUrlForEnvironment(
      normalizedEnvironment,
    );
    final targetUrl = '$normalizedBaseUrl/authenticate';

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final requestBody = jsonEncode(<String, String>{
      'environment': normalizedEnvironment,
      'clientId': clientId,
      'clientSecret': clientSecret,
      'xToken': xToken,
    });

    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse(authenticationProxyUrl);
      final response = await _httpClient
          .post(uri, headers: headers, body: requestBody)
          .timeout(const Duration(seconds: 15));

      stopwatch.stop();

      final bodyText = response.body;
      String parsedAccessToken = '';
      String parsedTokenType = '';
      int? parsedExpiresIn;
      String parsedErrorDescription = '';

      if (bodyText.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(bodyText);
          if (decoded is Map<String, dynamic>) {
            parsedAccessToken = _firstNonEmpty([
              _readString(decoded['access_token']),
              _readString(decoded['accessToken']),
              _readString(decoded['token']),
              _readString(decoded['bearerToken']),
            ]);
            parsedTokenType = _firstNonEmpty([
              _readString(decoded['token_type']),
              _readString(decoded['tokenType']),
            ]);
            parsedExpiresIn =
                _readInt(decoded['expires_in']) ??
                _readInt(decoded['expiresIn']);
            final errorDescription = _readString(decoded['error_description']);
            parsedErrorDescription = errorDescription.isNotEmpty
                ? errorDescription
                : _readString(decoded['error']);
          }
        } catch (_) {
          // Not JSON, continue with other parsing strategies.
        }
      }

      if (bodyText.trim().isNotEmpty && parsedAccessToken.isEmpty) {
        try {
          final formData = Uri.splitQueryString(bodyText);
          parsedAccessToken = _firstNonEmpty([
            (formData['access_token'] ?? '').trim(),
            (formData['accessToken'] ?? '').trim(),
            (formData['token'] ?? '').trim(),
            (formData['bearerToken'] ?? '').trim(),
          ]);
          parsedTokenType = _firstNonEmpty([
            (formData['token_type'] ?? '').trim(),
            (formData['tokenType'] ?? '').trim(),
          ]);
          parsedExpiresIn =
              _readInt(formData['expires_in']) ??
              _readInt(formData['expiresIn']);
          parsedErrorDescription =
              (formData['error_description'] ?? formData['error'] ?? '').trim();
        } catch (_) {
          // Not URL-encoded form, continue with regex parsing.
        }
      }

      if (bodyText.trim().isNotEmpty && parsedAccessToken.isEmpty) {
        parsedAccessToken = _extractAccessTokenWithRegex(bodyText);
      }

      final bearerReceived = parsedAccessToken.isNotEmpty;
      final bearerPreview = bearerReceived
          ? _maskToken(parsedAccessToken)
          : null;

      if (parsedTokenType.isEmpty && bearerReceived) {
        parsedTokenType = 'Bearer';
      }

      final isSuccess = response.statusCode == 200 && bearerReceived;
      final message = isSuccess
          ? 'Autenticacao OAuth validada com sucesso. Bearer token recebido.'
          : response.statusCode == 200
          ? 'HTTP 200 recebido, mas sem access_token no retorno.'
          : parsedErrorDescription.isNotEmpty
          ? 'Falha na autenticacao OAuth (HTTP ${response.statusCode}): $parsedErrorDescription'
          : 'Falha na autenticacao OAuth (HTTP ${response.statusCode}). Verifique Client Id/Secret, X-Token e ambiente.';

      return EnterpriseErpConnectionTestResult(
        success: isSuccess,
        statusCode: response.statusCode,
        message: message,
        requestUrl: targetUrl,
        requestMethod: 'POST',
        latencyMs: stopwatch.elapsedMilliseconds,
        bearerReceived: bearerReceived,
        expiresInSeconds: parsedExpiresIn,
        tokenType: parsedTokenType,
        bearerPreview: bearerPreview,
      );
    } catch (error) {
      stopwatch.stop();
      final lowerError = error.toString().toLowerCase();
      final likelyCors =
          lowerError.contains('failed to fetch') ||
          lowerError.contains('xmlhttprequest') ||
          lowerError.contains('cors');

      return EnterpriseErpConnectionTestResult(
        success: false,
        statusCode: null,
        message: likelyCors
            ? 'Falha ao testar no navegador (CORS/rede). O browser bloqueou a resposta antes de confirmar se o bearer foi gerado.'
            : 'Falha ao testar conexao: $error',
        requestUrl: targetUrl,
        requestMethod: 'POST',
        latencyMs: stopwatch.elapsedMilliseconds,
        bearerReceived: false,
      );
    }
  }

  Future<EnterpriseErpModuleSyncResult> syncCatalogModule({
    required String tenantId,
    required EnterpriseErpSyncModuleOption module,
    required String environment,
    required String username,
    required String password,
    required String accessToken,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return EnterpriseErpModuleSyncResult(
        success: false,
        moduleId: module.id,
        message: 'Tenant invalido para sincronizacao.',
        statusCode: null,
        requestUrl: syncCatalogModuleProxyUrl,
        importedCount: 0,
        filteredOutZeroCodeCount: 0,
        skippedNotFoundCount: 0,
        sourceCount: 0,
      );
    }

    if (!module.enabled) {
      return EnterpriseErpModuleSyncResult(
        success: false,
        moduleId: module.id,
        message:
            'Modulo ainda nao habilitado. Valide endpoint/permissoes antes de sincronizar.',
        statusCode: null,
        requestUrl: syncCatalogModuleProxyUrl,
        importedCount: 0,
        filteredOutZeroCodeCount: 0,
        skippedNotFoundCount: 0,
        sourceCount: 0,
      );
    }

    final normalizedEnvironment = environment.trim().toLowerCase();
    if (normalizedEnvironment != 'homolog' && normalizedEnvironment != 'prod') {
      return EnterpriseErpModuleSyncResult(
        success: false,
        moduleId: module.id,
        message: 'Ambiente invalido para sincronizacao. Use homolog ou prod.',
        statusCode: null,
        requestUrl: syncCatalogModuleProxyUrl,
        importedCount: 0,
        filteredOutZeroCodeCount: 0,
        skippedNotFoundCount: 0,
        sourceCount: 0,
      );
    }

    final xToken = accessToken.trim();
    final clientId = username.trim();
    final clientSecret = password.trim();
    if (xToken.isEmpty || clientId.isEmpty || clientSecret.isEmpty) {
      return EnterpriseErpModuleSyncResult(
        success: false,
        moduleId: module.id,
        message: 'Informe Client Id, Client Secret e X-Token para sincronizar.',
        statusCode: null,
        requestUrl: syncCatalogModuleProxyUrl,
        importedCount: 0,
        filteredOutZeroCodeCount: 0,
        skippedNotFoundCount: 0,
        sourceCount: 0,
      );
    }

    final body = jsonEncode(<String, Object?>{
      'tenantId': normalizedTenantId,
      'module': module.id,
      'environment': normalizedEnvironment,
      'clientId': clientId,
      'clientSecret': clientSecret,
      'xToken': xToken,
    });

    try {
      final uri = Uri.parse(syncCatalogModuleProxyUrl);
      final response = await _httpClient
          .post(
            uri,
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 60));

      final payload = _decodeResponseAsMap(response.body);
      final importedCount = _readInt(payload['importedCount']) ?? 0;
      final filteredOutZeroCodeCount =
          _readInt(payload['filteredOutZeroCodeCount']) ?? 0;
        final skippedNotFoundCount =
          _readInt(payload['skippedNotFoundCount']) ?? 0;
      final sourceCount = _readInt(payload['sourceCount']) ?? 0;
      final messageFromApi = _readString(payload['message']);
      final success = response.statusCode == 200;

      return EnterpriseErpModuleSyncResult(
        success: success,
        moduleId: module.id,
        message: messageFromApi.isNotEmpty
            ? messageFromApi
            : success
            ? 'Sincronizacao concluida.'
            : 'Falha na sincronizacao do modulo ${module.label}.',
        statusCode: response.statusCode,
        requestUrl: syncCatalogModuleProxyUrl,
        importedCount: importedCount,
        filteredOutZeroCodeCount: filteredOutZeroCodeCount,
        skippedNotFoundCount: skippedNotFoundCount,
        sourceCount: sourceCount,
      );
    } catch (error) {
      return EnterpriseErpModuleSyncResult(
        success: false,
        moduleId: module.id,
        message: 'Falha ao sincronizar modulo ${module.label}: $error',
        statusCode: null,
        requestUrl: syncCatalogModuleProxyUrl,
        importedCount: 0,
        filteredOutZeroCodeCount: 0,
        skippedNotFoundCount: 0,
        sourceCount: 0,
      );
    }
  }

  Future<List<EnterpriseErpOperationType>> fetchOperationTypes({
    required String environment,
    required String username,
    required String password,
    required String accessToken,
  }) async {
    final normalizedEnvironment = environment.trim().toLowerCase();
    if (normalizedEnvironment != 'homolog' && normalizedEnvironment != 'prod') {
      throw Exception('Ambiente invalido. Use homolog ou prod.');
    }

    final xToken = accessToken.trim();
    final clientId = username.trim();
    final clientSecret = password.trim();
    if (xToken.isEmpty || clientId.isEmpty || clientSecret.isEmpty) {
      throw Exception(
        'Informe Client Id, Client Secret e X-Token antes de buscar as TOPs.',
      );
    }

    final body = jsonEncode(<String, Object?>{
      'environment': normalizedEnvironment,
      'clientId': clientId,
      'clientSecret': clientSecret,
      'xToken': xToken,
    });

    final uri = Uri.parse(fetchOperationTypesProxyUrl);
    final response = await _httpClient
        .post(
          uri,
          headers: const <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    final payload = _decodeResponseAsMap(response.body);
    if (response.statusCode != 200 || payload['ok'] != true) {
      final message = _readString(payload['message']);
      throw Exception(
        message.isNotEmpty
            ? message
            : 'Falha ao buscar tipos de operacao (HTTP ${response.statusCode}).',
      );
    }

    final rawItems = payload['operationTypes'];
    if (rawItems is! List) {
      return const <EnterpriseErpOperationType>[];
    }

    return rawItems
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => EnterpriseErpOperationType(
            code: _readString(item['code']),
            description: _readString(item['description']),
            movementType: _readString(item['movementType']),
          ),
        )
        .where((item) => item.code.isNotEmpty)
        .toList(growable: false);
  }

  static String _resolveProxyUrl({
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

  String _readString(Object? value) => value?.toString().trim() ?? '';

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  int? _readInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString().trim());
  }

  String _extractAccessTokenWithRegex(String body) {
    final jsonMatch = RegExp(r'"access_token"\s*:\s*"([^"]+)"')
        .firstMatch(body);
    if (jsonMatch != null && jsonMatch.groupCount >= 1) {
      return (jsonMatch.group(1) ?? '').trim();
    }

    final formMatch = RegExp(r'(?:^|[?&])access_token=([^&\s]+)')
        .firstMatch(body);
    if (formMatch != null && formMatch.groupCount >= 1) {
      return Uri.decodeQueryComponent((formMatch.group(1) ?? '').trim());
    }

    return '';
  }

  Map<String, dynamic> _decodeResponseAsMap(String bodyText) {
    if (bodyText.trim().isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(bodyText);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      // Ignore parse errors and fallback to empty map.
    }
    return const <String, dynamic>{};
  }

  String _maskToken(String token) {
    final trimmed = token.trim();
    if (trimmed.length <= 10) {
      final take = trimmed.length < 4 ? trimmed.length : 4;
      return '${trimmed.substring(0, take)}...';
    }
    final head = trimmed.substring(0, 6);
    final tail = trimmed.substring(trimmed.length - 4);
    return '$head...$tail';
  }

  EnterpriseErpIntegrationData _resolveIntegrationData(
    Map<String, dynamic> workspaceData,
  ) {
    final direct = _readNestedMap(workspaceData, 'erpIntegration');
    final selectedCompany = _readNestedMap(direct, 'selectedCompany');
    final credentials = _readNestedMap(direct, 'credentials');

    final provider =
        (direct['provider'] ?? workspaceData['erpIntegration.provider'] ?? '')
            .toString()
            .trim();
    final environment =
        (direct['environment'] ??
                workspaceData['erpIntegration.environment'] ??
                '')
            .toString()
            .trim();
    final status =
        (direct['status'] ?? workspaceData['erpIntegration.status'] ?? '')
            .toString()
            .trim();

    final selectedId =
        (selectedCompany['id'] ??
                workspaceData['erpIntegration.selectedCompany.id'] ??
                '')
            .toString()
            .trim();
    final selectedName =
        (selectedCompany['name'] ??
                workspaceData['erpIntegration.selectedCompany.name'] ??
                '')
            .toString()
            .trim();

    final apiBaseUrl =
        (credentials['apiBaseUrl'] ??
                workspaceData['erpIntegration.credentials.apiBaseUrl'] ??
                '')
            .toString()
            .trim();
    final username =
        (credentials['username'] ??
                workspaceData['erpIntegration.credentials.username'] ??
                '')
            .toString()
            .trim();
    final password =
        (credentials['password'] ??
                workspaceData['erpIntegration.credentials.password'] ??
                '')
            .toString()
            .trim();
    final accessToken =
        (credentials['accessToken'] ??
                workspaceData['erpIntegration.credentials.accessToken'] ??
                '')
            .toString()
            .trim();
    final priceTableCodes = _readPriceTableCodes(
      primary: direct['priceTableCodes'],
      fallback: workspaceData['erpIntegration.priceTableCodes'],
    );
    final orderTopCodes = _readOrderTopCodes(
      primary: direct['orderTopCodes'],
      fallback: workspaceData['erpIntegration.orderTopCodes'],
    );

    return EnterpriseErpIntegrationData(
      provider: provider,
      environment: environment,
      status: status,
      selectedCompanyId: selectedId,
      selectedCompanyName: selectedName,
      apiBaseUrl: apiBaseUrl,
      username: username,
      password: password,
      accessToken: accessToken,
      priceTableCodes: priceTableCodes,
      orderTopCodes: orderTopCodes,
    );
  }

  EnterpriseErpOrderTopCodes _readOrderTopCodes({
    required Object? primary,
    required Object? fallback,
  }) {
    Map<String, dynamic> asMap(Object? source) {
      if (source is Map<String, dynamic>) {
        return source;
      }
      if (source is Map) {
        return source.map((key, value) => MapEntry(key.toString(), value));
      }
      return const <String, dynamic>{};
    }

    final merged = <String, dynamic>{}
      ..addAll(asMap(fallback))
      ..addAll(asMap(primary));

    String readCode(String key) {
      final raw = (merged[key] ?? '').toString().trim();
      if (!RegExp(r'^\d+$').hasMatch(raw)) {
        return '';
      }
      return raw;
    }

    final legacyUsoConsumoSameUf = readCode('uso_consumo_same_uf');
    final legacyUsoConsumoInterstate = readCode('uso_consumo_interstate');

    return EnterpriseErpOrderTopCodes(
      revendaSameUf: readCode('revenda_same_uf'),
      revendaInterstate: readCode('revenda_interstate'),
      usoConsumoContribuinteSameUf:
          readCode('uso_consumo_contribuinte_same_uf'),
      usoConsumoContribuinteInterstate:
          readCode('uso_consumo_contribuinte_interstate'),
      usoConsumoNaoContribuinteSameUf:
          readCode('uso_consumo_nao_contribuinte_same_uf').isNotEmpty
          ? readCode('uso_consumo_nao_contribuinte_same_uf')
          : legacyUsoConsumoSameUf,
      usoConsumoNaoContribuinteInterstate:
          readCode('uso_consumo_nao_contribuinte_interstate').isNotEmpty
          ? readCode('uso_consumo_nao_contribuinte_interstate')
          : legacyUsoConsumoInterstate,
      industrializacaoSameUf: readCode('industrializacao_same_uf'),
      industrializacaoInterstate: readCode('industrializacao_interstate'),
      zfmIndustrializacao: readCode('zfm_industrializacao'),
      zfmComercializacaoRevenda: readCode('zfm_comercializacao_revenda'),
    );
  }

  List<String> _readPriceTableCodes({
    required Object? primary,
    required Object? fallback,
  }) {
    final tokens = <String>[];
    void appendFrom(Object? source) {
      if (source is List) {
        for (final item in source) {
          tokens.add((item ?? '').toString());
        }
        return;
      }
      if (source is String) {
        tokens.addAll(source.split(RegExp(r'[,;\s\n]+')));
      }
    }

    appendFrom(primary);
    appendFrom(fallback);
    return _normalizePriceTableCodes(tokens);
  }

  List<String> _normalizePriceTableCodes(Iterable<String> values) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final clean = value.trim();
      if (clean.isEmpty) {
        continue;
      }
      if (!RegExp(r'^\d+$').hasMatch(clean)) {
        continue;
      }
      if (!seen.add(clean)) {
        continue;
      }
      normalized.add(clean);
    }
    return normalized;
  }

  Map<String, dynamic> _readNestedMap(Map<String, dynamic> source, String key) {
    final raw = source[key];
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, dynamic>{};
  }
}
