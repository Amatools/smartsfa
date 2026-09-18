import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import 'product_editor_defaults.dart';

class ProductDraftFactory {
  const ProductDraftFactory();

  Produto emptyDraft({required String defaultCurrencyCode}) {
    return Produto(
      id: 'draft',
      tenantId: 'draft',
      codigoInterno: '',
      descricao: '',
      origemCadastro: ProductSource.manual,
      status: ProductStatus.active,
      descricaoResumida: '',
      sku: '',
      ean: '',
      marca: '',
      categoria: '',
      subcategoria: '',
      unidade: 'UN',
      bitolaUnidade: ProductEditorDefaults.defaultBitolaUnit,
      moeda: defaultCurrencyCode,
      multiploVenda: 1,
      quantidadeMinima: 1,
      ncm: '0000.00.00',
      cfop: '5102',
      aliquotaIcms: 0,
      aliquotaPis: 0,
      aliquotaCofins: 0,
      pesoKg: 0,
      erpProductId: '',
      erpSyncId: '',
      tabelaPrecoVersao: 'rascunho',
      estoqueVersao: 'rascunho',
    );
  }
}
