class ProductEditorSaveValidation {
  static String? validateRequired({
    required String descricao,
    required double? tablePrice,
    required String categoria,
    required String subcategoria,
    required String requiredDescriptionMessage,
    required String requiredTablePriceMessage,
    required String requiredCategoryMessage,
    required String requiredSubcategoryMessage,
  }) {
    if (descricao.trim().isEmpty) {
      return requiredDescriptionMessage;
    }
    if (tablePrice == null) {
      return requiredTablePriceMessage;
    }
    if (categoria.trim().isEmpty) {
      return requiredCategoryMessage;
    }
    if (subcategoria.trim().isEmpty) {
      return requiredSubcategoryMessage;
    }
    return null;
  }
}
