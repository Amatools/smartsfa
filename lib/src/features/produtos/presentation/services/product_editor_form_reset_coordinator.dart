import '../../../../core/models/domain_types.dart';
import 'product_editor_defaults.dart';
import 'product_editor_initialization_coordinator.dart';

class ProductEditorFormResetValues {
  const ProductEditorFormResetValues({
    required this.status,
    required this.bitolaUnit,
    required this.currencyCode,
  });

  final ProductStatus status;
  final String bitolaUnit;
  final String currencyCode;
}

class ProductEditorFormResetCoordinator {
  const ProductEditorFormResetCoordinator();

  ProductEditorFormResetValues resetAfterSave({
    required String nextCodigoInterno,
    required String unidadePadrao,
    required String defaultCurrencyCode,
    required ProductEditorFormControllers controllers,
  }) {
    controllers.codigo.text = nextCodigoInterno;
    controllers.codigoFabricante.clear();
    controllers.ean.clear();
    controllers.descricao.clear();
    controllers.precoTabela.clear();
    controllers.precoMinimo.clear();
    controllers.descricaoLonga.clear();
    controllers.marca.clear();
    controllers.categoria.clear();
    controllers.subcategoria.clear();
    controllers.bitola.clear();
    controllers.unidade.text = unidadePadrao;
    controllers.ncm.clear();
    controllers.cfop.clear();
    controllers.icms.clear();
    controllers.pis.clear();
    controllers.cofins.clear();
    controllers.peso.clear();
    controllers.comprimentoMm.clear();
    controllers.larguraMm.clear();
    controllers.alturaMm.clear();
    controllers.quantidadeMinima.clear();
    controllers.multiploVenda.clear();
    controllers.erpProductId.clear();
    controllers.erpSyncId.clear();
    controllers.tabelaVersao.text = ProductEditorDefaults.defaultManualVersion;
    controllers.estoqueVersao.text = ProductEditorDefaults.defaultManualVersion;

    return ProductEditorFormResetValues(
      status: ProductStatus.active,
      bitolaUnit: ProductEditorDefaults.defaultBitolaUnit,
      currencyCode: defaultCurrencyCode,
    );
  }
}
