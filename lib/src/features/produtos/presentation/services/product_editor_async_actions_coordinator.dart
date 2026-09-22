import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';
import 'product_default_price_sync_service.dart';
import 'product_editor_action_flow_coordinator.dart';
import 'product_editor_default_table_price_coordinator.dart';
import 'product_editor_delete_outcome_coordinator.dart';
import 'product_editor_integration_flow_coordinator.dart';
import 'product_editor_initialization_coordinator.dart';
import 'product_editor_media_upload_coordinator.dart';
import 'product_editor_save_outcome_coordinator.dart';
import 'product_editor_view_state.dart';
import 'product_media_editor_coordinator.dart';
import 'product_media_upload_service.dart';

class ProductEditorAsyncActionsCoordinator {
  const ProductEditorAsyncActionsCoordinator({
    this.actionFlowCoordinator = const ProductEditorActionFlowCoordinator(),
    this.integrationFlowCoordinator =
        const ProductEditorIntegrationFlowCoordinator(),
  });

  final ProductEditorActionFlowCoordinator actionFlowCoordinator;
  final ProductEditorIntegrationFlowCoordinator integrationFlowCoordinator;

  Future<ProductEditorMediaIntegrationUiAction> openMediaLibrary({
    required BuildContext context,
    required ProductEditorViewState state,
    required String selectedUrl,
    required String tenantId,
    required String? representedCompanyId,
    required String? representedCompanyName,
    required String scopeKey,
    required ProductMediaEditorCoordinator mediaEditorCoordinator,
    required ProductEditorMediaUploadCoordinator mediaUploadCoordinator,
    required ProductMediaUploadService uploadService,
    required bool Function() isUploadingImage,
    required void Function(bool value) onUploadingChanged,
  }) {
    return integrationFlowCoordinator.openMediaLibrary(
      context: context,
      state: state,
      selectedUrl: selectedUrl,
      tenantId: tenantId,
      representedCompanyId: representedCompanyId,
      representedCompanyName: representedCompanyName,
      scopeKey: scopeKey,
      mediaEditorCoordinator: mediaEditorCoordinator,
      mediaUploadCoordinator: mediaUploadCoordinator,
      uploadService: uploadService,
      isUploadingImage: isUploadingImage,
      onUploadingChanged: onUploadingChanged,
    );
  }

  Future<ProductEditorSaveOutcomeUiAction> save({
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
  }) {
    return actionFlowCoordinator.executeSave(
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
  }

  Future<ProductEditorDeleteOutcomeUiAction?> delete({
    required BuildContext context,
    required Produto? existingProduct,
    required String tenantId,
    required ProdutoRepository repository,
    required ProductDefaultPriceSyncService defaultPriceSyncService,
    required String unknownErrorMessage,
    required VoidCallback onExecutionStarted,
  }) async {
    final existing = existingProduct;
    if (existing == null) {
      return null;
    }

    return actionFlowCoordinator.confirmAndExecuteDelete(
      context: context,
      existing: existing,
      tenantId: tenantId,
      repository: repository,
      defaultPriceSyncService: defaultPriceSyncService,
      unknownErrorMessage: unknownErrorMessage,
      onExecutionStarted: onExecutionStarted,
    );
  }

  Future<ProductEditorDefaultTableLoadUiAction?> loadDefaultTablePrice({
    required ProductEditorDefaultTablePriceCoordinator
    defaultTablePriceCoordinator,
    required ProductEditorViewState state,
    required Produto? existingProduct,
    required String currentCurrencyCode,
    required Map<String, String> currencyLabels,
    required void Function(bool isLoading) onLoadingChanged,
  }) {
    return integrationFlowCoordinator.loadDefaultTablePrice(
      defaultTablePriceCoordinator: defaultTablePriceCoordinator,
      state: state,
      existingProduct: existingProduct,
      currentCurrencyCode: currentCurrencyCode,
      currencyLabels: currencyLabels,
      onLoadingChanged: onLoadingChanged,
    );
  }

  Future<void> syncDefaultTablePrice({
    required ProductEditorDefaultTablePriceCoordinator
    defaultTablePriceCoordinator,
    required Produto produto,
    required String tablePriceText,
    required String currencyCode,
    required Future<void> Function() ensureDefaultTable,
  }) {
    return integrationFlowCoordinator.syncDefaultTablePrice(
      defaultTablePriceCoordinator: defaultTablePriceCoordinator,
      produto: produto,
      tablePriceText: tablePriceText,
      currencyCode: currencyCode,
      ensureDefaultTable: ensureDefaultTable,
    );
  }
}
