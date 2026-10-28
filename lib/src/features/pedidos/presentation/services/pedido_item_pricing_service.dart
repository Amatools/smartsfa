import '../../../../core/models/customer_price_table_assignment.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/cliente.dart';
import '../../../../core/models/pedido.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/cliente_repository.dart';
import '../../../../core/repositories/customer_price_table_assignment_repository.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../../../precos/presentation/services/default_price_table_guard.dart';
import '../../../precos/services/product_tax_engine_service.dart';
import '../models/computed_pedido_item_values.dart';
import 'pedido_commercial_pricing_service.dart';
import 'pedido_format_utils.dart';

/// Resolves destination UF, price table and fiscal snapshot for a single
/// pedido item, orchestrating the tax engine plus commercial rule/point
/// discount adjustments.
///
/// Extracted from `_PedidoInlineEditorState` to isolate the (async,
/// repository-dependent but otherwise pure) pricing/tax computation from
/// widget/state concerns. Callers own the mutable state (items, customer
/// selection, commercial rules); this service only takes explicit inputs
/// and returns a [ComputedPedidoItemValues] result.
class PedidoItemPricingService {
  PedidoItemPricingService({
    required this.clienteRepository,
    required this.customerPriceTableAssignmentRepository,
    required this.taxEngineService,
  });

  final ClienteRepository clienteRepository;
  final CustomerPriceTableAssignmentRepository
  customerPriceTableAssignmentRepository;
  final ProductTaxEngineService taxEngineService;

  List<CustomerPriceTableAssignment>? _cachedAssignments;

  /// Must be called whenever the tenant scope changes (mirrors the
  /// invalidation previously done ad-hoc on `_cachedAssignments = null`).
  void invalidateAssignmentsCache() {
    _cachedAssignments = null;
  }

  String normalizedOriginUf({
    required String? originCompanyUfFromWidget,
    required String? originCompanyUfFromPedido,
  }) {
    final fromWidget = (originCompanyUfFromWidget ?? '').trim().toUpperCase();
    if (fromWidget.isNotEmpty) {
      return fromWidget;
    }
    final fromPedido = (originCompanyUfFromPedido ?? '').trim().toUpperCase();
    if (fromPedido.isNotEmpty) {
      return fromPedido;
    }
    return 'SP';
  }

  bool _isInDateWindow(
    DateTime? validFrom,
    DateTime? validUntil,
    DateTime now,
  ) {
    if (validFrom != null && now.isBefore(validFrom.toUtc())) {
      return false;
    }
    if (validUntil != null && now.isAfter(validUntil.toUtc())) {
      return false;
    }
    return true;
  }

  Future<String> resolveDestinationUf({
    required String tenantId,
    required String? customerId,
    required String fallbackUf,
  }) async {
    final normalizedCustomerId = (customerId ?? '').trim();
    if (normalizedCustomerId.isEmpty || tenantId.trim().isEmpty) {
      return fallbackUf;
    }

    try {
      final cliente = await clienteRepository.fetchById(
        tenantId: tenantId,
        id: normalizedCustomerId,
      );
      final clienteUf = (cliente?.estado ?? '').trim().toUpperCase();
      return clienteUf.isEmpty ? fallbackUf : clienteUf;
    } catch (_) {
      return fallbackUf;
    }
  }

  Future<String> resolvePriceTableId({
    required String tenantId,
    required String destinationUf,
    required String? customerId,
    required String? representedCompanyId,
  }) async {
    if (tenantId.trim().isEmpty) {
      return '';
    }

    final normalizedCustomerId = (customerId ?? '').trim();
    final now = DateTime.now().toUtc();

    if (normalizedCustomerId.isNotEmpty) {
      try {
        final assignments = await _loadAssignmentsOnce(tenantId);
        final eligible = assignments
            .where(
              (item) =>
                  item.customerId == normalizedCustomerId &&
                  item.isActive &&
                  _isInDateWindow(item.validFrom, item.validUntil, now),
            )
            .toList();

        eligible.sort((a, b) {
          final aRegion = (a.regionId ?? '').trim().toUpperCase();
          final bRegion = (b.regionId ?? '').trim().toUpperCase();
          final aExact = aRegion == destinationUf;
          final bExact = bRegion == destinationUf;
          if (aExact != bExact) {
            return bExact ? 1 : -1;
          }

          final aDefault = aRegion.isEmpty || a.isDefault;
          final bDefault = bRegion.isEmpty || b.isDefault;
          if (aDefault != bDefault) {
            return bDefault ? 1 : -1;
          }

          return b.priority.compareTo(a.priority);
        });

        final chosen = eligible.isEmpty ? null : eligible.first;
        final assignmentTableId = (chosen?.priceTableId ?? '').trim();
        if (assignmentTableId.isNotEmpty) {
          return assignmentTableId;
        }
      } catch (_) {
        // Falls back to default table id when customer assignment lookup fails.
      }
    }

    return DefaultPriceTableGuard.defaultPriceTableIdForScope(
      tenantId: tenantId,
      representedCompanyId: representedCompanyId,
    );
  }

