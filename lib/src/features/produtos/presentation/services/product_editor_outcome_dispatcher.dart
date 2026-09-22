import 'package:flutter/foundation.dart';

import '../../../../core/models/produto.dart';
import 'product_editor_delete_outcome_coordinator.dart';
import 'product_editor_form_reset_coordinator.dart';
import 'product_editor_save_outcome_coordinator.dart';

class ProductEditorOutcomeDispatcher {
  const ProductEditorOutcomeDispatcher();

  void dispatchSave({
    required ProductEditorSaveOutcomeUiAction action,
    required void Function(String message) onFeedback,
    required void Function(ProductEditorFormResetValues resetValues)
    onApplyResetValues,
    required ValueChanged<Produto> onSaved,
    required void Function() onStopSaving,
  }) {
    for (final message in action.feedbackMessages) {
      onFeedback(message);
    }

    final resetValues = action.resetValues;
    if (resetValues != null) {
      onApplyResetValues(resetValues);
    }

    final savedEntity = action.savedEntity;
    if (savedEntity != null) {
      onSaved(savedEntity);
      return;
    }

    if (action.shouldStopSaving) {
      onStopSaving();
    }
  }

  void dispatchDelete({
    required ProductEditorDeleteOutcomeUiAction action,
    required void Function(String message) onFeedback,
    required void Function() onCloseEditor,
    required void Function() onDeleted,
    required void Function() onStopSaving,
  }) {
    final feedbackMessage = action.feedbackMessage;
    if (feedbackMessage != null) {
      onFeedback(feedbackMessage);
    }

    switch (action.followUpAction) {
      case ProductEditorDeleteFollowUpAction.none:
        break;
      case ProductEditorDeleteFollowUpAction.closeEditor:
        onCloseEditor();
        return;
      case ProductEditorDeleteFollowUpAction.notifyDeleted:
        onDeleted();
        return;
    }

    if (action.shouldStopSaving) {
      onStopSaving();
    }
  }
}
