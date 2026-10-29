import '../../../../core/models/produto.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../models/computed_pedido_item_values.dart';
import 'pedido_format_utils.dart';

class PointDiscountBreakdown {
  const PointDiscountBreakdown({
    this.beforeTax = const <double>[],
    this.afterTax = const <double>[],
  });

  final List<double> beforeTax;
  final List<double> afterTax;
}

/// Resolves commercial adjustment rules (per product/brand/category/general
/// scope) and point-discount stacking on top of a base computed price.
/// Extracted from `pedidos_page.dart` (SRP) — this service is pure/stateless
/// and only depends on the rule list and product passed in by the caller.
class PedidoCommercialPricingService {
  const PedidoCommercialPricingService._();

  static PointDiscountBreakdown splitPointDiscountsByMode({
    required List<double> discountPercents,
    required List<OrderDiscountFieldRule> policyFields,
  }) {
    if (discountPercents.isEmpty) {
      return const PointDiscountBreakdown();
    }

    final beforeTax = <double>[];
    final afterTax = <double>[];
    for (var index = 0; index < discountPercents.length; index++) {
      final discount = discountPercents[index];
      final safeDiscount = discount < 0 ? 0.0 : discount;
      if (safeDiscount <= 0) {
        continue;
      }

      final mode = index < policyFields.length
          ? policyFields[index].applyMode
          : OrderDiscountApplyMode.afterTax;
      if (mode == OrderDiscountApplyMode.beforeTax) {
        beforeTax.add(safeDiscount);
      } else {
        afterTax.add(safeDiscount);
      }
    }

    return PointDiscountBreakdown(beforeTax: beforeTax, afterTax: afterTax);
  }

