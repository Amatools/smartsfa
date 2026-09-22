import 'package:flutter/material.dart';

import '../../../../core/models/produto.dart';
import 'product_editor_default_table_price_coordinator.dart';
import 'product_editor_local_view_state_coordinator.dart';
import 'product_editor_media_flow_coordinator.dart';
import 'product_editor_media_upload_coordinator.dart';
import 'product_editor_view_state.dart';
import 'product_media_editor_coordinator.dart';
import 'product_media_upload_service.dart';

class ProductEditorMediaIntegrationUiAction {
  const ProductEditorMediaIntegrationUiAction({
    required this.state,
    required this.fotoUrlText,
    required this.feedbackMessages,
    required this.hasStateChange,
  });

  final ProductEditorViewState state;
  final String fotoUrlText;
  final List<String> feedbackMessages;
  final bool hasStateChange;
}

class ProductEditorDefaultTableLoadUiAction {
  const ProductEditorDefaultTableLoadUiAction({
    required this.state,
    required this.tablePriceText,
  });

  final ProductEditorViewState state;
  final String tablePriceText;
}

class ProductEditorIntegrationFlowCoordinator {
  const ProductEditorIntegrationFlowCoordinator({
    this.mediaFlowCoordinator = const ProductEditorMediaFlowCoordinator(),
    this.localViewStateCoordinator =
        const ProductEditorLocalViewStateCoordinator(),
  });

  final ProductEditorMediaFlowCoordinator mediaFlowCoordinator;
  final ProductEditorLocalViewStateCoordinator localViewStateCoordinator;

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
  }) async {
    var nextState = state;
    var nextFotoUrlText = selectedUrl;
    var hasStateChange = false;
    final feedbackMessages = <String>[];

    await mediaFlowCoordinator.openLibrary(
      context: context,
      mediaEditorCoordinator: mediaEditorCoordinator,
      mediaUploadCoordinator: mediaUploadCoordinator,
      uploadService: uploadService,
      tenantId: tenantId,
      representedCompanyId: representedCompanyId,
      representedCompanyName: representedCompanyName,
      selectedUrl: selectedUrl,
      scopeKey: scopeKey,
      isUploadingImage: isUploadingImage,
      onUploadingChanged: onUploadingChanged,
      onStateReady: (mediaState) {
        final applyResult = localViewStateCoordinator.applyMediaState(
          state: nextState,
          mediaState: mediaState,
        );
        nextState = applyResult.state;
        nextFotoUrlText = applyResult.fotoUrlText;
        hasStateChange = true;
      },
      onFeedback: feedbackMessages.add,
    );

    return ProductEditorMediaIntegrationUiAction(
      state: nextState,
      fotoUrlText: nextFotoUrlText,
      feedbackMessages: feedbackMessages,
      hasStateChange: hasStateChange,
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
  }) async {
    final loadedState = await defaultTablePriceCoordinator.loadForEditor(
      existingProduct: existingProduct,
      currentCurrencyCode: currentCurrencyCode,
      currencyLabels: currencyLabels,
      onLoadingChanged: onLoadingChanged,
    );
    if (loadedState == null) {
      return null;
    }

    final applyResult = localViewStateCoordinator.applyLoadedTablePrice(
      state: state,
      loadedState: loadedState,
    );

    return ProductEditorDefaultTableLoadUiAction(
      state: applyResult.state,
      tablePriceText: applyResult.tablePriceText,
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
    return defaultTablePriceCoordinator.syncForProduct(
      produto: produto,
      tablePriceText: tablePriceText,
      currencyCode: currencyCode,
      ensureDefaultTable: ensureDefaultTable,
    );
  }

  ProductEditorMediaIntegrationUiAction applyMediaState({
    required ProductEditorViewState state,
    required ProductMediaEditorState mediaState,
  }) {
    final applyResult = localViewStateCoordinator.applyMediaState(
      state: state,
      mediaState: mediaState,
    );

    return ProductEditorMediaIntegrationUiAction(
      state: applyResult.state,
      fotoUrlText: applyResult.fotoUrlText,
      feedbackMessages: const <String>[],
      hasStateChange: true,
    );
  }
}
