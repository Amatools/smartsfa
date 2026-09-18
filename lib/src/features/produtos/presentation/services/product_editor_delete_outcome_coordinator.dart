import 'product_editor_delete_execution_coordinator.dart';
import 'product_editor_feedback.dart';

enum ProductEditorDeleteFollowUpAction { none, closeEditor, notifyDeleted }

class ProductEditorDeleteOutcomeUiAction {
  const ProductEditorDeleteOutcomeUiAction({
    required this.feedbackMessage,
    required this.shouldStopSaving,
    required this.followUpAction,
  });

  final String? feedbackMessage;
  final bool shouldStopSaving;
  final ProductEditorDeleteFollowUpAction followUpAction;
}

class ProductEditorDeleteOutcomeCoordinator {
  const ProductEditorDeleteOutcomeCoordinator();

  ProductEditorDeleteOutcomeUiAction resolve({
    required ProductEditorDeleteExecutionOutcome outcome,
    required String unknownErrorMessage,
  }) {
    switch (outcome.type) {
      case ProductEditorDeleteExecutionOutcomeType.cancelled:
        return const ProductEditorDeleteOutcomeUiAction(
          feedbackMessage: null,
          shouldStopSaving: false,
          followUpAction: ProductEditorDeleteFollowUpAction.none,
        );
      case ProductEditorDeleteExecutionOutcomeType.deactivated:
        return const ProductEditorDeleteOutcomeUiAction(
          feedbackMessage:
              ProductEditorFeedback.deletePermissionFallbackMessage,
          shouldStopSaving: false,
          followUpAction: ProductEditorDeleteFollowUpAction.closeEditor,
        );
      case ProductEditorDeleteExecutionOutcomeType.deleted:
        return const ProductEditorDeleteOutcomeUiAction(
          feedbackMessage: null,
          shouldStopSaving: false,
          followUpAction: ProductEditorDeleteFollowUpAction.notifyDeleted,
        );
      case ProductEditorDeleteExecutionOutcomeType.failed:
        return ProductEditorDeleteOutcomeUiAction(
          feedbackMessage: ProductEditorFeedback.deleteFailureMessage(
            outcome.error ?? unknownErrorMessage,
          ),
          shouldStopSaving: true,
          followUpAction: ProductEditorDeleteFollowUpAction.none,
        );
    }
  }
}
