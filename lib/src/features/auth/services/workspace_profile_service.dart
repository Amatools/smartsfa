import 'package:cloud_firestore/cloud_firestore.dart';

class WorkspaceProfileService {
  WorkspaceProfileService(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _representedCompaniesCollection =>
      _firestore.collection('tenant_represented_companies');

  Stream<Map<String, dynamic>?> watchWorkspace(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(null);
    }

    return _firestore.collection('tenants').doc(normalizedTenantId).snapshots().map(
      (doc) => doc.data(),
    );
  }

  Stream<List<String>> watchTextRuleList({
    required String tenantId,
    required String fieldName,
  }) {
    final normalizedTenantId = tenantId.trim();
    final normalizedFieldName = fieldName.trim();
    if (normalizedTenantId.isEmpty || normalizedFieldName.isEmpty) {
      return Stream.value(const <String>[]);
    }

    return _firestore.collection('tenants').doc(normalizedTenantId).snapshots().map((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      final raw = data[normalizedFieldName];
      if (raw is! List) {
        return const <String>[];
      }

      final result = <String>[];
      for (final item in raw) {
        final value = item?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          result.add(value);
        }
      }
      return result;
    });
  }

  Stream<List<Map<String, Object?>>> watchRepresentedCompanies(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <Map<String, Object?>>[]);
    }

    return _representedCompaniesCollection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map((snapshot) {
          final companies = snapshot.docs
              .map((doc) => doc.data().map((key, value) => MapEntry(key, value as Object?)))
              .toList(growable: false);
          companies.sort((a, b) {
            final aName = (a['nomeFantasia'] ?? '').toString().toLowerCase();
            final bName = (b['nomeFantasia'] ?? '').toString().toLowerCase();
            return aName.compareTo(bName);
          });
          return companies;
        });
  }

  Future<void> updateTextRuleList({
    required String tenantId,
    required String fieldName,
    required List<String> values,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedFieldName = fieldName.trim();
    if (normalizedTenantId.isEmpty || normalizedFieldName.isEmpty) {
      throw StateError('Dados invalidos para salvar regras textuais.');
    }

    final normalizedValues = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        normalizedFieldName: normalizedValues,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> updateWorkspaceProfile({
    required String tenantId,
    required String workspaceType,
    required Map<String, Object?> values,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedWorkspaceType = workspaceType.trim();
    if (normalizedTenantId.isEmpty || normalizedWorkspaceType.isEmpty) {
      throw StateError('Workspace invalido para atualizacao.');
    }

    final payload = <String, Object?>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    void writeIfPresent(String key, Object? value) {
      if (value == null) {
        return;
      }
      payload[key] = value;
    }

    writeIfPresent('nomeFantasia', _normalize(values['nomeFantasia']));
    writeIfPresent('contatoResponsavel', _normalize(values['contatoResponsavel']));
    writeIfPresent('telefoneComercial', _normalize(values['telefoneComercial']));
    writeIfPresent('emailComercial', _normalize(values['emailComercial']));
    writeIfPresent('website', _normalize(values['website']));
    writeIfPresent('segmento', _normalize(values['segmento']));
    writeIfPresent('regiaoAtuacao', _normalize(values['regiaoAtuacao']));
    writeIfPresent('marcasRepresentadas', _normalize(values['marcasRepresentadas']));
    writeIfPresent('logradouro', _normalize(values['logradouro']));
    writeIfPresent('numero', _normalize(values['numero']));
    writeIfPresent('complemento', _normalize(values['complemento']));
    writeIfPresent('bairro', _normalize(values['bairro']));
    writeIfPresent('cep', _normalize(values['cep']));
    writeIfPresent('cidade', _normalize(values['cidade']));
    writeIfPresent('uf', _normalize(values['uf']));

    if (normalizedWorkspaceType == 'seller_solo_workspace') {
      payload.remove('regiaoAtuacao');
      payload.remove('marcasRepresentadas');
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
          payload,
          SetOptions(merge: true),
        );
  }

  Future<void> setProductSyncFromErpEnabled({
    required String tenantId,
    required bool enabled,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Workspace invalido para configurar sincronizacao de produtos.');
    }

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        'productSyncFromErpEnabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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

    await _representedCompaniesCollection.doc(docId).set({
      'tenantId': normalizedTenantId,
      'companyId': normalizedId,
      'nomeFantasia': _normalize(values['nomeFantasia']),
      'razaoSocial': _normalize(values['razaoSocial']),
      'cnpj': _normalize(values['cnpj']),
      'cep': _normalize(values['cep']),
      'logradouro': _normalize(values['logradouro']),
      'numero': _normalize(values['numero']),
      'logoUrl': _normalize(values['logoUrl']),
      'contato': _normalize(values['contato']),
      'telefone': _normalize(values['telefone']),
      'email': _normalize(values['email']),
      'cidade': _normalize(values['cidade']),
      'uf': _normalize(values['uf']).toUpperCase(),
      'segmento': _normalize(values['segmento']),
      'ativo': values['ativo'] != false,
      'updatedAt': nowIso,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    final representedRef =
        _representedCompaniesCollection.doc('${normalizedTenantId}_$normalizedCompanyId');

    await _firestore.runTransaction((transaction) async {
      final tenantSnapshot = await transaction.get(tenantRef);
      final favoriteId =
          (tenantSnapshot.data()?['favoriteRepresentedCompanyId'] ?? '').toString().trim();

      transaction.delete(representedRef);
      if (favoriteId == normalizedCompanyId) {
        transaction.set(
          tenantRef,
          {
            'favoriteRepresentedCompanyId': '',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
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

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        'favoriteRepresentedCompanyId': normalizedCompanyId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
  String _normalize(Object? value) {
    return value?.toString().trim() ?? '';
  }
}
