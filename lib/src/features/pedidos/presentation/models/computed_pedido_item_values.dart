import '../../../../core/models/pedido.dart';

/// Result of computing an order item's price/tax snapshot (base price +
/// commercial rule adjustments + point discounts). Made public (moved out of
/// `pedidos_page.dart`, where it previously lived as a private class) so it
/// can be shared with extracted pricing services.
class ComputedPedidoItemValues {
  const ComputedPedidoItemValues({
    required this.unitPrice,
    required this.totalPrice,
    required this.taxSnapshot,
    required this.usedFallback,
  });

  final double unitPrice;
  final double totalPrice;
  final PedidoItemTaxSnapshot taxSnapshot;
  final bool usedFallback;
}
