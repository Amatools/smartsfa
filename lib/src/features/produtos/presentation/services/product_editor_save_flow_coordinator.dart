import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';
import 'product_editor_feedback.dart';
import 'product_editor_form_reset_coordinator.dart';
import 'product_editor_initialization_coordinator.dart';
import 'product_editor_post_save_coordinator.dart';
import 'product_editor_save_command_builder.dart';
import 'product_editor_save_coordinator.dart';
import 'product_editor_save_form_data_builder.dart';
import 'product_editor_save_result_coordinator.dart';

enum ProductEditorSaveFlowOutcomeType {
  validationFailed,
  failed,
  savedAndClose,
  savedAndCreateAnother,
  stopSaving,
}

class ProductEditorSaveFlowOutcome {
  const ProductEditorSaveFlowOutcome({
    required this.type,
    this.savedEntity,
    this.resetValues,
    this.validationFeedbackMessage,
    this.failureFeedbackMessage,
    this.successFeedbackMessage,
    this.syncFeedbackMessage,
  });

  final ProductEditorSaveFlowOutcomeType type;
  final Produto? savedEntity;
  final ProductEditorFormResetValues? resetValues;
  final String? validationFeedbackMessage;
  final String? failureFeedbackMessage;
  final String? successFeedbackMessage;
  final String? syncFeedbackMessage;
}

class ProductEditorSaveFlowCoordinator {
  const ProductEditorSaveFlowCoordinator({
    this.saveFormDataBuilder = const ProductEditorSaveFormDataBuilder(),
    this.saveCommandBuilder = const ProductEditorSaveCommandBuilder(),
    this.saveCoordinator = const ProductEditorSaveCoordinator(),
    this.saveResultCoordinator = const ProductEditorSaveResultCoordinator(),
    this.postSaveCoordinator = const ProductEditorPostSaveCoordinator(),
  });

  final ProductEditorSaveFormDataBuilder saveFormDataBuilder;
  final ProductEditorSaveCommandBuilder saveCommandBuilder;
  final ProductEditorSaveCoordinator saveCoordinator;
  final ProductEditorSaveResultCoordinator saveResultCoordinator;
  final ProductEditorPostSaveCoordinator postSaveCoordinator;

  Future<ProductEditorSaveFlowOutcome> execute({
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
    final formData = saveFormDataBuilder.build(
      controllers: controllers,
      imageExplicitlyCleared: imageExplicitlyCleared,
      availableBrands: availableBrands,
      bitolaUnit: bitolaUnit,
      currentImageStoragePath: currentImageStoragePath,
      currentImageThumbBase64: currentImageThumbBase64,
    );

    final commandBuildResult = saveCommandBuilder.build(
      repository: repository,
      identity: identity,
      existing: existingProduct,
      createAnother: createAnother,
      isEnterprise: isEnterprise,
      status: status,
      currencyCode: currencyCode,
      tablePriceText: tablePriceText,
      formData: formData,
      syncDefaultTablePrice: syncDefaultTablePrice,
      requiredDescriptionMessage: requiredDescriptionMessage,
      requiredTablePriceMessage: requiredTablePriceMessage,
    );

    final validationMessage = commandBuildResult.validationMessage;
    if (validationMessage != null) {
      return ProductEditorSaveFlowOutcome(
        type: ProductEditorSaveFlowOutcomeType.validationFailed,
        validationFeedbackMessage: validationMessage,
      );
    }

    final command = commandBuildResult.command;
    if (command == null) {
      return const ProductEditorSaveFlowOutcome(
        type: ProductEditorSaveFlowOutcomeType.stopSaving,
      );
    }

    onSaveStarted();

    final executionResult = await saveCoordinator.execute(command);
    final resultOutcome = saveResultCoordinator.resolve(
      executionResult: executionResult,
      unknownErrorMessage: unknownErrorMessage,
    );

    switch (resultOutcome.type) {
      case ProductEditorSaveResultOutcomeType.failed:
        return ProductEditorSaveFlowOutcome(
          type: ProductEditorSaveFlowOutcomeType.failed,
          syncFeedbackMessage: resultOutcome.syncFeedbackMessage,
          failureFeedbackMessage: resultOutcome.failureFeedbackMessage,
        );
      case ProductEditorSaveResultOutcomeType.savedAndClose:
        return ProductEditorSaveFlowOutcome(
          type: ProductEditorSaveFlowOutcomeType.savedAndClose,
          savedEntity: resultOutcome.savedEntity,
          syncFeedbackMessage: resultOutcome.syncFeedbackMessage,
        );
      case ProductEditorSaveResultOutcomeType.savedAndCreateAnother:
        final savedEntity = resultOutcome.savedEntity;
        if (savedEntity == null) {
          return ProductEditorSaveFlowOutcome(
            type: ProductEditorSaveFlowOutcomeType.stopSaving,
            syncFeedbackMessage: resultOutcome.syncFeedbackMessage,
          );
        }

        final resetValues = postSaveCoordinator.prepareForCreateAnother(
          savedEntity: savedEntity,
          existingProducts: existingProducts,
          defaultCurrencyCode: defaultCurrencyCode,
          controllers: controllers,
        );

        return ProductEditorSaveFlowOutcome(
          type: ProductEditorSaveFlowOutcomeType.savedAndCreateAnother,
          savedEntity: savedEntity,
          resetValues: resetValues,
          successFeedbackMessage: ProductEditorFeedback.productSavedMessage(
            isNew: true,
          ),
          syncFeedbackMessage: resultOutcome.syncFeedbackMessage,
        );
      case ProductEditorSaveResultOutcomeType.stopSaving:
        return ProductEditorSaveFlowOutcome(
          type: ProductEditorSaveFlowOutcomeType.stopSaving,
          syncFeedbackMessage: resultOutcome.syncFeedbackMessage,
        );
    }
  }
}
