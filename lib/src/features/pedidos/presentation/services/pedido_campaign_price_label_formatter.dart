class PedidoCampaignPriceLabelFormatter {
  const PedidoCampaignPriceLabelFormatter._();

  static String formatMobileSearchPriceLabel({
    required double basePrice,
    required double? promotionPrice,
    required String Function(double value) formatMoneyBr,
  }) {
    final safeBasePrice =
        basePrice.isNaN || basePrice.isInfinite || basePrice < 0
        ? 0.0
        : basePrice;

    final hasPromotion =
        promotionPrice != null &&
        !promotionPrice.isNaN &&
        !promotionPrice.isInfinite &&
        promotionPrice >= 0;

    if (!hasPromotion) {
      return 'R\$ ${formatMoneyBr(safeBasePrice)}';
    }

    final safePromotionPrice = promotionPrice;

    return 'Promoção R\$${formatMoneyBr(safePromotionPrice)} (R\$${formatMoneyBr(safeBasePrice)})';
  }
}