  static String resolveCommercialCode(Produto product) {
    final codeCandidates = [product.codigoFabricante, product.sku, product.ean];
    for (final candidate in codeCandidates) {
      final normalized = (candidate ?? '').trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  static List<String> splitRuleTargets(String raw) {
    final targets = <String>[];
    final seen = <String>{};
    for (final value in raw.split(RegExp(r'[,;|\n]+'))) {
      final normalized = PedidoFormatUtils.normalizeSearch(value);
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      targets.add(value.trim());
    }
    return targets;
  }

  static List<String> resolveRuleTargets(CommercialAdjustmentRule rule) {
    if (rule.scopeTargets.isNotEmpty) {
      final targets = <String>[];
      final seen = <String>{};
      for (final value in rule.scopeTargets) {
        final normalized = PedidoFormatUtils.normalizeSearch(value);
        if (normalized.isEmpty || !seen.add(normalized)) {
          continue;
        }
        targets.add(value.trim());
      }
      return targets;
    }
    return splitRuleTargets(rule.scopeTarget);
  }

  static bool ruleTargetsContain(
    CommercialAdjustmentRule rule,
    Iterable<String> candidates,
  ) {
    final normalizedTargets = resolveRuleTargets(rule)
        .map(PedidoFormatUtils.normalizeSearch)
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedTargets.isEmpty) {
      return false;
    }

    for (final candidate in candidates) {
      final normalizedCandidate = PedidoFormatUtils.normalizeSearch(candidate);
      if (normalizedCandidate.isEmpty) {
        continue;
      }
      if (normalizedTargets.contains(normalizedCandidate)) {
        return true;
      }
    }
    return false;
  }

  static bool ruleMatchesProduct(
    CommercialAdjustmentRule rule,
    Produto product,
  ) {
    final scope = rule.scope.trim().toLowerCase();
    if (scope == 'geral') {
      return true;
    }

    if (scope == 'marca') {
      return ruleTargetsContain(rule, <String>[product.marca ?? '']);
    }

    if (scope == 'categoria') {
      return ruleTargetsContain(rule, <String>[product.categoria ?? '']);
    }

    if (scope == 'produto') {
      final descricao = product.descricao.trim();
      final codigoInterno = product.codigoInterno.trim();
      final comercial = resolveCommercialCode(product);
      return ruleTargetsContain(rule, <String>[
        product.id,
        descricao,
        codigoInterno,
        comercial,
        if (codigoInterno.isNotEmpty && descricao.isNotEmpty)
          '$codigoInterno - $descricao',
      ]);
    }

    return false;
  }

  static CommercialAdjustmentRule? resolvePriorityRuleForProduct(
    List<CommercialAdjustmentRule> rules,
    Produto product,
  ) {
    for (final rule in rules) {
      if (ruleMatchesProduct(rule, product)) {
        return rule;
      }
    }
    return null;
  }

  static ComputedPedidoItemValues applyCommercialRule({
    required List<CommercialAdjustmentRule> rules,
    required ComputedPedidoItemValues baseValues,
    required Produto product,
    required double quantity,
  }) {
    final rule = resolvePriorityRuleForProduct(rules, product);
    if (rule == null) {
      return baseValues;
    }

    final safeQuantity = quantity <= 0 ? 1 : quantity;
    var unitPrice = baseValues.unitPrice;
    final valueType = rule.valueType.trim().toLowerCase();
    final adjustmentType = rule.adjustmentType.trim().toLowerCase();
    final amount = rule.value;

    if (valueType == 'percent') {
      final factor = adjustmentType == 'discount'
          ? (1 - (amount / 100))
          : (1 + (amount / 100));
      unitPrice = PedidoFormatUtils.roundCurrency(
        baseValues.unitPrice * factor,
      );
    } else {
      final delta = adjustmentType == 'discount' ? -amount : amount;
      unitPrice = PedidoFormatUtils.roundCurrency(baseValues.unitPrice + delta);
    }

    if (unitPrice < 0) {
      unitPrice = 0;
    }

    final unitDiff = unitPrice - baseValues.unitPrice;
    var totalPrice = PedidoFormatUtils.roundCurrency(
      baseValues.totalPrice + (unitDiff * safeQuantity),
    );
    if (totalPrice < 0) {
      totalPrice = 0;
    }

    final snapshot = baseValues.taxSnapshot.copyWith(
      valorTotalItem: totalPrice,
    );

    return ComputedPedidoItemValues(
      unitPrice: unitPrice,
      totalPrice: totalPrice,
      taxSnapshot: snapshot,
      usedFallback: baseValues.usedFallback,
    );
  }

  static ComputedPedidoItemValues applyPointDiscounts({
    required ComputedPedidoItemValues baseValues,
    required List<double> discountPercents,
  }) {
    if (discountPercents.isEmpty) {
      return baseValues;
    }

    var unitPrice = baseValues.unitPrice;
    var totalPrice = baseValues.totalPrice;
    for (final discount in discountPercents) {
      final safeDiscount = discount < 0 ? 0 : discount;
      if (safeDiscount <= 0) {
        continue;
      }
      final factor = 1 - (safeDiscount / 100);
      unitPrice = PedidoFormatUtils.roundCurrency(unitPrice * factor);
      totalPrice = PedidoFormatUtils.roundCurrency(totalPrice * factor);
    }

    if (unitPrice < 0) {
      unitPrice = 0;
    }
    if (totalPrice < 0) {
      totalPrice = 0;
    }

    final snapshot = baseValues.taxSnapshot.copyWith(
      valorTotalItem: totalPrice,
    );
    return ComputedPedidoItemValues(
      unitPrice: unitPrice,
      totalPrice: totalPrice,
      taxSnapshot: snapshot,
      usedFallback: baseValues.usedFallback,
    );
  }

  static double applyDiscountPercentsToUnitPrice({
    required double unitPrice,
    required List<double> discountPercents,
  }) {
    if (discountPercents.isEmpty) {
      return unitPrice;
    }

    var adjusted = unitPrice;
    for (final discount in discountPercents) {
      final safeDiscount = discount < 0 ? 0 : discount;
      if (safeDiscount <= 0) {
        continue;
      }
      adjusted = PedidoFormatUtils.roundCurrency(
        adjusted * (1 - (safeDiscount / 100)),
      );
    }
    if (adjusted < 0) {
      return 0;
    }
    return adjusted;
  }
}
