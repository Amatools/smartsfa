import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/models/produto.dart';
import 'product_default_price_sync_service.dart';
import 'product_editor_default_table_price_loader.dart';
import 'product_form_value_codec.dart';

class ProductEditorDefaultTablePriceCoordinator {
  const ProductEditorDefaultTablePriceCoordinator({
    required this.defaultPriceSyncService,
  });

  final ProductDefaultPriceSyncService defaultPriceSyncService;

  Future<ProductEditorDefaultTablePriceState?> loadForEditor({
    required Produto? existingProduct,
    required String currentCurrencyCode,
    required Map<String, String> currencyLabels,
    required void Function(bool isLoading) onLoadingChanged,
  }) async {
    if (existingProduct == null) {
      return null;
    }

    onLoadingChanged(true);
    try {
      final selected = await defaultPriceSyncService.loadForProduct(
        productId: existingProduct.id,
      );
      if (selected == null) {
        return null;
      }

      return ProductEditorDefaultTablePriceLoader.fromBasePrice(
        selected: selected,
        currentCurrencyCode: currentCurrencyCode,
        currencyLabels: currencyLabels,
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return null;
      }
      rethrow;
    } finally {
      onLoadingChanged(false);
    }
  }

  Future<void> syncForProduct({
    required Produto produto,
    required String tablePriceText,
    required String currencyCode,
    required Future<void> Function() ensureDefaultTable,
  }) async {
    final typedPrice = ProductFormValueCodec.parseDecimal(tablePriceText);
    final price = typedPrice ?? produto.valorBruto ?? 0;
    await defaultPriceSyncService.saveForProduct(
      produto: produto,
      price: price,
      currencyCode: currencyCode,
      ensureDefaultTable: ensureDefaultTable,
    );
  }
}