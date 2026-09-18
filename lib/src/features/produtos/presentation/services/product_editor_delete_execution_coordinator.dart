import 'package:flutter/material.dart';

import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';
import 'product_default_price_sync_service.dart';
import 'product_editor_delete_coordinator.dart';

enum ProductEditorDeleteExecutionOutcomeType {
  cancelled,
  deleted,
  deactivated,
  failed,
}

class ProductEditorDeleteExecutionOutcome {
  const ProductEditorDeleteExecutionOutcome({required this.type, this.error});

  final ProductEditorDeleteExecutionOutcomeType type;
  final Object? error;
}

class ProductEditorDeleteExecutionCoordinator {
  const ProductEditorDeleteExecutionCoordinator({
    this._deleteCoordinator = const ProductEditorDeleteCoordinator(),
  });

  final ProductEditorDeleteCoordinator _deleteCoordinator;

  Future<ProductEditorDeleteExecutionOutcome> confirmAndExecute({
    required BuildContext context,
    required Produto existing,
    required String tenantId,
    required ProdutoRepository repository,
    required ProductDefaultPriceSyncService defaultPriceSyncService,
    required VoidCallback onExecutionStarted,
  }) async {
    final confirmed = await _deleteCoordinator.confirmDelete(
      context: context,
      produto: existing,
    );
    if (!confirmed) {
      return const ProductEditorDeleteExecutionOutcome(
        type: ProductEditorDeleteExecutionOutcomeType.cancelled,
      );
    }

    onExecutionStarted();
    return execute(
      existing: existing,
      tenantId: tenantId,
      repository: repository,
      defaultPriceSyncService: defaultPriceSyncService,
    );
  }

  Future<ProductEditorDeleteExecutionOutcome> execute({
    required Produto existing,
    required String tenantId,
    required ProdutoRepository repository,
    required ProductDefaultPriceSyncService defaultPriceSyncService,
  }) async {
    try {
      final result = await _deleteCoordinator.executeDelete(
        existing: existing,
        tenantId: tenantId,
        repository: repository,
        defaultPriceSyncService: defaultPriceSyncService,
      );

      if (result == ProductDeleteExecutionResult.deactivated) {
        return const ProductEditorDeleteExecutionOutcome(
          type: ProductEditorDeleteExecutionOutcomeType.deactivated,
        );
      }

      return const ProductEditorDeleteExecutionOutcome(
        type: ProductEditorDeleteExecutionOutcomeType.deleted,
      );
    } catch (error) {
      return ProductEditorDeleteExecutionOutcome(
        type: ProductEditorDeleteExecutionOutcomeType.failed,
        error: error,
      );
    }
  }
}
