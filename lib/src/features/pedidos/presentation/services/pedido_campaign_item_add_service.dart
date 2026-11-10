import '../../../../core/models/domain_types.dart';
import '../../../../core/models/pedido.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/pedido_repository.dart';
import 'pedido_format_utils.dart';

class PedidoCampaignItemAddService {
  PedidoCampaignItemAddService({required PedidoRepository pedidoRepository})
    : _pedidoRepository = pedidoRepository;

  final PedidoRepository _pedidoRepository;

  static const Set<OrderStatus> _openStatuses = <OrderStatus>{
    OrderStatus.draft,
    OrderStatus.pendingCustomer,
    OrderStatus.pendingSend,
  };

  Future<List<Pedido>> fetchOpenOrders({
    required String tenantId,
    String? representedCompanyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return const <Pedido>[];
    }

    final normalizedRepresentedId = (representedCompanyId ?? '').trim();
    final all = await _pedidoRepository.fetchAll(tenantId: normalizedTenantId);

    final filtered = all
        .where((pedido) {
          if (!_openStatuses.contains(pedido.statusFila)) {
            return false;
          }
          if (normalizedRepresentedId.isEmpty) {
            return true;
          }
          return (pedido.representedCompanyId ?? '').trim() ==
              normalizedRepresentedId;
        })
        .toList(growable: false);

    filtered.sort((a, b) {
      final aUpdated = a.updatedAt?.millisecondsSinceEpoch ?? 0;
      final bUpdated = b.updatedAt?.millisecondsSinceEpoch ?? 0;
      return bUpdated.compareTo(aUpdated);
    });

    return filtered;
  }

  Future<Pedido?> addProductToOrder({
    required String tenantId,
    required String orderId,
    required Produto product,
    required int quantity,
    required OrderItemSourceType sourceType,
    String? sourceListId,
    String? sourceListLabel,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedTenantId.isEmpty || normalizedOrderId.isEmpty) {
      return null;
    }

    final safeQuantity = quantity <= 0 ? 1 : quantity;
    final current = await _pedidoRepository.fetchById(
      tenantId: normalizedTenantId,
      id: normalizedOrderId,
    );
    if (current == null) {
      return null;
    }
    if (!_openStatuses.contains(current.statusFila)) {
      return null;
    }

    final unitPrice = PedidoFormatUtils.roundCurrency(product.valorBruto ?? 0);
    final items = List<PedidoItem>.from(current.itens);
    final existingIndex = items.indexWhere(
      (item) => item.productId == product.id,
    );
    final now = DateTime.now().toUtc();

    if (existingIndex >= 0) {
      final existing = items[existingIndex];
      final nextQuantity = existing.quantity + safeQuantity;
      final effectiveUnitPrice = existing.unitPrice > 0
          ? existing.unitPrice
          : unitPrice;
      final mergedSourceType = _mergeSourceType(
        existing.sourceType,
        sourceType,
      );
      final mergedSourceListId = _mergeSourceValue(
        currentSourceType: existing.sourceType,
        incomingSourceType: sourceType,
        currentValue: existing.sourceListId,
        incomingValue: sourceListId,
      );
      final mergedSourceListLabel = _mergeSourceValue(
        currentSourceType: existing.sourceType,
        incomingSourceType: sourceType,
        currentValue: existing.sourceListLabel,
        incomingValue: sourceListLabel,
      );

      items[existingIndex] = existing.copyWith(
        quantity: nextQuantity,
        unitPrice: effectiveUnitPrice,
        totalPrice: PedidoFormatUtils.roundCurrency(
          nextQuantity * effectiveUnitPrice,
        ),
        sourceType: mergedSourceType,
        sourceListId: mergedSourceListId,
        sourceListLabel: mergedSourceListLabel,
      );
    } else {
      items.add(
        PedidoItem(
          id: 'itm_${now.microsecondsSinceEpoch}_${product.id}',
          productId: product.id,
          productCode: product.codigoInterno.trim().isEmpty
              ? '-'
              : product.codigoInterno.trim(),
          productName: product.descricao.trim().isEmpty
              ? 'Produto sem descricao'
              : product.descricao.trim(),
          quantity: safeQuantity.toDouble(),
          unitPrice: unitPrice,
          totalPrice: PedidoFormatUtils.roundCurrency(unitPrice * safeQuantity),
          unit: product.unidade,
          ncm: product.ncm,
          sourceType: sourceType,
          sourceListId: (sourceListId ?? '').trim().isEmpty
              ? null
              : sourceListId!.trim(),
          sourceListLabel: (sourceListLabel ?? '').trim().isEmpty
              ? null
              : sourceListLabel!.trim(),
        ),
      );
    }

    final nextTotalItens = items.fold<double>(
      0,
      (sum, item) => PedidoFormatUtils.roundCurrency(sum + item.quantity),
    );
    final nextTotalBruto = items.fold<double>(
      0,
      (sum, item) => PedidoFormatUtils.roundCurrency(sum + item.totalPrice),
    );

    final updated = current.copyWith(
      itens: items,
      totalItens: nextTotalItens,
      totalBruto: nextTotalBruto,
      updatedAt: now,
    );

    await _pedidoRepository.save(updated);
    return updated;
  }

  OrderItemSourceType _mergeSourceType(
    OrderItemSourceType current,
    OrderItemSourceType incoming,
  ) {
    if (current == OrderItemSourceType.promotion) {
      return current;
    }
    if (incoming == OrderItemSourceType.promotion) {
      return incoming;
    }
    if (current == OrderItemSourceType.highlight) {
      return current;
    }
    return incoming;
  }

  String? _mergeSourceValue({
    required OrderItemSourceType currentSourceType,
    required OrderItemSourceType incomingSourceType,
    required String? currentValue,
    required String? incomingValue,
  }) {
    final normalizedCurrent = (currentValue ?? '').trim();
    final normalizedIncoming = (incomingValue ?? '').trim();

    final mergedType = _mergeSourceType(currentSourceType, incomingSourceType);
    if (mergedType == currentSourceType && normalizedCurrent.isNotEmpty) {
      return normalizedCurrent;
    }
    if (normalizedIncoming.isNotEmpty) {
      return normalizedIncoming;
    }
    return normalizedCurrent.isEmpty ? null : normalizedCurrent;
  }
}