  Future<List<CustomerPriceTableAssignment>> _loadAssignmentsOnce(
    String tenantId,
  ) async {
    final cached = _cachedAssignments;
    if (cached != null) {
      return cached;
    }

    final loaded = await customerPriceTableAssignmentRepository.fetchAll(
      tenantId: tenantId,
    );
    _cachedAssignments = loaded;
    return loaded;
  }

  PedidoItemTaxSnapshot buildFallbackSnapshotFromProduct({
    required Produto product,
    required double quantity,
    required double unitPrice,
    PedidoItemTaxSnapshot? previous,
    double? previousQuantity,
  }) {
    final baseValue = PedidoFormatUtils.roundCurrency(quantity * unitPrice);
    final aliquotaIpi = product.aliquotaIpiBase ?? previous?.aliquotaIpiPercent;
    final valorIpi = aliquotaIpi == null
        ? null
        : PedidoFormatUtils.roundCurrency(baseValue * (aliquotaIpi / 100));
    final oldQty = previousQuantity ?? quantity;
    final safeOldQty = oldQty <= 0 ? 1 : oldQty;
    final ratio = quantity / safeOldQty;
    final valorSt = previous?.valorSt == null
        ? 0
        : PedidoFormatUtils.roundCurrency(previous!.valorSt! * ratio);
    final valorDifal = previous?.valorDifal == null
        ? 0
        : PedidoFormatUtils.roundCurrency(previous!.valorDifal! * ratio);

    final normalizedNcm = (product.ncm ?? '').trim();
    final normalizedCest = (product.cest ?? '').trim();
    return PedidoItemTaxSnapshot(
      regraFiscalId: previous?.regraFiscalId,
      tabelaId: previous?.tabelaId,
      ufDestino: previous?.ufDestino,
      ncm: normalizedNcm.isEmpty ? previous?.ncm : normalizedNcm,
      cest: normalizedCest.isEmpty ? previous?.cest : normalizedCest,
      aliquotaIpiPercent: aliquotaIpi,
      aliquotaDestinoPercent: previous?.aliquotaDestinoPercent,
      aliquotaCreditoPercent: previous?.aliquotaCreditoPercent,
      aliquotaDifalPercent: previous?.aliquotaDifalPercent,
      valorIpi: valorIpi,
      valorSt: previous?.valorSt,
      valorDifal: previous?.valorDifal,
      valorTotalItem: PedidoFormatUtils.roundCurrency(
        baseValue + (valorIpi ?? 0) + valorSt + valorDifal,
      ),
    );
  }

