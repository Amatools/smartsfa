import 'workspace_profile_service.dart';

class CampaignPromotionProductMeta {
  const CampaignPromotionProductMeta({
    required this.sourceListId,
    required this.sourceListLabel,
    required this.promotionPrice,
    required this.listUpdatedAt,
  });

  final String sourceListId;
  final String sourceListLabel;
  final double? promotionPrice;
  final DateTime listUpdatedAt;
}

class CampaignProductResolutionService {
  const CampaignProductResolutionService._();

  static Set<String> resolveActiveProductIds({
    required Iterable<CampaignProductList> lists,
    DateTime? momentUtc,
  }) {
    final nowUtc = (momentUtc ?? DateTime.now()).toUtc();
    final ids = <String>{};

    for (final list in lists) {
      if (!isListActiveForMoment(list, nowUtc)) {
        continue;
      }
      for (final productId in list.productIds) {
        final normalizedProductId = productId.trim();
        if (normalizedProductId.isEmpty) {
          continue;
        }
        ids.add(normalizedProductId);
      }
    }

    return ids;
  }

  static Map<String, CampaignPromotionProductMeta>
  resolveActivePromotionMetaByProductId({
    required Iterable<CampaignProductList> promotionLists,
    DateTime? momentUtc,
  }) {
    final nowUtc = (momentUtc ?? DateTime.now()).toUtc();
    final bestByProductId = <String, CampaignPromotionProductMeta>{};

    for (final list in promotionLists) {
      if (!isListActiveForMoment(list, nowUtc)) {
        continue;
      }

      final listUpdatedAt =
          DateTime.tryParse((list.updatedAtIso ?? '').trim())?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

      for (final item in list.items) {
        final productId = item.productId.trim();
        if (productId.isEmpty) {
          continue;
        }

        final candidate = CampaignPromotionProductMeta(
          sourceListId: list.id,
          sourceListLabel: list.name,
          promotionPrice: item.promotionPrice,
          listUpdatedAt: listUpdatedAt,
        );

        final current = bestByProductId[productId];
        if (current == null ||
            _shouldReplacePromotionCandidate(current, candidate)) {
          bestByProductId[productId] = candidate;
        }
      }
    }

    return bestByProductId;
  }

  static bool isListActiveForMoment(CampaignProductList list, DateTime nowUtc) {
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

  static DateTime? _parseIsoDate(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized)?.toUtc();
  }

  static bool _shouldReplacePromotionCandidate(
    CampaignPromotionProductMeta current,
    CampaignPromotionProductMeta next,
  ) {
    final currentPrice = current.promotionPrice;
    final nextPrice = next.promotionPrice;

    if (currentPrice == null && nextPrice != null) {
      return true;
    }
    if (currentPrice != null && nextPrice == null) {
      return false;
    }
    if (currentPrice != null && nextPrice != null) {
      if (nextPrice < currentPrice) {
        return true;
      }
      if (nextPrice > currentPrice) {
        return false;
      }
    }

    return next.listUpdatedAt.isAfter(current.listUpdatedAt);
  }
}
