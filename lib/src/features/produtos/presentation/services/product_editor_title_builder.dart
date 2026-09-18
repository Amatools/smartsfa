class ProductEditorTitleBuilder {
  static String build({
    required String tenantName,
    required String? representedCompanyName,
    required bool isNew,
  }) {
    final companyName = (representedCompanyName ?? '').trim();
    final normalizedTenantName = tenantName.trim();
    final targetName = companyName.isNotEmpty ? companyName : normalizedTenantName;
    final base = isNew ? 'Novo Produto' : 'Editar Produto';
    return targetName.isEmpty ? base : '$base - $targetName';
  }
}