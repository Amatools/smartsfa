class ProductEditorSaveValidation {
  static String? validateRequired({
    required String descricao,
    required double? tablePrice,
    required String requiredDescriptionMessage,
    required String requiredTablePriceMessage,
  }) {
    if (descricao.trim().isEmpty) {
      return requiredDescriptionMessage;
    }
    if (tablePrice == null) {
      return requiredTablePriceMessage;
    }
    return null;
  }
}