import 'package:cloud_firestore/cloud_firestore.dart';

enum ProductUnitCatalogType { measure, standard }

class ProductUnitCatalogEntry {
  const ProductUnitCatalogEntry({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.shortCode,
    required this.normalizedShortCode,
  });

  final String id;
  final String name;
  final String normalizedName;
  final String shortCode;
  final String normalizedShortCode;
}

class ProductUnitCatalogService {
  ProductUnitCatalogService(this._firestore);

  final FirebaseFirestore _firestore;

  static const String _measureCollection = 'product_measure_units';
  static const String _standardCollection = 'product_standard_units';
  static const String _metaDocId = '__catalog_meta__';

  static final Set<String> _seededCatalogs = <String>{};

  CollectionReference<Map<String, dynamic>> _collection({
    required String tenantId,
    required ProductUnitCatalogType type,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Tenant invalido para catalogo de unidades.');
    }

    return _firestore
        .collection('tenants')
        .doc(normalizedTenantId)
        .collection(
          type == ProductUnitCatalogType.measure
              ? _measureCollection
              : _standardCollection,
        );
  }

  Stream<List<ProductUnitCatalogEntry>> watchUnits({
    required String tenantId,
    required ProductUnitCatalogType type,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <ProductUnitCatalogEntry>[]);
    }

