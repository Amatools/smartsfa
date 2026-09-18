import '../../../../core/models/produto.dart';
import 'product_editor_form_reset_coordinator.dart';
import 'product_editor_save_flow_coordinator.dart';

class ProductEditorSaveOutcomeUiAction {
  const ProductEditorSaveOutcomeUiAction({
    required this.feedbackMessages,
    required this.shouldStopSaving,
    this.savedEntity,
    this.resetValues,
  });

  final List<String> feedbackMessages;
  final bool shouldStopSaving;
  final Produto? savedEntity;
  final ProductEditorFormResetValues? resetValues;

  bool get shouldNotifySaved => savedEntity != null;
  bool get shouldApplyReset => resetValues != null;
}

class ProductEditorSaveOutcomeCoordinator {
  const ProductEditorSaveOutcomeCoordinator();

  ProductEditorSaveOutcomeUiAction resolve(
    ProductEditorSaveFlowOutcome outcome,
  ) {
    final feedbackMessages = <String>[];
    if (outcome.syncFeedbackMessage != null) {
      feedbackMessages.add(outcome.syncFeedbackMessage!);
    }

    switch (outcome.type) {
      case ProductEditorSaveFlowOutcomeType.validationFailed:
        if (outcome.validationFeedbackMessage != null) {
          feedbackMessages.add(outcome.validationFeedbackMessage!);
        }
        return ProductEditorSaveOutcomeUiAction(
          feedbackMessages: feedbackMessages,
          shouldStopSaving: false,
        );
      case ProductEditorSaveFlowOutcomeType.failed:
        if (outcome.failureFeedbackMessage != null) {
          feedbackMessages.add(outcome.failureFeedbackMessage!);
        }
        return ProductEditorSaveOutcomeUiAction(
          feedbackMessages: feedbackMessages,
          shouldStopSaving: true,
        );
      case ProductEditorSaveFlowOutcomeType.savedAndCreateAnother:
        if (outcome.successFeedbackMessage != null) {
          feedbackMessages.add(outcome.successFeedbackMessage!);
        }
        return ProductEditorSaveOutcomeUiAction(
          feedbackMessages: feedbackMessages,
          shouldStopSaving: true,
          resetValues: outcome.resetValues,
        );
      case ProductEditorSaveFlowOutcomeType.savedAndClose:
        final savedEntity = outcome.savedEntity;
        return ProductEditorSaveOutcomeUiAction(
          feedbackMessages: feedbackMessages,
          shouldStopSaving: savedEntity == null,
          savedEntity: savedEntity,
        );
      case ProductEditorSaveFlowOutcomeType.stopSaving:
        return ProductEditorSaveOutcomeUiAction(
          feedbackMessages: feedbackMessages,
          shouldStopSaving: true,
        );
    }
  }
}
