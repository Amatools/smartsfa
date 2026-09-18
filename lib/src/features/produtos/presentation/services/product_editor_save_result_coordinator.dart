import '../../../../core/models/produto.dart';
import 'product_editor_feedback.dart';
import 'product_editor_save_coordinator.dart';

enum ProductEditorSaveResultOutcomeType {
  failed,
  savedAndClose,
  savedAndCreateAnother,
  stopSaving,
}

class ProductEditorSaveResultOutcome {
  const ProductEditorSaveResultOutcome({
    required this.type,
    this.savedEntity,
    this.syncFeedbackMessage,
    this.failureFeedbackMessage,
  });

  final ProductEditorSaveResultOutcomeType type;
  final Produto? savedEntity;
  final String? syncFeedbackMessage;
  final String? failureFeedbackMessage;
}

class ProductEditorSaveResultCoordinator {
  const ProductEditorSaveResultCoordinator();

  ProductEditorSaveResultOutcome resolve({
    required ProductEditorSaveExecutionResult executionResult,
    required String unknownErrorMessage,
  }) {
    final syncFeedbackMessage = _buildSyncFeedbackMessage(
      executionResult.syncError,
    );

    switch (executionResult.type) {
      case ProductEditorSaveExecutionResultType.failed:
        return ProductEditorSaveResultOutcome(
          type: ProductEditorSaveResultOutcomeType.failed,
          syncFeedbackMessage: syncFeedbackMessage,
          failureFeedbackMessage:
              executionResult.failureMessage ??
              ProductEditorFeedback.saveFailureMessage(unknownErrorMessage),
        );
      case ProductEditorSaveExecutionResultType.savedAndCreateAnother:
        return _buildSavedOutcome(
          entity: executionResult.entity,
          successType: ProductEditorSaveResultOutcomeType.savedAndCreateAnother,
          syncFeedbackMessage: syncFeedbackMessage,
        );
      case ProductEditorSaveExecutionResultType.savedAndClose:
        return _buildSavedOutcome(
          entity: executionResult.entity,
          successType: ProductEditorSaveResultOutcomeType.savedAndClose,
          syncFeedbackMessage: syncFeedbackMessage,
        );
    }
  }

  String? _buildSyncFeedbackMessage(Object? syncError) {
    if (syncError == null) {
      return null;
    }
    return ProductEditorFeedback.syncDefaultTableFailureMessage(syncError);
  }

  ProductEditorSaveResultOutcome _buildSavedOutcome({
    required Produto? entity,
    required ProductEditorSaveResultOutcomeType successType,
    required String? syncFeedbackMessage,
  }) {
    if (entity == null) {
      return ProductEditorSaveResultOutcome(
        type: ProductEditorSaveResultOutcomeType.stopSaving,
        syncFeedbackMessage: syncFeedbackMessage,
      );
    }

    return ProductEditorSaveResultOutcome(
      type: successType,
      savedEntity: entity,
      syncFeedbackMessage: syncFeedbackMessage,
    );
  }
}
