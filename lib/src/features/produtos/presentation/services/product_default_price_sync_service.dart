import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/product_base_price.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/product_base_price_repository.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';
import '../../../precos/presentation/services/default_price_table_guard.dart';

class ProductDefaultPriceSyncService {
  const ProductDefaultPriceSyncService({
    required this.identity,
    required this.representedCompanyId,
    required this.basePriceRepository,
    required this.tableRepository,
  });

  final AppIdentity identity;
  final String? representedCompanyId;
  final ProductBasePriceRepository? basePriceRepository;
  final TabelaPrecoRepository? tableRepository;

  String get _defaultPriceTableId => DefaultPriceTableGuard.defaultPriceTableIdForScope(
    tenantId: identity.tenantId,
    representedCompanyId: representedCompanyId,
  );

  Future<ProductBasePrice?> loadForProduct({required String productId}) async {
    final repository = basePriceRepository;
    if (repository == null) {
      return null;
    }

    try {
      final prices = await repository.fetchAll(tenantId: identity.tenantId);
      for (final item in prices) {
        if (item.productId == productId &&
            item.priceTableId == _defaultPriceTableId &&
            item.regionId == DefaultPriceTableGuard.defaultPriceRegionId) {
          return item;
        }
      }
      return null;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }

  Future<void> saveForProduct({
    required Produto produto,
    required double price,
    required String currencyCode,
    required Future<void> Function() ensureDefaultTable,
  }) async {
    final repository = basePriceRepository;
    if (repository == null) {
      return;
    }

    await ensureDefaultTable();

    final basePriceId = 'pbp_${identity.tenantId}_${produto.id}_$_defaultPriceTableId';
    final now = DateTime.now().toUtc();
    try {
      await repository.save(
        ProductBasePrice(
          id: basePriceId,
          tenantId: identity.tenantId,
          productId: produto.id,
          priceTableId: _defaultPriceTableId,
          regionId: DefaultPriceTableGuard.defaultPriceRegionId,
          basePrice: price,
          status: 'active',
          currencyCode: currencyCode,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _refreshDefaultPriceTableRowCount();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw StateError('permissao negada ao gravar em product_base_prices');
      }
      rethrow;
    }
  }

  Future<void> deleteForProduct({required String productId}) async {
    final repository = basePriceRepository;
    if (repository == null) {
      return;
    }

    final basePriceId = 'pbp_${identity.tenantId}_${productId}_$_defaultPriceTableId';
    try {
      await repository.delete(tenantId: identity.tenantId, id: basePriceId);
      await _refreshDefaultPriceTableRowCount();
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }
    }
  }

  Future<void> _refreshDefaultPriceTableRowCount() async {
    final pricesRepository = basePriceRepository;
    final pricesTableRepository = tableRepository;
    if (pricesRepository == null || pricesTableRepository == null) {
      return;
    }

    try {
      final allBasePrices = await pricesRepository.fetchAll(tenantId: identity.tenantId);
      final rows = allBasePrices.where((item) {
        return item.priceTableId == _defaultPriceTableId && item.status == 'active';
      }).length;

      final existingTable = await pricesTableRepository.fetchById(
        tenantId: identity.tenantId,
        id: _defaultPriceTableId,
      );
      if (existingTable == null) {
        return;
      }

      await pricesTableRepository.save(
        existingTable.copyWith(
          rowCount: rows,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }
      // In read-only contexts, keep product operations working.
    }
  }
}