import '../../../core/models/customer_price_table_assignment.dart';
import '../../../core/models/customer_product_rule.dart';
import '../../../core/models/product_base_price.dart';
import '../../../core/repositories/customer_price_table_assignment_repository.dart';
import '../../../core/repositories/customer_product_rule_repository.dart';
import '../../../core/repositories/discount_policy_repository.dart';
import '../../../core/repositories/product_base_price_repository.dart';

class ProductPriceCalculationResult {
  const ProductPriceCalculationResult({
    required this.basePrice,
    required this.discountPercentage,
    required this.netPrice,
    required this.priceTableId,
    required this.regionId,
    required this.source,
    this.discountPolicyId,
  });

  final double basePrice;
  final double discountPercentage;
  final double netPrice;
  final String priceTableId;
  final String regionId;
  final String source;
  final String? discountPolicyId;
}

class ProductPriceCalculatorService {
  ProductPriceCalculatorService({
    required this.basePriceRepository,
    required this.discountPolicyRepository,
    required this.customerProductRuleRepository,
    required this.customerPriceTableAssignmentRepository,
  });

  final ProductBasePriceRepository basePriceRepository;
  final DiscountPolicyRepository discountPolicyRepository;
  final CustomerProductRuleRepository customerProductRuleRepository;
  final CustomerPriceTableAssignmentRepository customerPriceTableAssignmentRepository;

  Future<ProductPriceCalculationResult> calculateFinalPrice({
    required String tenantId,
    required String customerId,
    required String productId,
    required String regionId,
    String? fallbackPriceTableId,
    String? fallbackDiscountPolicyId,
  }) async {
    final now = DateTime.now().toUtc();
    final normalizedRegion = regionId.trim().toUpperCase();

    final assignments = await customerPriceTableAssignmentRepository.fetchAll(
      tenantId: tenantId,
    );
    final activeAssignments = assignments
        .where((item) =>
            item.customerId == customerId &&
            item.isActive &&
            _isInDateWindow(item.validFrom, item.validUntil, now))
        .toList(growable: false);

    final chosenAssignment = _pickAssignmentByRegion(
      activeAssignments,
      normalizedRegion,
    );

    final chosenPriceTableId = (chosenAssignment?.priceTableId ?? fallbackPriceTableId ?? '')
        .trim();
    if (chosenPriceTableId.isEmpty) {
      throw StateError('Nenhuma tabela de preco encontrada para o cliente.');
    }

    final basePrices = await basePriceRepository.fetchAll(tenantId: tenantId);
    final selectedBasePrice = _pickBasePrice(
      basePrices,
      productId: productId,
      priceTableId: chosenPriceTableId,
      regionId: normalizedRegion,
      now: now,
    );

    if (selectedBasePrice == null) {
      throw StateError('Preco base nao encontrado para produto/regiao/tabela.');
    }

    final customerRules = await customerProductRuleRepository.fetchAll(tenantId: tenantId);
    final matchingRule = _pickCustomerRule(
      customerRules,
      customerId: customerId,
      productId: productId,
      now: now,
    );

    final discountPolicyId =
        (matchingRule?.discountPolicyId ?? fallbackDiscountPolicyId ?? '').trim();

    var discountPercentage = 0.0;
    if (discountPolicyId.isNotEmpty) {
      final policy = await discountPolicyRepository.fetchById(
        tenantId: tenantId,
        id: discountPolicyId,
      );
      if (policy != null && policy.isActive) {
        discountPercentage = policy.discountPercentage;
      }
    }

    final netPrice = selectedBasePrice.basePrice * (1 - (discountPercentage / 100));

    return ProductPriceCalculationResult(
      basePrice: selectedBasePrice.basePrice,
      discountPercentage: discountPercentage,
      netPrice: netPrice,
      priceTableId: selectedBasePrice.priceTableId,
      regionId: selectedBasePrice.regionId,
      source: matchingRule == null ? 'fallback' : 'customer_product_rule',
      discountPolicyId: discountPolicyId.isEmpty ? null : discountPolicyId,
    );
  }

  CustomerPriceTableAssignment? _pickAssignmentByRegion(
    List<CustomerPriceTableAssignment> items,
    String regionId,
  ) {
    final exactRegion = items
        .where((item) => (item.regionId ?? '').trim().toUpperCase() == regionId)
        .toList();
    exactRegion.sort((a, b) => b.priority.compareTo(a.priority));
    if (exactRegion.isNotEmpty) {
      return exactRegion.first;
    }

    final defaults = items.where((item) {
      final region = (item.regionId ?? '').trim();
      return region.isEmpty || item.isDefault;
    }).toList();
    defaults.sort((a, b) => b.priority.compareTo(a.priority));
    return defaults.isEmpty ? null : defaults.first;
  }

  ProductBasePrice? _pickBasePrice(
    List<ProductBasePrice> allPrices, {
    required String productId,
    required String priceTableId,
    required String regionId,
    required DateTime now,
  }) {
    final filtered = allPrices.where((item) {
      if (!item.isActive) {
        return false;
      }
      if (item.productId != productId || item.priceTableId != priceTableId) {
        return false;
      }
      return _isInDateWindow(item.validFrom, item.validUntil, now);
    }).toList();

    final exact = filtered
        .where((item) => item.regionId.trim().toUpperCase() == regionId)
        .toList();
    if (exact.isNotEmpty) {
      return exact.first;
    }

    final fallback = filtered.where((item) {
      final normalized = item.regionId.trim().toUpperCase();
      return normalized.isEmpty || normalized == 'ALL' || normalized == 'BR';
    }).toList();

    return fallback.isEmpty ? null : fallback.first;
  }

  CustomerProductRule? _pickCustomerRule(
    List<CustomerProductRule> allRules, {
    required String customerId,
    required String productId,
    required DateTime now,
  }) {
    final filtered = allRules.where((item) {
      return item.customerId == customerId &&
          item.productId == productId &&
          item.isActive &&
          _isInDateWindow(item.validFrom, item.validUntil, now);
    }).toList();

    filtered.sort((a, b) => b.priority.compareTo(a.priority));
    return filtered.isEmpty ? null : filtered.first;
  }

  bool _isInDateWindow(DateTime? validFrom, DateTime? validUntil, DateTime now) {
    if (validFrom != null && now.isBefore(validFrom)) {
      return false;
    }
    if (validUntil != null && now.isAfter(validUntil)) {
      return false;
    }
    return true;
  }
}