  /// Resolves the final price/tax values for a pedido item, trying the
  /// customer's assigned price table first, then the legacy default table,
  /// then falling back to the product's gross price. Commercial adjustment
  /// rules and point discounts are applied on top of whichever base values
  /// were resolved.
  Future<ComputedPedidoItemValues> resolveItemValues({
    required String tenantId,
    required Produto product,
    required double quantity,
    PedidoItemTaxSnapshot? previousSnapshot,
    double? previousQuantity,
    List<double> appliedDiscountPercents = const <double>[],
    required Cliente? selectedCliente,
    required String? customerId,
    required String? representedCompanyId,
    required String originCompanyUf,
    required SalePurpose salePurpose,
    required List<CommercialAdjustmentRule> commercialRules,
  }) async {
    final fallbackUnitPrice = PedidoFormatUtils.roundCurrency(
      product.valorBruto ?? 0,
    );
    final fallbackSnapshot = buildFallbackSnapshotFromProduct(
      product: product,
      quantity: quantity,
      unitPrice: fallbackUnitPrice,
      previous: previousSnapshot,
      previousQuantity: previousQuantity,
    );

    final fallback = ComputedPedidoItemValues(
      unitPrice: fallbackUnitPrice,
      totalPrice: PedidoFormatUtils.roundCurrency(
        quantity * fallbackUnitPrice,
      ),
      taxSnapshot: fallbackSnapshot,
      usedFallback: true,
    );

    ComputedPedidoItemValues finalize(ComputedPedidoItemValues baseValues) {
      final adjusted = PedidoCommercialPricingService.applyCommercialRule(
        rules: commercialRules,
        baseValues: baseValues,
        product: product,
        quantity: quantity,
      );
      return PedidoCommercialPricingService.applyPointDiscounts(
        baseValues: adjusted,
        discountPercents: appliedDiscountPercents,
      );
    }

    if (tenantId.trim().isEmpty) {
      return finalize(fallback);
    }

    final destinationUf = await resolveDestinationUf(
      tenantId: tenantId,
      customerId: customerId,
      fallbackUf: originCompanyUf,
    );
    final resolvedTableId = await resolvePriceTableId(
      tenantId: tenantId,
      destinationUf: destinationUf,
      customerId: customerId,
      representedCompanyId: representedCompanyId,
    );
    if (resolvedTableId.isEmpty) {
      return finalize(fallback);
    }

    final customerTaxProfile =
        selectedCliente?.taxProfile ?? CustomerTaxProfile.contribuinte;
    final isZonaFrancaSuframa = selectedCliente?.isZfmSuframa ?? false;

    Future<ComputedPedidoItemValues?> tryTable(String tableId) async {
      if (tableId.trim().isEmpty) {
        return null;
      }

      final result = await taxEngineService.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: product.id,
        tabelaId: tableId,
        clienteUf: destinationUf,
        quantidade: quantity,
        salePurpose: salePurpose,
        customerTaxProfile: customerTaxProfile,
        isZonaFrancaSuframa: isZonaFrancaSuframa,
        representedCompanyId: representedCompanyId,
        ufOrigem: originCompanyUf,
        customerTaxRegime: selectedCliente?.taxRegime,
      );

      final safeQty = quantity <= 0 ? 1 : quantity;
      final unitPrice = PedidoFormatUtils.roundCurrency(
        result.precoBase / safeQty,
      );
      final snapshot = PedidoItemTaxSnapshot(
        regraFiscalId: result.regraFiscalId,
        tabelaId: result.tabelaId,
        ufDestino: result.ufDestino,
        ncm: (result.ncm ?? product.ncm)?.trim(),
        cest: (result.cest ?? product.cest)?.trim(),
        aliquotaIpiPercent: product.aliquotaIpiBase,
        aliquotaDestinoPercent: previousSnapshot?.aliquotaDestinoPercent,
        aliquotaCreditoPercent: previousSnapshot?.aliquotaCreditoPercent,
        aliquotaDifalPercent: previousSnapshot?.aliquotaDifalPercent,
        valorIpi: PedidoFormatUtils.roundCurrency(result.valorIpi),
        valorSt: PedidoFormatUtils.roundCurrency(result.valorSt),
        valorDifal: PedidoFormatUtils.roundCurrency(result.valorDifal),
        valorFcp: PedidoFormatUtils.roundCurrency(result.valorFcp),
        valorFcpSt: PedidoFormatUtils.roundCurrency(result.valorFcpSt),
        valorFcpDifal: PedidoFormatUtils.roundCurrency(result.valorFcpDifal),
        valorTotalItem: PedidoFormatUtils.roundCurrency(result.valorTotalItem),
        operationProfileKey: result.operationProfileKey,
        matchedTier: result.matchedTier,
        matchedByCest: result.matchedByCest,
        matchedByBuyerRegime: result.matchedByBuyerRegime,
        operationProfileSource: result.operationProfileSource,
        operationProfileOverrideId: result.operationProfileOverrideId,
      );

      return ComputedPedidoItemValues(
        unitPrice: unitPrice,
        totalPrice: PedidoFormatUtils.roundCurrency(result.valorTotalItem),
        taxSnapshot: snapshot,
        usedFallback: false,
      );
    }

    try {
      final primary = await tryTable(resolvedTableId);
      if (primary != null) {
        return finalize(primary);
      }
    } catch (_) {
      final legacyDefaultTableId =
          DefaultPriceTableGuard.legacyDefaultPriceTableIdForScope(
            tenantId: tenantId,
            representedCompanyId: representedCompanyId,
          );

      if (legacyDefaultTableId != resolvedTableId) {
        try {
          final legacy = await tryTable(legacyDefaultTableId);
          if (legacy != null) {
            return finalize(legacy);
          }
        } catch (_) {
          // Keeps fallback below.
        }
      }
    }

    return finalize(fallback);
  }
}
