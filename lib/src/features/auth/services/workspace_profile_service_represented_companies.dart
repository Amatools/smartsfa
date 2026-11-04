part of 'workspace_profile_service.dart';

mixin _WorkspaceProfileRepresentedCompaniesMixin {
  FirebaseFirestore get _firestore;
  CollectionReference<Map<String, dynamic>> get _representedCompaniesCollection;

  Stream<List<Map<String, Object?>>> watchRepresentedCompanies(
    String tenantId,
  ) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <Map<String, Object?>>[]);
    }

    return _representedCompaniesCollection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map((snapshot) {
          final companies = snapshot.docs
              .map(
                (doc) => doc.data().map(
                  (key, value) => MapEntry(key, value as Object?),
                ),
              )
              .toList(growable: false);
          companies.sort((a, b) {
            final aName = (a['nomeFantasia'] ?? '').toString().toLowerCase();
            final bName = (b['nomeFantasia'] ?? '').toString().toLowerCase();
            return aName.compareTo(bName);
          });
          return companies;
        });
  }

  Future<void> upsertRepresentedCompany({
    required String tenantId,
    required Map<String, Object?> values,
    String? companyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Tenant invalido para cadastro de representada.');
    }

    final normalizedId = (companyId ?? '').trim().isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : companyId!.trim();
    final docId = '${normalizedTenantId}_$normalizedId';
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final nomeFantasia = _normalize(values['nomeFantasia']);
    if (nomeFantasia.isEmpty) {
      throw StateError('Nome fantasia é obrigatório.');
    }

    final cnpjDigits = _digitsOnly(values['cnpj']);
    if (!_isValidCnpjDigits(cnpjDigits)) {
      throw StateError('CNPJ inválido. Informe um CNPJ válido com 14 dígitos.');
    }
    final formattedCnpj = _formatCnpj(cnpjDigits);
    final cnpjRoot = cnpjDigits.substring(0, 8);

    final cepDigits = _digitsOnly(values['cep']);
    if (cepDigits.isNotEmpty && cepDigits.length != 8) {
      throw StateError('CEP inválido. Informe um CEP com 8 dígitos.');
    }

    final telefoneDigits = _digitsOnly(values['telefone']);
    if (telefoneDigits.isNotEmpty &&
        (telefoneDigits.length < 10 || telefoneDigits.length > 11)) {
      throw StateError('Telefone inválido. Informe 10 ou 11 dígitos.');
    }

    final normalizedEmail = _normalize(values['email']).toLowerCase();
    if (normalizedEmail.isNotEmpty && !_isValidEmailAddress(normalizedEmail)) {
      throw StateError('E-mail inválido.');
    }

    final normalizedUf = _normalize(values['uf']).toUpperCase();
    if (!_validBrazilStates.contains(normalizedUf)) {
      throw StateError('UF inválida.');
    }

    final parentCompanyId = _normalize(values['parentCompanyId']);
    if (parentCompanyId == normalizedId) {
      throw StateError('Uma empresa não pode ser matriz dela mesma.');
    }

    QuerySnapshot<Map<String, dynamic>>? linkedChildrenSnapshot;
    try {
      linkedChildrenSnapshot = await _representedCompaniesCollection
          .where('tenantId', isEqualTo: normalizedTenantId)
          .where('parentCompanyId', isEqualTo: normalizedId)
          .limit(1)
          .get();
    } on FirebaseException catch (error) {
      if (!_isConnectivityLimitedError(error)) {
        rethrow;
      }
    }
    if (parentCompanyId.isNotEmpty &&
        linkedChildrenSnapshot != null &&
        linkedChildrenSnapshot.docs.isNotEmpty) {
      throw StateError(
        'Esta empresa já possui filiais vinculadas e não pode ser marcada como filial.',
      );
    }

    if (parentCompanyId.isNotEmpty) {
      DocumentSnapshot<Map<String, dynamic>>? parentDoc;
      try {
        parentDoc = await _representedCompaniesCollection
            .doc('${normalizedTenantId}_$parentCompanyId')
            .get();
      } on FirebaseException catch (error) {
        if (!_isConnectivityLimitedError(error)) {
          rethrow;
        }
      }

      final parentData = parentDoc?.data();
      if (parentData != null) {
        final parentParentCompanyId = _normalize(parentData['parentCompanyId']);
        if (parentParentCompanyId.isNotEmpty) {
          throw StateError('A matriz selecionada já é uma filial.');
        }

        final parentCnpjDigits = _digitsOnly(parentData['cnpj']);
        if (parentCnpjDigits.length == 14 &&
            parentCnpjDigits.substring(0, 8) != cnpjRoot) {
          throw StateError(
            'Filial e matriz devem compartilhar a mesma raiz de CNPJ (8 primeiros dígitos).',
          );
        }
      }
    }

    QuerySnapshot<Map<String, dynamic>>? duplicatedCnpjSnapshot;
    try {
      duplicatedCnpjSnapshot = await _representedCompaniesCollection
          .where('tenantId', isEqualTo: normalizedTenantId)
          .where('cnpj', isEqualTo: formattedCnpj)
          .limit(2)
          .get();
    } on FirebaseException catch (error) {
      if (!_isConnectivityLimitedError(error)) {
        rethrow;
      }
    }
    if (duplicatedCnpjSnapshot != null) {
      for (final doc in duplicatedCnpjSnapshot.docs) {
        final existingCompanyId = _normalize(doc.data()['companyId']);
        if (existingCompanyId != normalizedId) {
          throw StateError('Já existe uma representada com esse CNPJ.');
        }
      }
    }

    await _representedCompaniesCollection.doc(docId).set({
      'tenantId': normalizedTenantId,
      'companyId': normalizedId,
      'parentCompanyId': parentCompanyId,
      'nomeFantasia': nomeFantasia,
      'razaoSocial': _normalize(values['razaoSocial']),
      'cnpj': formattedCnpj,
      'cep': _formatCep(cepDigits),
      'logradouro': _normalize(values['logradouro']),
      'numero': _normalize(values['numero']),
      'logoUrl': _normalize(values['logoUrl']),
      'contato': _normalize(values['contato']),
      'telefone': _formatPhone(telefoneDigits),
      'email': normalizedEmail,
      'cidade': _normalize(values['cidade']),
      'uf': normalizedUf,
      'segmento': _normalize(values['segmento']),
      'taxRegime': _normalizeTaxRegime(values['taxRegime']),
      'ativo': values['ativo'] != false,
      'companyUnits': FieldValue.delete(),
      'defaultOrderOriginUnitId': FieldValue.delete(),
      'updatedAt': nowIso,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _ensureDefaultCatalogAndPricingScope(
      tenantId: normalizedTenantId,
      representedCompanyId: normalizedId,
      representedCompanyName: _normalize(values['nomeFantasia']),
    );
  }

  Future<void> _ensureDefaultCatalogAndPricingScope({
    required String tenantId,
    required String representedCompanyId,
    required String representedCompanyName,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedRepresentedId = representedCompanyId.trim();
    if (normalizedTenantId.isEmpty || normalizedRepresentedId.isEmpty) {
      return;
    }

    final scopeKey = _normalizeDefaultPricingScopeKey(normalizedRepresentedId);
    final legacyScopeKey = normalizedRepresentedId.replaceAll('/', '_');
    final defaultPriceTableId = 'pt_default_${normalizedTenantId}_$scopeKey';
    final defaultCatalogId = 'products_default_${normalizedTenantId}_$scopeKey';
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await _firestore.collection('tabelas_preco').doc(defaultPriceTableId).set({
      'id': defaultPriceTableId,
      'tenantId': normalizedTenantId,
      'nome': 'Tabela padrao',
      'scopeType': 'represented_company',
      'scopeLabel': representedCompanyName.isEmpty
          ? 'Tabela padrao da representada'
          : 'Tabela padrao - $representedCompanyName',
      'scopeIndex': <String>['default', scopeKey],
      'origem': 'system',
      'status': 'ativo',
      'linkedEntityId': normalizedRepresentedId,
      'rowCount': 0,
      'createdAt': nowIso,
      'updatedAt': nowIso,
    }, SetOptions(merge: true));

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'defaultPriceTableIds': {scopeKey: defaultPriceTableId},
      'defaultPriceRegionIds': {scopeKey: _defaultPriceRegionId},
      'defaultProductCatalogIds': {scopeKey: defaultCatalogId},
      'defaultPriceTableId': defaultPriceTableId,
      'defaultPriceRegionId': _defaultPriceRegionId,
      'defaultProductCatalogId': defaultCatalogId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (legacyScopeKey != scopeKey) {
      final legacyDefaultPriceTableId =
          'pt_default_${normalizedTenantId}_$legacyScopeKey';
      final legacyDoc = await _firestore
          .collection('tabelas_preco')
          .doc(legacyDefaultPriceTableId)
          .get();
      final legacyData = legacyDoc.data() ?? <String, dynamic>{};
      final isLegacySystemDefault =
          (legacyData['origem'] ?? '').toString().trim().toLowerCase() ==
              'system' &&
          (legacyData['nome'] ?? '').toString().trim().toLowerCase() ==
              'tabela padrao';
      if (legacyDoc.exists && isLegacySystemDefault) {
        await legacyDoc.reference.delete();
      }

      await _firestore.collection('tenants').doc(normalizedTenantId).set({
        'defaultPriceTableIds': {legacyScopeKey: FieldValue.delete()},
        'defaultPriceRegionIds': {legacyScopeKey: FieldValue.delete()},
        'defaultProductCatalogIds': {legacyScopeKey: FieldValue.delete()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    final tenantDoc = await _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .get();
    final workspaceType = (tenantDoc.data()?['workspaceType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (workspaceType == 'rep_workspace') {
      final tenantDefaultPriceTableId = 'pt_default_$normalizedTenantId';
      await _firestore
          .collection('tabelas_preco')
          .doc(tenantDefaultPriceTableId)
          .delete();
      await _firestore.collection('tenants').doc(normalizedTenantId).set({
        'defaultPriceTableIds': {'tenant_default': FieldValue.delete()},
        'defaultPriceRegionIds': {'tenant_default': FieldValue.delete()},
        'defaultProductCatalogIds': {'tenant_default': FieldValue.delete()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> deleteRepresentedCompany({
    required String tenantId,
    required String companyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedCompanyId = companyId.trim();
    if (normalizedTenantId.isEmpty || normalizedCompanyId.isEmpty) {
      throw StateError('Dados invalidos para exclusao da representada.');
    }

    final tenantRef = _firestore.collection('tenants').doc(normalizedTenantId);
    final representedRef = _representedCompaniesCollection.doc(
      '${normalizedTenantId}_$normalizedCompanyId',
    );
    final scopeKey = _normalizeDefaultPricingScopeKey(normalizedCompanyId);
    final legacyScopeKey = normalizedCompanyId.replaceAll('/', '_');
    final defaultPriceTableId = 'pt_default_${normalizedTenantId}_$scopeKey';
    final legacyDefaultPriceTableId =
        'pt_default_${normalizedTenantId}_$legacyScopeKey';
    final defaultPriceTableRef = _firestore
        .collection('tabelas_preco')
        .doc(defaultPriceTableId);
    final legacyDefaultPriceTableRef = _firestore
        .collection('tabelas_preco')
        .doc(legacyDefaultPriceTableId);

    await _firestore.runTransaction((transaction) async {
      final tenantSnapshot = await transaction.get(tenantRef);
      final favoriteId =
          (tenantSnapshot.data()?['favoriteRepresentedCompanyId'] ?? '')
              .toString()
              .trim();

      transaction.delete(representedRef);
      transaction.delete(defaultPriceTableRef);
      if (legacyDefaultPriceTableId != defaultPriceTableId) {
        transaction.delete(legacyDefaultPriceTableRef);
      }

      final defaultPriceTableIdsPatch = <String, Object?>{
        scopeKey: FieldValue.delete(),
      };
      final defaultPriceRegionIdsPatch = <String, Object?>{
        scopeKey: FieldValue.delete(),
      };
      final defaultProductCatalogIdsPatch = <String, Object?>{
        scopeKey: FieldValue.delete(),
      };
      if (legacyScopeKey != scopeKey) {
        defaultPriceTableIdsPatch[legacyScopeKey] = FieldValue.delete();
        defaultPriceRegionIdsPatch[legacyScopeKey] = FieldValue.delete();
        defaultProductCatalogIdsPatch[legacyScopeKey] = FieldValue.delete();
      }

      transaction.set(tenantRef, {
        'defaultPriceTableIds': defaultPriceTableIdsPatch,
        'defaultPriceRegionIds': defaultPriceRegionIdsPatch,
        'defaultProductCatalogIds': defaultProductCatalogIdsPatch,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (favoriteId == normalizedCompanyId) {
        transaction.set(tenantRef, {
          'favoriteRepresentedCompanyId': '',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  Future<void> setFavoriteRepresentedCompany({
    required String tenantId,
    required String companyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedCompanyId = companyId.trim();
    if (normalizedTenantId.isEmpty || normalizedCompanyId.isEmpty) {
      throw StateError('Dados invalidos para favoritar representada.');
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set({
      'favoriteRepresentedCompanyId': normalizedCompanyId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
