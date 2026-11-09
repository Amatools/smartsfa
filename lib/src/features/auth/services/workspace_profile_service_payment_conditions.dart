part of 'workspace_profile_service.dart';

mixin _WorkspaceProfilePaymentConditionsMixin {
  FirebaseFirestore get _firestore;
  CollectionReference<Map<String, dynamic>> get _representedCompaniesCollection;

  /// Contas `brand_owner_workspace` (enterprise) usam um id sintetico de UI
  /// (`enterprise_default_<tenantId>`, ver `app_shell.dart`/
  /// `web_portal_shell_state_section.dart`) que NUNCA vira um documento real
  /// em `tenant_represented_companies` - nao ha "representada" de verdade
  /// para essas contas, so a propria empresa. Tratar esse id sintetico como
  /// "sem representada" aqui evita ler/gravar num documento que nunca existe
  /// (o que gera lista sempre vazia na leitura e permission-denied/erro na
  /// escrita), mantendo o mesmo escopo tenant-level ja usado historicamente
  /// para essas contas. Mesmo padrao ja aplicado em
  /// `watchReformaTributariaEnabled`/`setReformaTributariaEnabled`.
  String? _tenantScopedRepresentedCompanyId(
    String tenantId,
    String? representedCompanyId,
  ) {
    return EnterpriseRepresentedScope.effectiveRepresentedCompanyId(
      tenantId: tenantId,
      representedCompanyId: representedCompanyId,
    );
  }

  Stream<List<PaymentConditionRule>> watchPaymentConditionRules({
    required String tenantId,
    String? representedCompanyId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <PaymentConditionRule>[]);
    }

    final normalizedRepresentedCompanyId = _tenantScopedRepresentedCompanyId(
      normalizedTenantId,
      representedCompanyId,
    );
    if (normalizedRepresentedCompanyId != null) {
      final representedRef = _representedCompaniesCollection.doc(
        _representedCompanyDocId(
          normalizedTenantId,
          normalizedRepresentedCompanyId,
        ),
      );
      return representedRef.snapshots().map((doc) {
        final data = doc.data() ?? const <String, dynamic>{};
        return _parsePaymentConditionRulesList(data['paymentConditionRules']);
      });
    }

    final scopeKey = _scopeKey(normalizedRepresentedCompanyId);

    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .snapshots()
        .map((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          return _readPaymentConditionRulesForScope(
            data: data,
            scopeKey: scopeKey,
          );
        });
  }

  /// Leitura unica (nao continua) das condicoes de pagamento, usada pelo
  /// editor de pedido no mobile. Por design "offline first": o `.get()`
  /// padrao do Firestore ja tenta o servidor e cai para o cache local quando
  /// offline, sem manter uma assinatura (`.snapshots()`) aberta o tempo todo.
  /// Isso evita leituras extras cobradas enquanto o editor fica aberto -
  /// edicoes feitas no portal web so refletem no mobile na proxima vez que o
  /// editor for aberto/reaberto ou apos uma sincronizacao manual.
  Future<List<PaymentConditionRule>> fetchPaymentConditionRules({
    required String tenantId,
    String? representedCompanyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const <PaymentConditionRule>[];
    }

    final normalizedRepresentedCompanyId = _tenantScopedRepresentedCompanyId(
      normalizedTenantId,
      representedCompanyId,
    );
    if (normalizedRepresentedCompanyId != null) {
      final representedRef = _representedCompaniesCollection.doc(
        _representedCompanyDocId(
          normalizedTenantId,
          normalizedRepresentedCompanyId,
        ),
      );
      final doc = await representedRef.get();
      final data = doc.data() ?? const <String, dynamic>{};
      return _parsePaymentConditionRulesList(data['paymentConditionRules']);
    }

    final scopeKey = _scopeKey(normalizedRepresentedCompanyId);
    final doc = await _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .get();
    final data = doc.data() ?? const <String, dynamic>{};
    return _readPaymentConditionRulesForScope(data: data, scopeKey: scopeKey);
  }

  Future<void> updatePaymentConditionRules({
    required String tenantId,
    required List<PaymentConditionRule> values,
    String? representedCompanyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Dados invalidos para salvar condicoes de pagamento.');
    }

    final normalizedRepresentedCompanyId = _tenantScopedRepresentedCompanyId(
      normalizedTenantId,
      representedCompanyId,
    );
    final scopeKey = _scopeKey(normalizedRepresentedCompanyId);

    final normalizedValues = values
        .map(
          (rule) => PaymentConditionRule(
            description: rule.description.trim(),
            minimumValue: rule.minimumValue,
          ),
        )
        .where((rule) => rule.description.isNotEmpty)
        .map((rule) => rule.toMap())
        .toList(growable: false);

    if (normalizedRepresentedCompanyId != null) {
      final representedRef = _representedCompaniesCollection.doc(
        _representedCompanyDocId(
          normalizedTenantId,
          normalizedRepresentedCompanyId,
        ),
      );
      final representedSnapshot = await representedRef.get();
      if (!representedSnapshot.exists) {
        throw StateError(
          'Representada ativa não encontrada para salvar condições de pagamento.',
        );
      }

      await representedRef.set({
        'paymentConditionRules': normalizedValues,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
      return;
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'representedPaymentConditionRules': {scopeKey: normalizedValues},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  List<PaymentConditionRule> filterPaymentConditionsByOrderValue({
    required List<PaymentConditionRule> rules,
    required double orderTotal,
  }) {
    final normalizedTotal = orderTotal < 0 ? 0 : orderTotal;
    return rules
        .where((rule) => normalizedTotal >= rule.minimumValue)
        .toList(growable: false);
  }

  List<PaymentConditionRule> _parsePaymentConditionRulesList(Object? raw) {
    if (raw is! List) {
      return const <PaymentConditionRule>[];
    }

    final result = <PaymentConditionRule>[];
    for (final item in raw) {
      if (item is String) {
        final description = item.trim();
        if (description.isEmpty) {
          continue;
        }
        result.add(
          PaymentConditionRule(description: description, minimumValue: 0),
        );
        continue;
      }

      if (item is Map) {
        final map = item.cast<Object?, Object?>();
        final description = (map['description'] ?? map['descricao'] ?? '')
            .toString()
            .trim();
        if (description.isEmpty) {
          continue;
        }

        result.add(
          PaymentConditionRule(
            description: description,
            minimumValue: _toDouble(map['minimumValue'] ?? map['valorMinimo']),
          ),
        );
      }
    }

    return result;
  }

  List<PaymentConditionRule> _readPaymentConditionRulesForScope({
    required Map<String, dynamic> data,
    required String scopeKey,
  }) {
    final scopedRoot = data['representedPaymentConditionRules'];
    if (scopedRoot is Map) {
      final scopedRaw = scopedRoot[scopeKey] ?? scopedRoot['__tenant__'];
      final scopedParsed = _parsePaymentConditionRulesList(scopedRaw);
      if (scopedParsed.isNotEmpty) {
        return scopedParsed;
      }
    }

    // Legacy fallback for old tenant-wide payloads.
    return _parsePaymentConditionRulesList(data['paymentConditionRules']);
  }
}
