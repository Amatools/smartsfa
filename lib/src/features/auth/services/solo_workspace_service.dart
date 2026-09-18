import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SoloWorkspaceService {
  SoloWorkspaceService(this._firestore);

  final FirebaseFirestore _firestore;

  static const List<String> _collectionsWithScopeMigration = [
    'clientes',
    'pedidos',
  ];

  static const List<String> _collectionsWithTenantOnlyMigration = [
    'cliente_pre_cadastros',
    'produtos',
  ];
  static const String _defaultPriceRegionId = 'default';
  static const String _defaultPriceTableName = 'Tabela padrao';

  Future<SoloWorkspaceResult> bootstrapOwnerWorkspace(User user) async {
    return createOwnerWorkspace(
      user: user,
      plan: OnboardingPlan.solo,
      workspaceName: _soloTenantName(user),
      workspaceType: WorkspaceType.sellerSoloWorkspace,
    );
  }

  Future<SoloWorkspaceResult> createOwnerWorkspace({
    required User user,
    required OnboardingPlan plan,
    required String workspaceName,
    WorkspaceType? workspaceType,
    String? cnpj,
    bool clearPendingRequest = false,
  }) async {
    final normalizedName = workspaceName.trim();
    if (normalizedName.isEmpty) {
      throw StateError('Informe um nome para o workspace.');
    }

    final effectiveWorkspaceType = workspaceType ?? WorkspaceType.fromPlan(plan);
    final userRef = _firestore.collection('usuarios').doc(user.uid);
    final existingUserDoc = await userRef.get();
    final accountContractLock = _readAccountContractLock(existingUserDoc.data());

    await _assertWorkspaceCreationAllowed(
      user: user,
      workspaceType: effectiveWorkspaceType,
      accountContractLock: accountContractLock,
    );

    final initialRole = _initialRoleForWorkspaceType(effectiveWorkspaceType);
    final scope = _roleScope(role: initialRole, uid: user.uid);

    final tenantId = _tenantIdForPlan(
      uid: user.uid,
      plan: plan,
      workspaceName: normalizedName,
    );
    final tenantName = normalizedName;
    final membershipId = '${tenantId}_${user.uid}';

    final tenantRef = _firestore.collection('tenants').doc(tenantId);
    final membershipRef = _firestore.collection('tenant_memberships').doc(membershipId);
    final requestRef = _firestore.collection('solicitacoes_acesso').doc(user.uid);

    await _firestore.runTransaction((tx) async {
      tx.set(
        tenantRef,
        {
          'tenantId': tenantId,
          'slug': tenantId,
          'nomeFantasia': tenantName,
          'ativo': true,
          'operationMode': 'manual',
          'erpProvider': 'none',
          'plan': plan.value,
          'workspaceType': effectiveWorkspaceType.value,
          'hierarchyModel': effectiveWorkspaceType.hierarchyModel,
          'allowInvitations': effectiveWorkspaceType.allowsInvitations,
          'ownerUid': user.uid,
          if (cnpj != null && cnpj.trim().isNotEmpty)
            if (effectiveWorkspaceType == WorkspaceType.brandOwnerWorkspace)
              'cnpj': cnpj.trim()
            else
              'representedCompanyDocument': cnpj.trim(),
          'cnpjBinding': effectiveWorkspaceType == WorkspaceType.brandOwnerWorkspace
              ? 'owner_legal_entity'
              : 'informational_only',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        userRef,
        {
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName': user.displayName ?? (user.email ?? user.uid),
          'platformRole': 'none',
          'ativoGlobal': true,
          'accountContractLock': effectiveWorkspaceType ==
                  WorkspaceType.brandOwnerWorkspace
              ? AccountContractLock.enterpriseOnly.value
              : accountContractLock.value,
          'defaultTenantId': tenantId,
          'lastSelectedTenantId': tenantId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        membershipRef,
        {
          'membershipId': membershipId,
          'tenantId': tenantId,
          'uid': user.uid,
          'role': initialRole,
          'ativo': true,
          'defaultTenant': true,
          'state': 'active',
          'ownerId': scope.ownerId,
          'gerenteId': scope.gerenteId,
          'representanteId': scope.representanteId,
          'vendedorId': scope.vendedorId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (clearPendingRequest) {
        // Only remove an existing request doc; deleting a missing doc can
        // fail under Firestore rules for a first-time account.
        tx.delete(requestRef);
      }
    });

    await _syncDefaultTenantContext(
      uid: user.uid,
      selectedMembershipId: membershipId,
      selectedTenantId: tenantId,
    );
    await _bootstrapDefaultCatalogAndPricing(
      tenantId: tenantId,
      workspaceType: effectiveWorkspaceType,
    );

    return SoloWorkspaceResult(
      tenantId: tenantId,
      tenantName: tenantName,
      membershipId: membershipId,
    );
  }

  Future<UpgradeToRepResult> upgradeIndividualToRepWorkspace({
    required User user,
    required String workspaceName,
    String? representedCompanyDocument,
  }) async {
    final normalizedName = workspaceName.trim();
    if (normalizedName.isEmpty) {
      throw StateError('Informe um nome para o workspace de Representacoes.');
    }

    final activeMemberships = await _firestore
        .collection('tenant_memberships')
        .where('uid', isEqualTo: user.uid)
        .where('ativo', isEqualTo: true)
        .get();

    DocumentSnapshot<Map<String, dynamic>>? sourceMembership;
    for (final membership in activeMemberships.docs) {
      final data = membership.data();
      final tenantId = (data['tenantId'] ?? '').toString();
      final role = (data['role'] ?? '').toString().trim().toLowerCase();
      final state = (data['state'] ?? 'active').toString().trim().toLowerCase();
      if (tenantId.startsWith('solo_') && role == 'vendedor' && state == 'active') {
        sourceMembership = membership;
        break;
      }
    }

    if (sourceMembership == null) {
      throw StateError(
        'Upgrade disponivel apenas para contas com workspace Individual ativo.',
      );
    }

    final sourceTenantId = (sourceMembership.data()?['tenantId'] ?? '').toString().trim();
    if (sourceTenantId.isEmpty) {
      throw StateError('Nao foi possivel identificar o tenant Individual de origem.');
    }

    final targetTenantId = _tenantIdForPlan(
      uid: user.uid,
      plan: OnboardingPlan.team,
      workspaceName: normalizedName,
    );
    final targetMembershipId = '${targetTenantId}_${user.uid}';

    final targetTenantRef = _firestore.collection('tenants').doc(targetTenantId);
    final targetMembershipRef = _firestore
        .collection('tenant_memberships')
        .doc(targetMembershipId);
    final userRef = _firestore.collection('usuarios').doc(user.uid);
    final sourceTenantRef = _firestore.collection('tenants').doc(sourceTenantId);
    final sourceMembershipRef = _firestore
        .collection('tenant_memberships')
        .doc(sourceMembership.id);

    await _firestore.runTransaction((tx) async {
      tx.set(
        targetTenantRef,
        {
          'tenantId': targetTenantId,
          'slug': targetTenantId,
          'nomeFantasia': normalizedName,
          'ativo': true,
          'operationMode': 'manual',
          'erpProvider': 'none',
          'plan': OnboardingPlan.team.value,
          'workspaceType': WorkspaceType.repWorkspace.value,
          'hierarchyModel': WorkspaceType.repWorkspace.hierarchyModel,
          'allowInvitations': WorkspaceType.repWorkspace.allowsInvitations,
          'ownerUid': user.uid,
          if (representedCompanyDocument != null &&
              representedCompanyDocument.trim().isNotEmpty)
            'representedCompanyDocument': representedCompanyDocument.trim(),
          'cnpjBinding': 'informational_only',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        targetMembershipRef,
        {
          'membershipId': targetMembershipId,
          'tenantId': targetTenantId,
          'uid': user.uid,
          'role': 'owner',
          'ativo': true,
          'defaultTenant': true,
          'state': 'active',
          'ownerId': user.uid,
          'gerenteId': '',
          'representanteId': '',
          'vendedorId': '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        sourceMembershipRef,
        {
          'defaultTenant': false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        sourceTenantRef,
        {
          'supersededByTenantId': targetTenantId,
          'upgradedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        userRef,
        {
          'accountContractLock': AccountContractLock.flexible.value,
          'defaultTenantId': targetTenantId,
          'lastSelectedTenantId': targetTenantId,
          'upgradedFromTenantId': sourceTenantId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    var migratedScopedDocs = 0;
    var migratedTenantOnlyDocs = 0;

    for (final collection in _collectionsWithScopeMigration) {
      migratedScopedDocs += await _migrateScopedCollection(
        collection: collection,
        sourceTenantId: sourceTenantId,
        targetTenantId: targetTenantId,
        ownerUid: user.uid,
      );
    }

    for (final collection in _collectionsWithTenantOnlyMigration) {
      migratedTenantOnlyDocs += await _migrateTenantOnlyCollection(
        collection: collection,
        sourceTenantId: sourceTenantId,
        targetTenantId: targetTenantId,
      );
    }

    await _bootstrapDefaultCatalogAndPricing(
      tenantId: targetTenantId,
      workspaceType: WorkspaceType.repWorkspace,
    );

    return UpgradeToRepResult(
      sourceTenantId: sourceTenantId,
      targetTenantId: targetTenantId,
      targetMembershipId: targetMembershipId,
      migratedScopedDocs: migratedScopedDocs,
      migratedTenantOnlyDocs: migratedTenantOnlyDocs,
    );
  }

  Future<void> _bootstrapDefaultCatalogAndPricing({
    required String tenantId,
    required WorkspaceType workspaceType,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return;
    }

    if (workspaceType == WorkspaceType.repWorkspace) {
      return;
    }

    final defaultPriceTableId = 'pt_default_$normalizedTenantId';
    const scopeKey = 'tenant_default';
    final now = DateTime.now().toUtc().toIso8601String();

    await _firestore.collection('tabelas_preco').doc(defaultPriceTableId).set(
      {
        'id': defaultPriceTableId,
        'tenantId': normalizedTenantId,
        'nome': _defaultPriceTableName,
        'scopeType': 'general',
        'scopeLabel': 'Tabela principal da conta',
        'scopeIndex': const <String>['general', _defaultPriceRegionId],
        'origem': 'system',
        'status': 'ativo',
        'linkedEntityId': null,
        'rowCount': 0,
        'createdAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    await _firestore.collection('tenants').doc(normalizedTenantId).set(
      {
        'defaultPriceTableIds': {scopeKey: defaultPriceTableId},
        'defaultPriceRegionIds': {scopeKey: _defaultPriceRegionId},
        'defaultProductCatalogIds': {
          scopeKey: 'products_default_${normalizedTenantId}_$scopeKey',
        },
        // Backward compatibility for legacy readers.
        'defaultPriceTableId': defaultPriceTableId,
        'defaultPriceRegionId': _defaultPriceRegionId,
        'defaultProductCatalogId': 'products_default',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<int> _migrateScopedCollection({
    required String collection,
    required String sourceTenantId,
    required String targetTenantId,
    required String ownerUid,
  }) async {
    final snapshot = await _firestore
        .collection(collection)
        .where('tenantId', isEqualTo: sourceTenantId)
        .get();

    if (snapshot.docs.isEmpty) {
      return 0;
    }

    var migrated = 0;
    WriteBatch batch = _firestore.batch();
    var opCount = 0;

    for (final doc in snapshot.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['tenantId'] = targetTenantId;
      data['ownerId'] = ownerUid;
      data['gerenteId'] = '';
      data['representanteId'] = '';
      data['vendedorId'] = '';
      data['updatedAt'] = FieldValue.serverTimestamp();
      final targetDocId = '${doc.id}_to_$targetTenantId';

      batch.set(
        _firestore.collection(collection).doc(targetDocId),
        data,
        SetOptions(merge: true),
      );

      migrated += 1;
      opCount += 1;

      if (opCount >= 350) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    if (opCount > 0) {
      await batch.commit();
    }

    return migrated;
  }

  Future<int> _migrateTenantOnlyCollection({
    required String collection,
    required String sourceTenantId,
    required String targetTenantId,
  }) async {
    final snapshot = await _firestore
        .collection(collection)
        .where('tenantId', isEqualTo: sourceTenantId)
        .get();

    if (snapshot.docs.isEmpty) {
      return 0;
    }

    var migrated = 0;
    WriteBatch batch = _firestore.batch();
    var opCount = 0;

    for (final doc in snapshot.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['tenantId'] = targetTenantId;
      data['updatedAt'] = FieldValue.serverTimestamp();
      final targetDocId = '${doc.id}_to_$targetTenantId';

      batch.set(
        _firestore.collection(collection).doc(targetDocId),
        data,
        SetOptions(merge: true),
      );

      migrated += 1;
      opCount += 1;

      if (opCount >= 350) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    if (opCount > 0) {
      await batch.commit();
    }

    return migrated;
  }

  String _soloTenantName(User user) {
    final preferred = (user.displayName ?? '').trim();
    if (preferred.isNotEmpty) {
      return '$preferred (Solo)';
    }

    final email = (user.email ?? '').trim();
    if (email.isNotEmpty) {
      return '${email.split('@').first} (Solo)';
    }

    return 'Workspace Solo';
  }

  String _tenantIdForPlan({
    required String uid,
    required OnboardingPlan plan,
    required String workspaceName,
  }) {
    if (plan == OnboardingPlan.solo) {
      return 'solo_$uid';
    }

    final slug = _slugify(workspaceName);
    return 'self_${uid}_$slug';
  }

  AccountContractLock _readAccountContractLock(Map<String, dynamic>? data) {
    final rawValue = (data?['accountContractLock'] ?? '').toString().trim();
    return AccountContractLock.fromValue(rawValue);
  }

  Future<void> _assertWorkspaceCreationAllowed({
    required User user,
    required WorkspaceType workspaceType,
    required AccountContractLock accountContractLock,
  }) async {
    final memberships = await _firestore
        .collection('tenant_memberships')
        .where('uid', isEqualTo: user.uid)
        .where('ativo', isEqualTo: true)
        .get();

    final activeMemberships = memberships.docs.where((doc) {
      final data = doc.data();
      final state = (data['state'] ?? 'active').toString().trim().toLowerCase();
      return state == 'active';
    }).toList();

    if (activeMemberships.isNotEmpty) {
      throw StateError(
        'Sua conta ja esta vinculada a um workspace ativo. Mudanca de tipo/plano deve ser feita por upgrade, sem criar novo workspace paralelo.',
      );
    }

    if (accountContractLock == AccountContractLock.enterpriseOnly &&
        workspaceType != WorkspaceType.brandOwnerWorkspace) {
      throw StateError(
        'Conta enterprise e exclusiva. Use outro login para criar workspace vendedor solo ou de representacao.',
      );
    }
  }

  Future<void> _syncDefaultTenantContext({
    required String uid,
    required String selectedMembershipId,
    required String selectedTenantId,
  }) async {
    final memberships = await _firestore
        .collection('tenant_memberships')
        .where('uid', isEqualTo: uid)
        .get();

    final batch = _firestore.batch();
    for (final doc in memberships.docs) {
      batch.set(
        doc.reference,
        {'defaultTenant': doc.id == selectedMembershipId},
        SetOptions(merge: true),
      );
    }

    batch.set(
      _firestore.collection('usuarios').doc(uid),
      {
        'defaultTenantId': selectedTenantId,
        'lastSelectedTenantId': selectedTenantId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  String _initialRoleForWorkspaceType(WorkspaceType type) {
    switch (type) {
      case WorkspaceType.sellerSoloWorkspace:
        return 'vendedor';
      case WorkspaceType.repWorkspace:
        return 'owner';
      case WorkspaceType.brandOwnerWorkspace:
        return 'owner';
    }
  }

  _RoleScope _roleScope({
    required String role,
    required String uid,
  }) {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'owner') {
      return const _RoleScope(
        ownerId: '',
        gerenteId: '',
        representanteId: '',
        vendedorId: '',
      ).copyWith(ownerId: uid);
    }

    if (normalized == 'gerente') {
      return const _RoleScope(
        ownerId: '',
        gerenteId: '',
        representanteId: '',
        vendedorId: '',
      ).copyWith(gerenteId: uid);
    }

    if (normalized == 'representante') {
      return const _RoleScope(
        ownerId: '',
        gerenteId: '',
        representanteId: '',
        vendedorId: '',
      ).copyWith(representanteId: uid);
    }

    return const _RoleScope(
      ownerId: '',
      gerenteId: '',
      representanteId: '',
      vendedorId: '',
    ).copyWith(vendedorId: uid);
  }

  String _slugify(String value) {
    final lowered = value.toLowerCase();
    final slug = lowered
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    if (slug.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch.toString();
    }

    if (slug.length <= 48) {
      return slug;
    }

    return slug.substring(0, 48);
  }
}

enum OnboardingPlan {
  solo('solo'),
  team('team'),
  enterprise('enterprise');

  const OnboardingPlan(this.value);
  final String value;
}

enum WorkspaceType {
  sellerSoloWorkspace('seller_solo_workspace', 'seller_only', false),
  repWorkspace('rep_workspace', 'full_chain', true),
  brandOwnerWorkspace('brand_owner_workspace', 'full_chain', true);

  const WorkspaceType(this.value, this.hierarchyModel, this.allowsInvitations);

  final String value;
  final String hierarchyModel;
  final bool allowsInvitations;

  static WorkspaceType fromPlan(OnboardingPlan plan) {
    switch (plan) {
      case OnboardingPlan.solo:
        return WorkspaceType.sellerSoloWorkspace;
      case OnboardingPlan.team:
        return WorkspaceType.repWorkspace;
      case OnboardingPlan.enterprise:
        return WorkspaceType.brandOwnerWorkspace;
    }
  }
}

enum AccountContractLock {
  flexible('flexible'),
  enterpriseOnly('enterprise_only');

  const AccountContractLock(this.value);

  final String value;

  static AccountContractLock fromValue(String value) {
    switch (value) {
      case 'enterprise_only':
        return AccountContractLock.enterpriseOnly;
      default:
        return AccountContractLock.flexible;
    }
  }
}

class _RoleScope {
  const _RoleScope({
    required this.ownerId,
    required this.gerenteId,
    required this.representanteId,
    required this.vendedorId,
  });

  final String ownerId;
  final String gerenteId;
  final String representanteId;
  final String vendedorId;

  _RoleScope copyWith({
    String? ownerId,
    String? gerenteId,
    String? representanteId,
    String? vendedorId,
  }) {
    return _RoleScope(
      ownerId: ownerId ?? this.ownerId,
      gerenteId: gerenteId ?? this.gerenteId,
      representanteId: representanteId ?? this.representanteId,
      vendedorId: vendedorId ?? this.vendedorId,
    );
  }
}

class SoloWorkspaceResult {
  const SoloWorkspaceResult({
    required this.tenantId,
    required this.tenantName,
    required this.membershipId,
  });

  final String tenantId;
  final String tenantName;
  final String membershipId;
}

class UpgradeToRepResult {
  const UpgradeToRepResult({
    required this.sourceTenantId,
    required this.targetTenantId,
    required this.targetMembershipId,
    required this.migratedScopedDocs,
    required this.migratedTenantOnlyDocs,
  });

  final String sourceTenantId;
  final String targetTenantId;
  final String targetMembershipId;
  final int migratedScopedDocs;
  final int migratedTenantOnlyDocs;
}
