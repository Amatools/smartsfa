import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';
import 'product_editor_save_coordinator.dart';
import 'product_editor_save_validation.dart';
import 'product_form_value_codec.dart';

class ProductEditorSaveCommandBuildResult {
  const ProductEditorSaveCommandBuildResult._({
    this.command,
    this.validationMessage,
  });

  const ProductEditorSaveCommandBuildResult.command(
    ProductEditorSaveCommand command,
  ) : this._(command: command);

  const ProductEditorSaveCommandBuildResult.validationError(String message)
    : this._(validationMessage: message);

  final ProductEditorSaveCommand? command;
  final String? validationMessage;
}

class ProductEditorSaveCommandBuilder {
  const ProductEditorSaveCommandBuilder();

  ProductEditorSaveCommandBuildResult build({
    required ProdutoRepository repository,
    required AppIdentity identity,
    required String? representedCompanyId,
    required Produto? existing,
    required bool createAnother,
    required bool isEnterprise,
    required ProductStatus status,
    required String currencyCode,
    required String tablePriceText,
    required ProductEditorSaveFormData formData,
    required Future<void> Function(Produto entity) syncDefaultTablePrice,
    required String requiredDescriptionMessage,
    required String requiredTablePriceMessage,
    required String requiredCategoryMessage,
    required String requiredSubcategoryMessage,
  }) {
    final tablePrice = ProductFormValueCodec.parseDecimal(tablePriceText);
    final validationMessage = ProductEditorSaveValidation.validateRequired(
      descricao: formData.descricaoText,
      tablePrice: tablePrice,
      categoria: formData.categoriaText,
      subcategoria: formData.subcategoriaText,
      requiredDescriptionMessage: requiredDescriptionMessage,
      requiredTablePriceMessage: requiredTablePriceMessage,
      requiredCategoryMessage: requiredCategoryMessage,
      requiredSubcategoryMessage: requiredSubcategoryMessage,
    );

    if (validationMessage != null) {
      return ProductEditorSaveCommandBuildResult.validationError(
        validationMessage,
      );
    }

    if (tablePrice == null) {
      return ProductEditorSaveCommandBuildResult.validationError(
        requiredTablePriceMessage,
      );
    }

    return ProductEditorSaveCommandBuildResult.command(
      ProductEditorSaveCommand(
        repository: repository,
        identity: identity,
        representedCompanyId: representedCompanyId,
        existing: existing,
        createAnother: createAnother,
        isEnterprise: isEnterprise,
        status: status,
        currencyCode: currencyCode,
        tablePrice: tablePrice,
        formData: formData,
        syncDefaultTablePrice: syncDefaultTablePrice,
      ),
    );
  }
}