    return _collection(
      tenantId: normalizedTenantId,
      type: type,
    ).snapshots().map((snapshot) {
      final units = <ProductUnitCatalogEntry>[];
      for (final doc in snapshot.docs) {
        if (doc.id == _metaDocId) {
          continue;
        }
        final entry = _entryFromDoc(doc: doc, type: type);
        if (entry == null) {
          continue;
        }
        units.add(entry);
      }

      units.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return units;
    });
  }

  Future<void> ensureDefaultUnits({
    required String tenantId,
    required ProductUnitCatalogType type,
    required List<String> defaultValues,
    Map<String, String> defaultShortCodes = const <String, String>{},
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw StateError('Tenant invalido para seed de unidades.');
    }

    final cacheKey = '${normalizedTenantId}_${type.name}';
    if (_seededCatalogs.contains(cacheKey)) {
      return;
    }

    final collection = _collection(tenantId: normalizedTenantId, type: type);
    final metadata = await collection.doc(_metaDocId).get();
    final alreadySeeded =
        metadata.data()?['defaultsSeeded'] == true && metadata.exists;
    if (alreadySeeded) {
      _seededCatalogs.add(cacheKey);
      return;
    }

    _seededCatalogs.add(cacheKey);

    try {
      for (final rawValue in defaultValues) {
        final value = rawValue.trim();
        final normalized = _normalizeUnitName(value);
        if (normalized.isEmpty) {
          continue;
        }

        final exists = await _findByNormalizedName(
          tenantId: normalizedTenantId,
          type: type,
          normalizedName: normalized,
        );

        if (exists != null) {
          continue;
        }

        final configuredShortCode = defaultShortCodes[normalized] ?? '';
        final inferredShortCode = _inferMeasureShortCode(value);
        final resolvedShortCode = configuredShortCode.isNotEmpty
            ? configuredShortCode
            : inferredShortCode;
        final normalizedShortCode = _normalizeUnitShortCode(resolvedShortCode);
        final shouldPersistShortCode =
            type == ProductUnitCatalogType.measure &&
            normalizedShortCode.isNotEmpty;

        final payload = <String, Object?>{
          'name': value,
          'normalizedName': normalized,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (shouldPersistShortCode) {
          payload['shortCode'] = resolvedShortCode.toLowerCase();
          payload['normalizedShortCode'] = normalizedShortCode;
        }

        await collection.add(payload);
      }

      await collection.doc(_metaDocId).set({
        'defaultsSeeded': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'seededAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      _seededCatalogs.remove(cacheKey);
      rethrow;
    }
  }

  Future<void> createUnit({
    required String tenantId,
    required ProductUnitCatalogType type,
    required String name,
    String? shortCode,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final trimmedName = name.trim();
    final normalizedName = _normalizeUnitName(trimmedName);
    final trimmedShortCode = (shortCode ?? '').trim();
    final normalizedShortCode = _normalizeUnitShortCode(trimmedShortCode);

    if (normalizedTenantId.isEmpty || normalizedName.isEmpty) {
      throw StateError('Nome de unidade invalido.');
    }

    if (type == ProductUnitCatalogType.measure && normalizedShortCode.isEmpty) {
      throw StateError('Informe uma sigla valida com ate 4 letras.');
    }

    final existing = await _findByNormalizedName(
      tenantId: normalizedTenantId,
      type: type,
      normalizedName: normalizedName,
    );
    if (existing != null) {
      throw StateError('Ja existe uma unidade com esse nome.');
    }

    if (type == ProductUnitCatalogType.measure) {
      final existingByShortCode = await _findByNormalizedShortCode(
        tenantId: normalizedTenantId,
        type: type,
        normalizedShortCode: normalizedShortCode,
      );
      if (existingByShortCode != null) {
        throw StateError('Ja existe uma unidade com essa sigla.');
      }
    }

    final payload = <String, Object?>{
      'name': trimmedName,
      'normalizedName': normalizedName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (type == ProductUnitCatalogType.measure) {
      payload['shortCode'] = trimmedShortCode.toLowerCase();
      payload['normalizedShortCode'] = normalizedShortCode;
    }

    await _collection(tenantId: normalizedTenantId, type: type).add(payload);
  }

  Future<void> updateUnit({
    required String tenantId,
    required ProductUnitCatalogType type,
    required String id,
    required String name,
    String? shortCode,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedId = id.trim();
    final trimmedName = name.trim();
    final normalizedName = _normalizeUnitName(trimmedName);
    final trimmedShortCode = (shortCode ?? '').trim();
    final normalizedShortCode = _normalizeUnitShortCode(trimmedShortCode);

    if (normalizedTenantId.isEmpty ||
        normalizedId.isEmpty ||
        normalizedName.isEmpty) {
      throw StateError('Dados invalidos para atualizar unidade.');
    }

    if (type == ProductUnitCatalogType.measure && normalizedShortCode.isEmpty) {
      throw StateError('Informe uma sigla valida com ate 4 letras.');
    }

    final existing = await _findByNormalizedName(
      tenantId: normalizedTenantId,
      type: type,
      normalizedName: normalizedName,
    );
    if (existing != null && existing.id != normalizedId) {
      throw StateError('Ja existe uma unidade com esse nome.');
    }

    if (type == ProductUnitCatalogType.measure) {
      final existingByShortCode = await _findByNormalizedShortCode(
        tenantId: normalizedTenantId,
        type: type,
        normalizedShortCode: normalizedShortCode,
      );
      if (existingByShortCode != null &&
          existingByShortCode.id != normalizedId) {
        throw StateError('Ja existe uma unidade com essa sigla.');
      }
    }

    final payload = <String, Object?>{
      'name': trimmedName,
      'normalizedName': normalizedName,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (type == ProductUnitCatalogType.measure) {
      payload['shortCode'] = trimmedShortCode.toLowerCase();
      payload['normalizedShortCode'] = normalizedShortCode;
    }

    await _collection(
      tenantId: normalizedTenantId,
      type: type,
    ).doc(normalizedId).set(payload, SetOptions(merge: true));
  }

  Future<void> deleteUnit({
    required String tenantId,
    required ProductUnitCatalogType type,
    required String id,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedId = id.trim();
    if (normalizedTenantId.isEmpty || normalizedId.isEmpty) {
      throw StateError('Dados invalidos para excluir unidade.');
    }

    await _collection(
      tenantId: normalizedTenantId,
      type: type,
    ).doc(normalizedId).delete();
  }

  Future<ProductUnitCatalogEntry?> _findByNormalizedName({
    required String tenantId,
    required ProductUnitCatalogType type,
    required String normalizedName,
  }) async {
    final snapshot = await _collection(
      tenantId: tenantId,
      type: type,
    ).where('normalizedName', isEqualTo: normalizedName).limit(1).get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    final doc = snapshot.docs.first;
    return _entryFromDoc(doc: doc, type: type);
  }

  Future<ProductUnitCatalogEntry?> _findByNormalizedShortCode({
    required String tenantId,
    required ProductUnitCatalogType type,
    required String normalizedShortCode,
  }) async {
    if (normalizedShortCode.isEmpty) {
      return null;
    }

    final snapshot = await _collection(tenantId: tenantId, type: type)
        .where('normalizedShortCode', isEqualTo: normalizedShortCode)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    final doc = snapshot.docs.first;
    return _entryFromDoc(doc: doc, type: type);
  }

  ProductUnitCatalogEntry? _entryFromDoc({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required ProductUnitCatalogType type,
  }) {
    final data = doc.data();
    final name = (data['name'] ?? '').toString().trim();
    if (name.isEmpty) {
      return null;
    }

    final normalizedName = (data['normalizedName'] ?? _normalizeUnitName(name))
        .toString()
        .trim();
    final parsedShortCode = (data['shortCode'] ?? '').toString().trim();
    final fallbackShortCode = type == ProductUnitCatalogType.measure
        ? _inferMeasureShortCode(name)
        : '';
    final shortCode = parsedShortCode.isNotEmpty
        ? parsedShortCode.toLowerCase()
        : fallbackShortCode;
    final normalizedShortCode =
        (data['normalizedShortCode'] ?? _normalizeUnitShortCode(shortCode))
            .toString()
            .trim();

    return ProductUnitCatalogEntry(
      id: doc.id,
      name: name,
      normalizedName: normalizedName,
      shortCode: shortCode,
      normalizedShortCode: normalizedShortCode,
    );
  }

  String _normalizeUnitName(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }

    return normalized.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeUnitShortCode(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }

    final isValid = RegExp(r'^[a-z]{1,4}$').hasMatch(normalized);
    if (!isValid) {
      return '';
    }

    return normalized;
  }

  String _inferMeasureShortCode(String unitName) {
    switch (_normalizeUnitName(unitName)) {
      case 'milimetro':
        return 'mm';
      case 'centimetro':
        return 'cm';
      case 'metro':
        return 'm';
      case 'litro':
        return 'l';
      default:
        return _normalizeUnitShortCode(unitName);
    }
  }
}
