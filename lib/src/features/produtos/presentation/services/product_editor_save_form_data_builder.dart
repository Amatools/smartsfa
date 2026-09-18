import 'product_editor_initialization_coordinator.dart';
import 'product_editor_save_coordinator.dart';

class ProductEditorSaveFormDataBuilder {
  const ProductEditorSaveFormDataBuilder();

  ProductEditorSaveFormData build({
    required ProductEditorFormControllers controllers,
    required bool imageExplicitlyCleared,
    required List<String> availableBrands,
    required String bitolaUnit,
    required String? currentImageStoragePath,
    required String? currentImageThumbBase64,
  }) {
    return ProductEditorSaveFormData(
      imageExplicitlyCleared: imageExplicitlyCleared,
      fotoUrlText: controllers.fotoUrl.text,
      descricaoLongaText: controllers.descricaoLonga.text,
      codigoText: controllers.codigo.text.trim(),
      descricaoText: controllers.descricao.text.trim(),
      codigoFabricanteText: controllers.codigoFabricante.text,
      eanText: controllers.ean.text,
      marcaText: controllers.marca.text,
      availableBrands: availableBrands,
      categoriaText: controllers.categoria.text,
      subcategoriaText: controllers.subcategoria.text,
      bitolaText: controllers.bitola.text,
      bitolaUnit: bitolaUnit,
      comprimentoMmText: controllers.comprimentoMm.text,
      larguraMmText: controllers.larguraMm.text,
      alturaMmText: controllers.alturaMm.text,
      precoMinimoText: controllers.precoMinimo.text,
      unidadeText: controllers.unidade.text,
      multiploVendaText: controllers.multiploVenda.text,
      quantidadeMinimaText: controllers.quantidadeMinima.text,
      ncmText: controllers.ncm.text,
      cfopText: controllers.cfop.text,
      icmsText: controllers.icms.text,
      pisText: controllers.pis.text,
      cofinsText: controllers.cofins.text,
      pesoText: controllers.peso.text,
      erpProductIdText: controllers.erpProductId.text,
      erpSyncIdText: controllers.erpSyncId.text,
      tabelaVersaoText: controllers.tabelaVersao.text,
      estoqueVersaoText: controllers.estoqueVersao.text,
      currentImageStoragePath: currentImageStoragePath,
      currentImageThumbBase64: currentImageThumbBase64,
    );
  }
}
