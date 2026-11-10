part of 'workspace_profile_service.dart';

mixin _WorkspaceProfileCampaignListsMixin {
  FirebaseFirestore get _firestore;

  static const String _campaignRegionId = 'default';

  Stream<List<CampaignProductList>> watchCampaignProductLists({
    required String tenantId,
    required String? representedCompanyId,
    required OrderItemSourceType sourceType,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <CampaignProductList>[]);
    }

    final scopeKey = _scopeKey(
      _effectiveRepresentedCompanyId(normalizedTenantId, representedCompanyId),
    );

    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .snapshots()
        .map((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          return _readCampaignListsForScope(
            data: data,
            scopeKey: scopeKey,
            sourceType: sourceType,
          );
        });
  }

  Future<List<CampaignProductList>> fetchCampaignProductLists({
    required String tenantId,
    required String? representedCompanyId,
    required OrderItemSourceType sourceType,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const <CampaignProductList>[];
    }

    final scopeKey = _scopeKey(
      _effectiveRepresentedCompanyId(normalizedTenantId, representedCompanyId),
    );

    final doc = await _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .get();
    final data = doc.data() ?? const <String, dynamic>{};
    return _readCampaignListsForScope(
      data: data,
      scopeKey: scopeKey,
      sourceType: sourceType,
    );
  }

  Future<CampaignProductList> createCampaignProductList({
    required String tenantId,
    required String? representedCompanyId,
    required OrderItemSourceType sourceType,
    required String name,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw StateError('Informe um nome para a lista.');
    }

    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Tenant invalido para criar lista.');
    }

    final effectiveRepresentedCompanyId = _effectiveRepresentedCompanyId(
      normalizedTenantId,
      representedCompanyId,
    );

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final generatedId = 'cpl_${DateTime.now().microsecondsSinceEpoch}';
    final created = CampaignProductList(
      id: generatedId,
      name: normalizedName,
      sourceType: sourceType,
      items: const <CampaignProductListItem>[],
      active: true,
      priceTableId: sourceType == OrderItemSourceType.promotion
          ? _promotionPriceTableId(
              tenantId: normalizedTenantId,
              representedCompanyId: effectiveRepresentedCompanyId,
            )
          : null,
      createdAtIso: nowIso,
      updatedAtIso: nowIso,
    );

    await upsertCampaignProductList(
      tenantId: normalizedTenantId,
      representedCompanyId: representedCompanyId,
      list: created,
    );

    return created;
  }

  Future<void> upsertCampaignProductList({
    required String tenantId,
    required String? representedCompanyId,
    required CampaignProductList list,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Dados invalidos para salvar lista.');
    }
    if (list.sourceType == OrderItemSourceType.none) {
      throw StateError('Tipo de lista invalido.');
    }

    final normalizedId = list.id.trim();
    if (normalizedId.isEmpty) {
      throw StateError('Lista sem identificador.');
    }

    final normalizedName = list.name.trim();
    if (normalizedName.isEmpty) {
      throw StateError('Nome da lista nao pode ficar vazio.');
    }

    final effectiveRepresentedCompanyId = _effectiveRepresentedCompanyId(
      normalizedTenantId,
      representedCompanyId,
    );

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final payloadList = list.copyWith(
      id: normalizedId,
      name: normalizedName,
      items: _normalizeCampaignItems(
        values: list.items,
        sourceType: list.sourceType,
      ),
      updatedAtIso: nowIso,
      createdAtIso: (list.createdAtIso ?? '').trim().isEmpty
          ? nowIso
          : list.createdAtIso,
      priceTableId: list.sourceType == OrderItemSourceType.promotion
          ? _promotionPriceTableId(
              tenantId: normalizedTenantId,
              representedCompanyId: effectiveRepresentedCompanyId,
            )
          : null,
    );

    final scopeKey = _scopeKey(effectiveRepresentedCompanyId);

    final tenantRef = _firestore.collection('tenants').doc(normalizedTenantId);

    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(tenantRef);
      final data = doc.data() ?? const <String, dynamic>{};
      final root = _copyRootMap(data['representedCampaignProductLists']);
      final scoped = _copyScopeMap(root[scopeKey]);
      final field = _campaignSourceField(payloadList.sourceType);

      final existing = _copyListMaps(scoped[field]);
      var replaced = false;
      final next = <Map<String, Object?>>[];
      for (final item in existing) {
        final currentId = (item['id'] ?? '').toString().trim();
        if (currentId == payloadList.id) {
          next.add(payloadList.toMap());
          replaced = true;
        } else {
          next.add(item);
        }
      }
      if (!replaced) {
        next.add(payloadList.toMap());
      }

      next.sort((a, b) {
        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

      scoped[field] = next;
      root[scopeKey] = scoped;

      tx.set(tenantRef, {
        'representedCampaignProductLists': root,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    if (payloadList.sourceType == OrderItemSourceType.promotion) {
      await _syncPromotionPriceTableForScope(
        tenantId: normalizedTenantId,
        representedCompanyId: effectiveRepresentedCompanyId,
      );
    }
  }

  Future<void> deleteCampaignProductList({
    required String tenantId,
    required String? representedCompanyId,
    required OrderItemSourceType sourceType,
    required String listId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedListId = listId.trim();
    if (normalizedTenantId.isEmpty || normalizedListId.isEmpty) {
      throw StateError('Dados invalidos para excluir lista.');
    }

    final effectiveRepresentedCompanyId = _effectiveRepresentedCompanyId(
      normalizedTenantId,
      representedCompanyId,
    );
    final scopeKey = _scopeKey(effectiveRepresentedCompanyId);
    final field = _campaignSourceField(sourceType);
    final tenantRef = _firestore.collection('tenants').doc(normalizedTenantId);

    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(tenantRef);
      final data = doc.data() ?? const <String, dynamic>{};
      final root = _copyRootMap(data['representedCampaignProductLists']);
      final scoped = _copyScopeMap(root[scopeKey]);
      final existing = _copyListMaps(scoped[field]);
      final next = existing
          .where((item) {
            final id = (item['id'] ?? '').toString().trim();
            return id != normalizedListId;
          })
          .toList(growable: false);

      scoped[field] = next;
      root[scopeKey] = scoped;

      tx.set(tenantRef, {
        'representedCampaignProductLists': root,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    if (sourceType == OrderItemSourceType.promotion) {
      await _syncPromotionPriceTableForScope(
        tenantId: normalizedTenantId,
        representedCompanyId: effectiveRepresentedCompanyId,
      );
    }
  }

  List<CampaignProductList> _readCampaignListsForScope({
    required Map<String, dynamic> data,
    required String scopeKey,
    required OrderItemSourceType sourceType,
  }) {
    if (sourceType == OrderItemSourceType.none) {
      return const <CampaignProductList>[];
    }

    final rootRaw = data['representedCampaignProductLists'];
    if (rootRaw is! Map) {
      return const <CampaignProductList>[];
    }

    final scopedRaw = rootRaw[scopeKey] ?? rootRaw['tenant_default'];
    if (scopedRaw is! Map) {
      return const <CampaignProductList>[];
    }

    final listRaw = scopedRaw[_campaignSourceField(sourceType)];
    if (listRaw is! List) {
      return const <CampaignProductList>[];
    }

    final parsed = <CampaignProductList>[];
    for (final item in listRaw) {
      if (item is! Map) {
        continue;
      }
      final id = (item['id'] ?? '').toString().trim();
      final name = (item['name'] ?? '').toString().trim();
      if (id.isEmpty || name.isEmpty) {
        continue;
      }

      final parsedItems = _readCampaignItems(
        item: item,
        sourceType: sourceType,
      );

      parsed.add(
        CampaignProductList(
          id: id,
          name: name,
          sourceType: sourceType,
          items: parsedItems,
          active: item['active'] != false,
          validFromIso: _readOptionalIsoField(item['validFrom']),
          validUntilIso: _readOptionalIsoField(item['validUntil']),
          priceTableId: _readOptionalIsoField(item['priceTableId']),
          createdAtIso: _readOptionalIsoField(item['createdAt']),
          updatedAtIso: _readOptionalIsoField(item['updatedAt']),
        ),
      );
    }

    parsed.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return parsed;
  }

  List<CampaignProductListItem> _readCampaignItems({
    required Map item,
    required OrderItemSourceType sourceType,
  }) {
    final rawItems = item['items'];
    if (rawItems is List) {
      final parsed = <CampaignProductListItem>[];
      for (final raw in rawItems) {
        if (raw is! Map) {
          continue;
        }
        final productId = (raw['productId'] ?? '').toString().trim();
        if (productId.isEmpty) {
          continue;
        }
        final promotionPrice = sourceType == OrderItemSourceType.promotion
            ? _readPromotionPrice(raw['promotionPrice'])
            : null;
        parsed.add(
          CampaignProductListItem(
            productId: productId,
            promotionPrice: promotionPrice,
          ),
        );
      }
      return _normalizeCampaignItems(values: parsed, sourceType: sourceType);
    }

    final rawIds = item['productIds'];
    if (rawIds is! List) {
      return const <CampaignProductListItem>[];
    }

    final fallback = <CampaignProductListItem>[];
    for (final value in rawIds) {
      final productId = value?.toString().trim() ?? '';
      if (productId.isEmpty) {
        continue;
      }
      fallback.add(
        CampaignProductListItem(productId: productId, promotionPrice: null),
      );
    }
    return _normalizeCampaignItems(values: fallback, sourceType: sourceType);
  }

  List<CampaignProductListItem> _normalizeCampaignItems({
    required Iterable<CampaignProductListItem> values,
    required OrderItemSourceType sourceType,
  }) {
    final normalized = <CampaignProductListItem>[];
    final seen = <String>{};
    for (final entry in values) {
      final productId = entry.productId.trim();
      if (productId.isEmpty) {
        continue;
      }
      if (!seen.add(productId)) {
        continue;
      }
      final promotionPrice = sourceType == OrderItemSourceType.promotion
          ? _readPromotionPrice(entry.promotionPrice)
          : null;
      normalized.add(
        CampaignProductListItem(
          productId: productId,
          promotionPrice: promotionPrice,
        ),
      );
    }
    normalized.sort((a, b) => a.productId.compareTo(b.productId));
    return normalized;
  }

  double? _readPromotionPrice(Object? value) {
    if (value == null) {
      return null;
    }
    final parsed = _toDouble(value);
    if (parsed.isNaN || parsed.isInfinite) {
      return null;
    }
    if (parsed < 0) {
      return null;
    }
    return parsed;
  }

  String? _readOptionalIsoField(Object? value) {
    final normalized = (value ?? '').toString().trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String _campaignSourceField(OrderItemSourceType sourceType) {
    switch (sourceType) {
      case OrderItemSourceType.promotion:
        return 'promotionLists';
      case OrderItemSourceType.highlight:
        return 'highlightLists';
      case OrderItemSourceType.none:
        throw StateError('Tipo de lista invalido.');
    }
  }

  Future<void> _syncPromotionPriceTableForScope({
    required String tenantId,
    required String? representedCompanyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return;
    }

    final effectiveRepresentedCompanyId = _effectiveRepresentedCompanyId(
      normalizedTenantId,
      representedCompanyId,
    );
    final scopeKey = _scopeKey(effectiveRepresentedCompanyId);
    final represented = (effectiveRepresentedCompanyId ?? '').trim();

    final tenantRef = _firestore.collection('tenants').doc(normalizedTenantId);
    final tenantDoc = await tenantRef.get();
    final data = tenantDoc.data() ?? const <String, dynamic>{};

    final promotionLists = _readCampaignListsForScope(
      data: data,
      scopeKey: scopeKey,
      sourceType: OrderItemSourceType.promotion,
    );

    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();

    final activePromotionLists = promotionLists
        .where((list) => _isCampaignListActiveForMoment(list, now))
        .toList(growable: false);

    final bestByProductId = <String, _PromotionPriceCandidate>{};
    for (final list in activePromotionLists) {
      final listUpdatedAt =
          DateTime.tryParse((list.updatedAtIso ?? '').trim())?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final validFrom = _parseIsoDate(list.validFromIso);
      final validUntil = _parseIsoDate(list.validUntilIso);

      for (final item in list.items) {
        final productId = item.productId.trim();
        final price = item.promotionPrice;
        if (productId.isEmpty || price == null) {
          continue;
        }

        final candidate = _PromotionPriceCandidate(
          price: price,
          validFrom: validFrom,
          validUntil: validUntil,
          sourceListId: list.id,
          sourceListName: list.name,
          listUpdatedAt: listUpdatedAt,
        );

        final current = bestByProductId[productId];
        if (current == null ||
            candidate.price < current.price ||
            (candidate.price == current.price &&
                candidate.listUpdatedAt.isAfter(current.listUpdatedAt))) {
          bestByProductId[productId] = candidate;
        }
      }
    }

    final priceTableId = _promotionPriceTableId(
      tenantId: normalizedTenantId,
      representedCompanyId: effectiveRepresentedCompanyId,
    );

    final tablePayload = <String, Object?>{
      'id': priceTableId,
      'tenantId': normalizedTenantId,
      'nome': 'Tabela Promocoes',
      'scopeType': 'promotion_campaign',
      'scopeLabel': 'Promocoes consolidadas',
      'scopeIndex': <String>[
        'campaign',
        'promotion',
        'aggregated',
        if (represented.isNotEmpty) represented,
      ],
      'origem': 'campaign_promotion',
      'status': bestByProductId.isEmpty ? 'inativo' : 'ativo',
      'linkedEntityId': represented.isEmpty ? null : represented,
      'rowCount': bestByProductId.length,
      'validFrom': null,
      'validUntil': null,
      'aggregatedFromListCount': activePromotionLists.length,
      'updatedAt': nowIso,
      'deletedAt': bestByProductId.isEmpty ? nowIso : null,
    };

    await _cleanupLegacyPromotionTablesForScope(
      tenantId: normalizedTenantId,
      representedCompanyId: effectiveRepresentedCompanyId,
      activePriceTableId: priceTableId,
      nowIso: nowIso,
    );

    await _firestore
        .collection('tabelas_preco')
        .doc(priceTableId)
        .set(tablePayload, SetOptions(merge: true));

    final desiredByDocId = <String, Map<String, Object?>>{};
    bestByProductId.forEach((productId, candidate) {
      final docId = _promotionBasePriceDocId(
        priceTableId: priceTableId,
        productId: productId,
      );
      desiredByDocId[docId] = <String, Object?>{
        'id': docId,
        'tenantId': normalizedTenantId,
        'productId': productId,
        'priceTableId': priceTableId,
        'regionId': _campaignRegionId,
        'basePrice': candidate.price,
        'status': 'active',
        'currencyCode': 'BRL',
        'validFrom': candidate.validFrom?.toIso8601String(),
        'validUntil': candidate.validUntil?.toIso8601String(),
        'sourceListId': candidate.sourceListId,
        'sourceListLabel': candidate.sourceListName,
        'updatedAt': nowIso,
      };
    });

    final existing = await _firestore
        .collection('product_base_prices')
        .where('tenantId', isEqualTo: normalizedTenantId)
        .where('priceTableId', isEqualTo: priceTableId)
        .get();

    var batch = _firestore.batch();
    var pending = 0;

    Future<void> flushBatchIfNeeded({required bool force}) async {
      if (!force && pending < 450) {
        return;
      }
      if (pending == 0) {
        return;
      }
      await batch.commit();
      batch = _firestore.batch();
      pending = 0;
    }

    for (final doc in existing.docs) {
      if (desiredByDocId.containsKey(doc.id)) {
        continue;
      }
      batch.delete(doc.reference);
      pending += 1;
      await flushBatchIfNeeded(force: false);
    }

    desiredByDocId.forEach((docId, payload) {
      final ref = _firestore.collection('product_base_prices').doc(docId);
      batch.set(ref, payload, SetOptions(merge: true));
      pending += 1;
    });
    await flushBatchIfNeeded(force: true);
  }

  Future<void> _cleanupLegacyPromotionTablesForScope({
    required String tenantId,
    required String? representedCompanyId,
    required String activePriceTableId,
    required String nowIso,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedActiveTableId = activePriceTableId.trim();
    if (normalizedTenantId.isEmpty || normalizedActiveTableId.isEmpty) {
      return;
    }

    final represented = (representedCompanyId ?? '').trim();

    final tablesSnapshot = await _firestore
        .collection('tabelas_preco')
        .where('tenantId', isEqualTo: normalizedTenantId)
        .where('origem', isEqualTo: 'campaign_promotion')
        .get();

    final legacyTableIds = <String>[];
    for (final doc in tablesSnapshot.docs) {
      final tableId = doc.id.trim();
      if (tableId.isEmpty || tableId == normalizedActiveTableId) {
        continue;
      }

      final data = doc.data();
      final scopeType = (data['scopeType'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (scopeType != 'promotion_campaign') {
        continue;
      }

      final linkedEntityId = (data['linkedEntityId'] ?? '').toString().trim();
      if (linkedEntityId != represented) {
        continue;
      }

      legacyTableIds.add(tableId);

      await doc.reference.set({
        'status': 'inativo',
        'rowCount': 0,
        'deletedAt': nowIso,
        'updatedAt': nowIso,
      }, SetOptions(merge: true));
    }

    if (legacyTableIds.isEmpty) {
      return;
    }

    var batch = _firestore.batch();
    var pending = 0;

    Future<void> flushBatchIfNeeded({required bool force}) async {
      if (!force && pending < 450) {
        return;
      }
      if (pending == 0) {
        return;
      }
      await batch.commit();
      batch = _firestore.batch();
      pending = 0;
    }

    for (final legacyTableId in legacyTableIds) {
      final basePrices = await _firestore
          .collection('product_base_prices')
          .where('tenantId', isEqualTo: normalizedTenantId)
          .where('priceTableId', isEqualTo: legacyTableId)
          .get();
      for (final doc in basePrices.docs) {
        batch.delete(doc.reference);
        pending += 1;
        await flushBatchIfNeeded(force: false);
      }
    }

    await flushBatchIfNeeded(force: true);
  }

  bool _isCampaignListActiveForMoment(
    CampaignProductList list,
    DateTime nowUtc,
  ) {
    if (!list.active) {
      return false;
    }

    final validFrom = _parseIsoDate(list.validFromIso);
    if (validFrom != null && nowUtc.isBefore(validFrom)) {
      return false;
    }

    final validUntil = _parseIsoDate(list.validUntilIso);
    if (validUntil != null && nowUtc.isAfter(validUntil)) {
      return false;
    }

    return true;
  }

  DateTime? _parseIsoDate(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized)?.toUtc();
  }

  String _promotionPriceTableId({
    required String tenantId,
    required String? representedCompanyId,
  }) {
    final normalizedTenantId = tenantId.trim().replaceAll('/', '_');
    final normalizedScope = _scopeKey(representedCompanyId)
        .trim()
        .replaceAll('/', '_');
    return 'pt_campaign_promo_${normalizedTenantId}_$normalizedScope';
  }

  String _promotionBasePriceDocId({
    required String priceTableId,
    required String productId,
  }) {
    final normalizedTable = priceTableId.trim().replaceAll('/', '_');
    final normalizedProduct = productId.trim().replaceAll('/', '_');
    return 'pbp_${normalizedTable}_${normalizedProduct}_$_campaignRegionId';
  }

  Map<String, Object?> _copyRootMap(Object? raw) {
    if (raw is! Map) {
      return <String, Object?>{};
    }
    final copy = <String, Object?>{};
    raw.forEach((key, value) {
      copy[key.toString()] = value;
    });
    return copy;
  }

  Map<String, Object?> _copyScopeMap(Object? raw) {
    if (raw is! Map) {
      return <String, Object?>{};
    }
    final copy = <String, Object?>{};
    raw.forEach((key, value) {
      copy[key.toString()] = value;
    });
    return copy;
  }

  List<Map<String, Object?>> _copyListMaps(Object? raw) {
    if (raw is! List) {
      return <Map<String, Object?>>[];
    }
    final result = <Map<String, Object?>>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = <String, Object?>{};
      item.forEach((key, value) {
        map[key.toString()] = value;
      });
      result.add(map);
    }
    return result;
  }
}

class _PromotionPriceCandidate {
  const _PromotionPriceCandidate({
    required this.price,
    required this.validFrom,
    required this.validUntil,
    required this.sourceListId,
    required this.sourceListName,
    required this.listUpdatedAt,
  });

  final double price;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String sourceListId;
  final String sourceListName;
  final DateTime listUpdatedAt;
}
