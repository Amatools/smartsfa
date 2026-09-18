import '../../../../core/models/produto.dart';

class ProductEditorThumbnailPreviewBuilder {
  const ProductEditorThumbnailPreviewBuilder();

  Produto build({
    required Produto? existingProduct,
    required Produto fallbackDraft,
    required String descricao,
    required String fotoUrl,
  }) {
    return (existingProduct ?? fallbackDraft).copyWith(
      descricao: descricao,
      fotoUrl: fotoUrl,
    );
  }
}
