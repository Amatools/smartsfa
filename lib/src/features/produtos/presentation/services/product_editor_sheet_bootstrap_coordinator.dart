import '../../../../core/models/app_identity.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/product_base_price_repository.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';
import 'product_default_price_sync_service.dart';
import 'product_editor_bootstrap_coordinator.dart';
import 'product_editor_default_table_price_coordinator.dart';
import 'product_editor_initialization_coordinator.dart';
import 'product_editor_view_state.dart';

class ProductEditorSheetBootstrapState {
  const ProductEditorSheetBootstrapState({
    required this.emptyDraft,
    required this.formControllers,
    required this.editorState,
    required this.defaultPriceSyncService,
    required this.defaultTablePriceCoordinator,
  });

  final Produto emptyDraft;
  final ProductEditorFormControllers formControllers;
  final ProductEditorViewState editorState;
  final ProductDefaultPriceSyncService defaultPriceSyncService;
  final ProductEditorDefaultTablePriceCoordinator defaultTablePriceCoordinator;
}

class ProductEditorSheetBootstrapCoordinator {
  const ProductEditorSheetBootstrapCoordinator({
    this.bootstrapCoordinator = const ProductEditorBootstrapCoordinator(),
  });

  final ProductEditorBootstrapCoordinator bootstrapCoordinator;

  ProductEditorSheetBootstrapState build({
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
    final bootstrap = bootstrapCoordinator.build(
      identity: identity,
      existingProduct: existingProduct,
      representedCompanyId: representedCompanyId,
      basePriceRepository: basePriceRepository,
      tableRepository: tableRepository,
      existingProducts: existingProducts,
      defaultCurrencyCode: defaultCurrencyCode,
      currencyLabels: currencyLabels,
      bitolaUnits: bitolaUnits,
    );

    final initializationState = bootstrap.initializationState;

    return ProductEditorSheetBootstrapState(
      emptyDraft: bootstrap.emptyDraft,
      formControllers: initializationState.controllers,
      editorState: ProductEditorViewState.initial(
        status: initializationState.status,
        bitolaUnit: initializationState.bitolaUnit,
        currencyCode: initializationState.currencyCode,
        currentImageStoragePath: initializationState.currentImageStoragePath,
        currentImageThumbBase64: initializationState.currentImageThumbBase64,
      ),
      defaultPriceSyncService: bootstrap.defaultPriceSyncService,
      defaultTablePriceCoordinator: bootstrap.defaultTablePriceCoordinator,
    );
  }
}
