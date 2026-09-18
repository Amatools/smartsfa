import '../../../../core/models/produto.dart';
import 'product_draft_factory.dart';
import 'product_editor_form_reset_coordinator.dart';
import 'product_editor_initialization_coordinator.dart';
import 'product_internal_code_generator.dart';

class ProductEditorPostSaveCoordinator {
  const ProductEditorPostSaveCoordinator({
    this._draftFactory = const ProductDraftFactory(),
    this._internalCodeGenerator = const ProductInternalCodeGenerator(),
    this._formResetCoordinator = const ProductEditorFormResetCoordinator(),
  });

  final ProductDraftFactory _draftFactory;
  final ProductInternalCodeGenerator _internalCodeGenerator;
  final ProductEditorFormResetCoordinator _formResetCoordinator;

  ProductEditorFormResetValues prepareForCreateAnother({
    required Produto savedEntity,
    required List<Produto> existingProducts,
    required String defaultCurrencyCode,
    required ProductEditorFormControllers controllers,
  }) {
    final nextDraft = _draftFactory
        .emptyDraft(defaultCurrencyCode: defaultCurrencyCode)
        .copyWith(
          codigoInterno: _internalCodeGenerator.buildNextProductCode([
            ...existingProducts,
            savedEntity,
          ]),
        );

    return _formResetCoordinator.resetAfterSave(
      nextCodigoInterno: nextDraft.codigoInterno,
      unidadePadrao: nextDraft.unidade ?? 'UN',
      defaultCurrencyCode: defaultCurrencyCode,
      controllers: controllers,
    );
  }
}
