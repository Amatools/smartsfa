import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';
import 'product_default_price_sync_service.dart';

enum ProductDeleteExecutionResult {
  deleted,
  deactivated,
}

class ProductEditorDeleteCoordinator {
  const ProductEditorDeleteCoordinator();

  Future<bool> confirmDelete({
    required BuildContext context,
    required Produto produto,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir produto'),
        content: Text(
          'Deseja excluir ${produto.descricao.isEmpty ? produto.codigoInterno : produto.descricao}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<ProductDeleteExecutionResult> executeDelete({
    required Produto existing,
    required String tenantId,
    required ProdutoRepository repository,
    required ProductDefaultPriceSyncService defaultPriceSyncService,
  }) async {
    await defaultPriceSyncService.deleteForProduct(productId: existing.id);

    try {
      await repository.delete(
        tenantId: tenantId,
        id: existing.id,
      );
      return ProductDeleteExecutionResult.deleted;
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }

      await repository.save(
        existing.copyWith(
          status: ProductStatus.inactive,
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      return ProductDeleteExecutionResult.deactivated;
    }
  }
}