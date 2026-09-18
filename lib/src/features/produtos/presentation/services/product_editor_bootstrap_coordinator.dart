import '../../../../core/models/app_identity.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/product_base_price_repository.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';
import 'product_default_price_sync_service.dart';
import 'product_draft_factory.dart';
import 'product_editor_default_table_price_coordinator.dart';
import 'product_editor_initialization_coordinator.dart';
import 'product_internal_code_generator.dart';

class ProductEditorBootstrapResult {
  const ProductEditorBootstrapResult({
    required this.emptyDraft,
    required this.initializationState,
    required this.defaultPriceSyncService,
    required this.defaultTablePriceCoordinator,
  });

  final Produto emptyDraft;
  final ProductEditorInitializationState initializationState;
  final ProductDefaultPriceSyncService defaultPriceSyncService;
  final ProductEditorDefaultTablePriceCoordinator defaultTablePriceCoordinator;
}

class ProductEditorBootstrapCoordinator {
  const ProductEditorBootstrapCoordinator({
    this.draftFactory = const ProductDraftFactory(),
    this.internalCodeGenerator = const ProductInternalCodeGenerator(),
    this.initializationCoordinator =
        const ProductEditorInitializationCoordinator(),
  });

  final ProductDraftFactory draftFactory;
  final ProductInternalCodeGenerator internalCodeGenerator;
  final ProductEditorInitializationCoordinator initializationCoordinator;

  ProductEditorBootstrapResult build({
    required AppIdentity identity,
    required Produto? existingProduct,
    required String? representedCompanyId,
    required ProductBasePriceRepository? basePriceRepository,
    required TabelaPrecoRepository? tableRepository,
    required List<Produto> existingProducts,
    required String defaultCurrencyCode,
    required Map<String, String> currencyLabels,
    required List<String> bitolaUnits,
  }) {
    final emptyDraft = draftFactory.emptyDraft(
      defaultCurrencyCode: defaultCurrencyCode,
    );
    final initializationState = initializationCoordinator.build(
      existingProduct: existingProduct,
      emptyDraft: emptyDraft,
      nextCodigoInterno: internalCodeGenerator.buildNextProductCode(
        existingProducts,
      ),
      defaultCurrencyCode: defaultCurrencyCode,
      currencyLabels: currencyLabels,
      bitolaUnits: bitolaUnits,
    );

    final defaultPriceSyncService = ProductDefaultPriceSyncService(
      identity: identity,
      representedCompanyId: representedCompanyId,
      basePriceRepository: basePriceRepository,
      tableRepository: tableRepository,
    );

    return ProductEditorBootstrapResult(
      emptyDraft: emptyDraft,
      initializationState: initializationState,
      defaultPriceSyncService: defaultPriceSyncService,
      defaultTablePriceCoordinator: ProductEditorDefaultTablePriceCoordinator(
        defaultPriceSyncService: defaultPriceSyncService,
      ),
    );
  }
}
