import '../../../../core/models/produto.dart';
import '../../../../core/models/domain_types.dart';
import '../../../auth/services/campaign_product_resolution_service.dart';
import '../../../auth/services/workspace_profile_service.dart';

class PedidoCampaignCatalogData {
  const PedidoCampaignCatalogData({
    required this.promotionProducts,
    required this.highlightProducts,
    required this.promotionMetaByProductId,
  });

  final List<Produto> promotionProducts;
  final List<Produto> highlightProducts;
  final Map<String, CampaignPromotionProductMeta> promotionMetaByProductId;
}

class PedidoCampaignCatalogResolverService {
  const PedidoCampaignCatalogResolverService._();

  static PedidoCampaignCatalogData resolve({
    required List<Produto> products,
    required List<CampaignProductList> promotionLists,
    required List<CampaignProductList> highlightLists,
    DateTime? momentUtc,
  }) {
    final nowUtc = (momentUtc ?? DateTime.now()).toUtc();

    final promotionMetaByProductId =
        CampaignProductResolutionService.resolveActivePromotionMetaByProductId(
          promotionLists: promotionLists,
          momentUtc: nowUtc,
        );

    final highlightIds =
        CampaignProductResolutionService.resolveActiveProductIds(
          lists: highlightLists,
          momentUtc: nowUtc,
        );

    final promotionProducts =
        products
            .where(
              (product) => promotionMetaByProductId.containsKey(product.id),
            )
            .where((product) => product.status == ProductStatus.active)
            .toList(growable: false)
          ..sort(
            (a, b) =>
                a.descricao.toLowerCase().compareTo(b.descricao.toLowerCase()),
          );

    final highlightProducts =
        products
            .where((product) => highlightIds.contains(product.id))
            .where((product) => product.status == ProductStatus.active)
            .toList(growable: false)
          ..sort(
            (a, b) =>
                a.descricao.toLowerCase().compareTo(b.descricao.toLowerCase()),
          );

    return PedidoCampaignCatalogData(
      promotionProducts: promotionProducts,
      highlightProducts: highlightProducts,
      promotionMetaByProductId: promotionMetaByProductId,
    );
  }
}
