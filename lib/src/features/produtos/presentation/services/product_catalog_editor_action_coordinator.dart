import '../../../../core/models/produto.dart';
import 'product_catalog_editor_state_coordinator.dart';
import 'product_catalog_feedback.dart';

class ProductCatalogEditorActionOutcome {
  const ProductCatalogEditorActionOutcome({
    required this.editorState,
    required this.feedbackMessage,
  });

  final ProductCatalogEditorState editorState;
  final String feedbackMessage;
}

class ProductCatalogEditorActionCoordinator {
  const ProductCatalogEditorActionCoordinator({
    this.editorStateCoordinator = const ProductCatalogEditorStateCoordinator(),
  });

  final ProductCatalogEditorStateCoordinator editorStateCoordinator;

  ProductCatalogEditorState openEditor({
    required Produto? produto,
    required String currentBrandFilter,
  }) {
    return editorStateCoordinator.openEditor(
      produto: produto,
      currentBrandFilter: currentBrandFilter,
    );
  }

  ProductCatalogEditorState closeEditor({required String currentBrandFilter}) {
    return editorStateCoordinator.closeEditor(
      currentBrandFilter: currentBrandFilter,
    );
  }

  ProductCatalogEditorActionOutcome onSaved({required bool isNew}) {
    return ProductCatalogEditorActionOutcome(
      editorState: editorStateCoordinator.afterSave(),
      feedbackMessage: ProductCatalogFeedback.productSavedMessage(isNew: isNew),
    );
  }

  ProductCatalogEditorActionOutcome onDeleted({
    required String currentBrandFilter,
  }) {
    return ProductCatalogEditorActionOutcome(
      editorState: editorStateCoordinator.afterDelete(
        currentBrandFilter: currentBrandFilter,
      ),
      feedbackMessage: ProductCatalogFeedback.productDeletedMessage,
    );
  }
}
