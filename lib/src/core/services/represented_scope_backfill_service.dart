import 'package:cloud_firestore/cloud_firestore.dart';

class RepresentedScopeBackfillResult {
  const RepresentedScopeBackfillResult({
    required this.produtosUpdated,
    required this.taxRulesUpdated,
    required this.unresolved,
  });

  final int produtosUpdated;
  final int taxRulesUpdated;
  final int unresolved;

  int get totalUpdated => produtosUpdated + taxRulesUpdated;
}

class RepresentedScopeBackfillService {
  RepresentedScopeBackfillService(this._firestore);

  final FirebaseFirestore _firestore;

  Future<RepresentedScopeBackfillResult> runForTenant({
    required String tenantId,
    required List<String> activeRepresentedCompanyIds,
    String? preferredRepresentedCompanyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const RepresentedScopeBackfillResult(
        produtosUpdated: 0,
        taxRulesUpdated: 0,
        unresolved: 0,
      );
    }

    final validRepresentedIds = <String>{
      for (final id in activeRepresentedCompanyIds)
        if (id.trim().isNotEmpty) id.trim(),
    };

    if (validRepresentedIds.isEmpty) {
      return const RepresentedScopeBackfillResult(
        produtosUpdated: 0,
        taxRulesUpdated: 0,
        unresolved: 0,
      );
    }

    final preferred = (preferredRepresentedCompanyId ?? '').trim();
    final preferredValid = validRepresentedIds.contains(preferred)
        ? preferred
        : '';
    final singleScope = validRepresentedIds.length == 1
        ? validRepresentedIds.first
        : '';
    final fallbackRepresentedId = preferredValid.isNotEmpty
        ? preferredValid
        : singleScope;

    final produtosOutcome = await _backfillCollection(
      collection: 'produtos',
      tenantId: normalizedTenantId,
      validRepresentedIds: validRepresentedIds,
      fallbackRepresentedId: fallbackRepresentedId,
      legacyScopeFields: const <String>['representadaId', 'companyId'],
    );

    final taxRulesOutcome = await _backfillCollection(
      collection: 'tax_rules',
      tenantId: normalizedTenantId,
      validRepresentedIds: validRepresentedIds,
      fallbackRepresentedId: fallbackRepresentedId,
      legacyScopeFields: const <String>['representadaId', 'companyId'],
    );

    return RepresentedScopeBackfillResult(
      produtosUpdated: produtosOutcome.updated,
      taxRulesUpdated: taxRulesOutcome.updated,
      unresolved: produtosOutcome.unresolved + taxRulesOutcome.unresolved,
    );
  }

  Future<_BackfillCollectionOutcome> _backfillCollection({
    required String collection,
    required String tenantId,
    required Set<String> validRepresentedIds,
    required String fallbackRepresentedId,
    required List<String> legacyScopeFields,
  }) async {
    final snapshot = await _firestore
        .collection(collection)
        .where('tenantId', isEqualTo: tenantId)
        .get();

    final docsToUpdate = <({String id, String representedCompanyId})>[];
    var unresolved = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final currentScope = _normalizeScope(data['representedCompanyId']);
      if (currentScope.isNotEmpty) {
        continue;
      }

      var targetScope = '';
      for (final field in legacyScopeFields) {
        final legacyScope = _normalizeScope(data[field]);
        if (legacyScope.isNotEmpty &&
            validRepresentedIds.contains(legacyScope)) {
          targetScope = legacyScope;
          break;
        }
      }

      if (targetScope.isEmpty) {
        targetScope = fallbackRepresentedId;
      }

      if (targetScope.isEmpty) {
        unresolved++;
        continue;
      }

      docsToUpdate.add((id: doc.id, representedCompanyId: targetScope));
    }

    if (docsToUpdate.isEmpty) {
      return _BackfillCollectionOutcome(updated: 0, unresolved: unresolved);
    }

    var updated = 0;
    for (var i = 0; i < docsToUpdate.length; i += 400) {
      final end = (i + 400 < docsToUpdate.length)
          ? i + 400
          : docsToUpdate.length;
      final batch = _firestore.batch();

      for (final entry in docsToUpdate.sublist(i, end)) {
        final ref = _firestore.collection(collection).doc(entry.id);
        batch.set(ref, {
          'representedCompanyId': entry.representedCompanyId,
        }, SetOptions(merge: true));
      }

      await batch.commit();
      updated += (end - i);
    }

    return _BackfillCollectionOutcome(updated: updated, unresolved: unresolved);
  }

  String _normalizeScope(Object? value) {
    return value?.toString().trim() ?? '';
  }
}

class _BackfillCollectionOutcome {
  const _BackfillCollectionOutcome({
    required this.updated,
    required this.unresolved,
  });

  final int updated;
  final int unresolved;
}
