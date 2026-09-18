import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';
import 'product_default_price_sync_service.dart';
import 'product_editor_delete_execution_coordinator.dart';
import 'product_editor_delete_outcome_coordinator.dart';
import 'product_editor_initialization_coordinator.dart';
import 'product_editor_save_flow_coordinator.dart';
import 'product_editor_save_outcome_coordinator.dart';

class ProductEditorActionFlowCoordinator {
  const ProductEditorActionFlowCoordinator({
    this.saveFlowCoordinator = const ProductEditorSaveFlowCoordinator(),
    this.saveOutcomeCoordinator = const ProductEditorSaveOutcomeCoordinator(),
    this.deleteExecutionCoordinator =
        const ProductEditorDeleteExecutionCoordinator(),
    this.deleteOutcomeCoordinator =
        const ProductEditorDeleteOutcomeCoordinator(),
  });

  final ProductEditorSaveFlowCoordinator saveFlowCoordinator;
  final ProductEditorSaveOutcomeCoordinator saveOutcomeCoordinator;
  final ProductEditorDeleteExecutionCoordinator deleteExecutionCoordinator;
  final ProductEditorDeleteOutcomeCoordinator deleteOutcomeCoordinator;

  Future<ProductEditorSaveOutcomeUiAction> executeSave({
    required ProdutoRepository repository,
    required AppIdentity identity,
    required Produto? existingProduct,
    required bool createAnother,
    required bool isEnterprise,
    required ProductStatus status,
    required String currencyCode,
    required String tablePriceText,
    required ProductEditorFormControllers controllers,
    required bool imageExplicitlyCleared,
    required List<String> availableBrands,
    required String bitolaUnit,
    required String? currentImageStoragePath,
    required String? currentImageThumbBase64,
    required Future<void> Function(Produto entity) syncDefaultTablePrice,
    required List<Produto> existingProducts,
    required String defaultCurrencyCode,
    required String requiredDescriptionMessage,
    required String requiredTablePriceMessage,
    required String unknownErrorMessage,
    required VoidCallback onSaveStarted,
  }) async {
    final outcome = await saveFlowCoordinator.execute(
      repository: repository,
      identity: identity,
      existingProduct: existingProduct,
      createAnother: createAnother,
      isEnterprise: isEnterprise,
      status: status,
      currencyCode: currencyCode,
      tablePriceText: tablePriceText,
      controllers: controllers,
      imageExplicitlyCleared: imageExplicitlyCleared,
      availableBrands: availableBrands,
      bitolaUnit: bitolaUnit,
      currentImageStoragePath: currentImageStoragePath,
      currentImageThumbBase64: currentImageThumbBase64,
      syncDefaultTablePrice: syncDefaultTablePrice,
      existingProducts: existingProducts,
      defaultCurrencyCode: defaultCurrencyCode,
      requiredDescriptionMessage: requiredDescriptionMessage,
      requiredTablePriceMessage: requiredTablePriceMessage,
      unknownErrorMessage: unknownErrorMessage,
      onSaveStarted: onSaveStarted,
    );

    return saveOutcomeCoordinator.resolve(outcome);
  }

  Future<ProductEditorDeleteOutcomeUiAction> confirmAndExecuteDelete({
    required BuildContext context,
    required Produto existing,
    required String tenantId,
    required ProdutoRepository repository,
    required ProductDefaultPriceSyncService defaultPriceSyncService,
    required String unknownErrorMessage,
    required VoidCallback onExecutionStarted,
  }) async {
    final outcome = await deleteExecutionCoordinator.confirmAndExecute(
      context: context,
      existing: existing,
      tenantId: tenantId,
      repository: repository,
      defaultPriceSyncService: defaultPriceSyncService,
      onExecutionStarted: onExecutionStarted,
    );

    return deleteOutcomeCoordinator.resolve(
      outcome: outcome,
      unknownErrorMessage: unknownErrorMessage,
    );
  }
}
