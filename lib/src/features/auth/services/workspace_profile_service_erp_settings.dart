part of 'workspace_profile_service.dart';

mixin _WorkspaceProfileErpSettingsMixin {
  FirebaseFirestore get _firestore;
  CollectionReference<Map<String, dynamic>> get _representedCompaniesCollection;

  Stream<Map<String, dynamic>?> watchWorkspace(String tenantId);

  Future<void> setProductSyncFromErpEnabled({
    required String tenantId,
    required bool enabled,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError(
        'Workspace invalido para configurar sincronizacao de produtos.',
      );
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'productSyncFromErpEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setTenantErpSelectedCompany({
    required String tenantId,
    required String provider,
    required String companyId,
    required String companyName,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedProvider = provider.trim().toLowerCase();
    final normalizedCompanyId = companyId.trim();
    final normalizedCompanyName = companyName.trim();

    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para configurar ERP.');
    }
    if (normalizedProvider.isEmpty ||
        (normalizedProvider != 'sankhya' && normalizedProvider != 'custom')) {
      throw StateError('Provider ERP invalido para configuracao.');
    }
    if (normalizedCompanyId.isEmpty || normalizedCompanyName.isEmpty) {
      throw StateError('Selecione uma empresa ERP valida para continuar.');
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'erpProvider': normalizedProvider,
      'operationMode': normalizedProvider == 'sankhya' ? 'sankhya' : 'custom',
      'erpIntegration': {
        'provider': normalizedProvider,
        'selectedCompany': {
          'id': normalizedCompanyId,
          'name': normalizedCompanyName,
        },
        'selectionLocked': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setTenantErpCredentials({
    required String tenantId,
    required String provider,
    required String environment,
    required String apiBaseUrl,
    required String username,
    required String password,
    required String accessToken,
    required List<String> priceTableCodes,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedProvider = provider.trim().toLowerCase();
    final normalizedEnvironment = environment.trim().toLowerCase();
    final normalizedBaseUrl = _normalize(apiBaseUrl)
        .replaceAll(RegExp(r'/+$'), '');
    final normalizedUsername = _normalize(username);
    final normalizedPassword = _normalize(password);
    final normalizedToken = _normalize(accessToken);
    final normalizedPriceTableCodes = _normalizePriceTableCodes(
      priceTableCodes,
    );

    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para salvar credenciais ERP.');
    }
    if (normalizedProvider.isEmpty ||
        (normalizedProvider != 'sankhya' && normalizedProvider != 'custom')) {
      throw StateError('Provider ERP invalido para salvar credenciais.');
    }
    if (normalizedEnvironment != 'homolog' && normalizedEnvironment != 'prod') {
      throw StateError('Ambiente invalido. Use homolog ou prod.');
    }
    if (normalizedBaseUrl.isEmpty) {
      throw StateError('Informe a URL base da API para continuar.');
    }

    final hasToken = normalizedToken.isNotEmpty;
    final hasUserAndPass =
        normalizedUsername.isNotEmpty && normalizedPassword.isNotEmpty;
    if (!hasToken && !hasUserAndPass) {
      throw StateError(
        'Informe token de acesso ou usuario e senha para autenticar no ERP.',
      );
    }

    final tenantRef = _firestore.collection('tenants').doc(normalizedTenantId);
    final currentSnapshot = await tenantRef.get();
    final currentData = currentSnapshot.data() ?? const <String, dynamic>{};
    final currentIntegration = currentData['erpIntegration'];

    String selectedCompanyId = '';
    String selectedCompanyName = '';
    bool selectionLocked = true;

    if (currentIntegration is Map) {
      final selectedCompany = currentIntegration['selectedCompany'];
      if (selectedCompany is Map) {
        selectedCompanyId = (selectedCompany['id'] ?? '').toString().trim();
        selectedCompanyName = (selectedCompany['name'] ?? '').toString().trim();
      }

      final rawSelectionLocked = currentIntegration['selectionLocked'];
      if (rawSelectionLocked is bool) {
        selectionLocked = rawSelectionLocked;
      }
    }

    await tenantRef.set({
      'erpProvider': normalizedProvider,
      'operationMode': normalizedProvider == 'sankhya' ? 'sankhya' : 'custom',
      'erpIntegration': {
        'provider': normalizedProvider,
        'selectedCompany': {
          'id': selectedCompanyId,
          'name': selectedCompanyName,
        },
        'selectionLocked': selectionLocked,
        'environment': normalizedEnvironment,
        'credentials': {
          'apiBaseUrl': normalizedBaseUrl,
          'username': normalizedUsername,
          'password': normalizedPassword,
          'accessToken': normalizedToken,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'priceTableCodes': normalizedPriceTableCodes,
        'status': 'credentials_ready',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setTenantErpPriceTableCodes({
    required String tenantId,
    required List<String> priceTableCodes,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para salvar codigos de tabela.');
    }

    final normalizedCodes = _normalizePriceTableCodes(priceTableCodes);
    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'erpIntegration': {
        'priceTableCodes': normalizedCodes,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setTenantErpOrderTopCodes({
    required String tenantId,
    required String revendaSameUf,
    required String revendaInterstate,
    required String usoConsumoContribuinteSameUf,
    required String usoConsumoContribuinteInterstate,
    required String usoConsumoNaoContribuinteSameUf,
    required String usoConsumoNaoContribuinteInterstate,
    required String industrializacaoSameUf,
    required String industrializacaoInterstate,
    required String zfmIndustrializacao,
    required String zfmComercializacaoRevenda,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para salvar TOPs de pedido.');
    }

    final orderTopCodes = <String, String>{
      'revenda_same_uf': _normalizeTopCode(revendaSameUf),
      'revenda_interstate': _normalizeTopCode(revendaInterstate),
      'uso_consumo_contribuinte_same_uf': _normalizeTopCode(
        usoConsumoContribuinteSameUf,
      ),
      'uso_consumo_contribuinte_interstate': _normalizeTopCode(
        usoConsumoContribuinteInterstate,
      ),
      'uso_consumo_nao_contribuinte_same_uf': _normalizeTopCode(
        usoConsumoNaoContribuinteSameUf,
      ),
      'uso_consumo_nao_contribuinte_interstate': _normalizeTopCode(
        usoConsumoNaoContribuinteInterstate,
      ),
      'industrializacao_same_uf': _normalizeTopCode(industrializacaoSameUf),
      'industrializacao_interstate': _normalizeTopCode(
        industrializacaoInterstate,
      ),
      'zfm_industrializacao': _normalizeTopCode(zfmIndustrializacao),
      'zfm_comercializacao_revenda': _normalizeTopCode(
        zfmComercializacaoRevenda,
      ),
    };

    final emptyFields = orderTopCodes.entries
        .where((entry) => entry.value.isEmpty)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (emptyFields.isNotEmpty) {
      throw StateError(
        'Preencha as 10 TOPs de pedido antes de salvar. Faltando: ${emptyFields.join(', ')}.',
      );
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'erpIntegration': {
        'orderTopCodes': orderTopCodes,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setAdvancedPricingEnabled({
    required String tenantId,
    required bool enabled,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError(
        'Workspace invalido para configurar precificacao avancada.',
      );
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'advancedPricingEnabled': enabled,
      'featureFlags': {'advancedPricingEnabled': enabled},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Importante: montar um Map aninhado de verdade (nao chaves com ponto tipo
  // 'featureFlags.x') porque set(merge:true) no cliente Dart do Firestore NAO
  // expande chaves com ponto em caminho aninhado (isso so acontece em
  // update()). Usar chave com ponto aqui grava um campo plano chamado
  // literalmente "featureFlags.x", nunca lido por _readFeatureFlag (bug real
  // ja encontrado e corrigido em producao - ver memoria do repo).
  Future<void> updateWorkspaceFeatureFlags({
    required String tenantId,
    required Map<String, bool> flags,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para atualizar feature flags.');
    }

    final featureFlagsPayload = <String, Object?>{};
    for (final entry in flags.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      featureFlagsPayload[key] = entry.value;
    }

    if (featureFlagsPayload.isEmpty) {
      return;
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'featureFlags': featureFlagsPayload,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Le o status da Reforma Tributaria no escopo correto: para
  /// `brand_owner_workspace` o flag e por tenant (ha uma unica empresa); para
  /// `rep_workspace`/`seller_solo_workspace` o flag e por representada, pois
  /// um mesmo tenant pode ter varias empresas representadas.
  Stream<bool> watchReformaTributariaEnabled({
    required String tenantId,
    required String workspaceType,
    String? representedCompanyId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(false);
    }

    if (workspaceType.trim() == 'brand_owner_workspace') {
      return watchWorkspace(normalizedTenantId).map(
        (data) => _readFeatureFlag(
          data ?? const <String, dynamic>{},
          'reformaTributariaEnabled',
        ),
      );
    }

    final normalizedRepresentedId = (representedCompanyId ?? '').trim();
    if (normalizedRepresentedId.isEmpty) {
      return Stream.value(false);
    }

    return _representedCompaniesCollection
        .doc(
          _representedCompanyDocId(normalizedTenantId, normalizedRepresentedId),
        )
        .snapshots()
        .map(
          (doc) => _readFeatureFlag(
            doc.data() ?? const <String, dynamic>{},
            'reformaTributariaEnabled',
          ),
        );
  }

  bool _readFeatureFlag(Map<String, dynamic> data, String key) {
    final flags = data['featureFlags'];
    if (flags is Map) {
      final raw = flags[key];
      if (raw is bool) {
        return raw;
      }
    }
    return false;
  }

  /// Grava o status da Reforma Tributaria no mesmo escopo usado por
  /// [watchReformaTributariaEnabled].
  Future<void> setReformaTributariaEnabled({
    required String tenantId,
    required String workspaceType,
    String? representedCompanyId,
    required bool enabled,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para atualizar Reforma Tributaria.');
    }

    if (workspaceType.trim() == 'brand_owner_workspace') {
      await updateWorkspaceFeatureFlags(
        tenantId: normalizedTenantId,
        flags: {'reformaTributariaEnabled': enabled},
      );
      return;
    }

    final normalizedRepresentedId = (representedCompanyId ?? '').trim();
    if (normalizedRepresentedId.isEmpty) {
      throw StateError(
        'Selecione uma representada para ativar a Reforma Tributaria.',
      );
    }

    await _representedCompaniesCollection
        .doc(
          _representedCompanyDocId(normalizedTenantId, normalizedRepresentedId),
        )
        .set(<String, Object?>{
          'featureFlags': {'reformaTributariaEnabled': enabled},
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> setWorkspacePlanTier({
    required String tenantId,
    required String tier,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedTier = tier.trim().toLowerCase();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para atualizar nivel de plano.');
    }
    if (normalizedTier != 'base' && normalizedTier != 'upgrade') {
      throw StateError('Nivel de plano invalido. Use base ou upgrade.');
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'planTier': normalizedTier,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
