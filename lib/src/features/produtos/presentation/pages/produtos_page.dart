import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/data/firestore/firestore_product_base_price_repository.dart';
import '../../../../core/data/firestore/firestore_tabela_preco_repository.dart';
import '../../../../core/models/app_identity.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/product_base_price_repository.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';
import '../../../../shared/presentation/state/mounted_state_mixin.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../../../precos/presentation/services/default_price_table_guard.dart';
import '../services/product_catalog_async_flow_coordinator.dart';
import '../services/product_catalog_editor_action_coordinator.dart';
import '../services/product_catalog_editor_state_coordinator.dart';
import '../services/product_catalog_erp_disable_flow_coordinator.dart';
import '../services/product_catalog_erp_products_deactivation_coordinator.dart';
import '../services/product_catalog_feedback.dart';
import '../services/product_catalog_page_view_state.dart';
import '../services/product_list_price_formatter.dart';
import '../widgets/disable_erp_sync_dialog.dart';
import '../widgets/product_catalog_workspace_section.dart';
import '../widgets/product_import_sheet.dart';

const String _defaultCurrencyCode = 'BRL';

const Map<String, String> _currencyLabels = <String, String>{
  'BRL': 'R\$',
  'USD': 'US\$',
  'EUR': 'EUR',
};

const String _unknownErrorMessage = 'erro desconhecido';

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({
    super.key,
    required this.identity,
    required this.repository,
    this.activeRepresentedCompanyName,
    this.selectedRepresentedCompanyId,
  });

  final AppIdentity identity;
  final ProdutoRepository repository;
  final String? activeRepresentedCompanyName;
  final String? selectedRepresentedCompanyId;

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

class _ProdutosPageState extends State<ProdutosPage>
    with MountedStateMixin<ProdutosPage> {
  final WorkspaceProfileService _workspaceService = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );
  final ProductCatalogEditorActionCoordinator _editorActionCoordinator =
      const ProductCatalogEditorActionCoordinator();
  final ProductCatalogAsyncFlowCoordinator _catalogAsyncFlowCoordinator =
      const ProductCatalogAsyncFlowCoordinator();
  final ProductCatalogErpProductsDeactivationCoordinator
  _erpProductsDeactivationCoordinator =
      const ProductCatalogErpProductsDeactivationCoordinator();
  late final TabelaPrecoRepository? _priceTableRepository;
  late final ProductBasePriceRepository? _basePriceRepository;

  ProductCatalogPageViewState _catalogState =
      ProductCatalogPageViewState.initial();
  final Set<String> _ensuredDefaultScopes = <String>{};

  bool get _updatingErpSync => _catalogState.updatingErpSync;
  Set<String> get _updatingStatusProductIds =>
      _catalogState.updatingStatusProductIds;
  String get _brandFilter => _catalogState.brandFilter;
  Produto? get _editingProduto => _catalogState.editingProduto;
  bool get _editorOpen => _catalogState.editorOpen;

  void _updateCatalogState(
    ProductCatalogPageViewState Function(ProductCatalogPageViewState state)
    update,
  ) {
    setState(() {
      _catalogState = update(_catalogState);
    });
  }

  void _updateCatalogStateIfMounted(
    ProductCatalogPageViewState Function(ProductCatalogPageViewState state)
    update,
  ) {
    setStateIfMounted(() {
      _catalogState = update(_catalogState);
    });
  }

  void _setCatalogEditorState(ProductCatalogEditorState state) {
    _updateCatalogState(
      (currentState) => currentState.withEditorState(
        editingProduto: state.editingProduto,
        editorOpen: state.editorOpen,
        brandFilter: state.brandFilter,
      ),
    );
  }

  void _setCatalogBrandFilter(String value) {
    _updateCatalogState((state) => state.withBrandFilter(value));
  }

  void _openImportSheet() {
    openProductImportSheet(
      context,
      identity: widget.identity,
      repository: widget.repository,
    );
  }

  void _setErpSyncUpdating(bool isLoading) {
    _updateCatalogStateIfMounted(
      (state) => state.withUpdatingErpSync(isLoading),
    );
  }

  void _addUpdatingStatusProductId(String productId) {
    _updateCatalogState(
      (state) => state.withAddedUpdatingStatusProductId(productId),
    );
  }

  void _removeUpdatingStatusProductId(String productId) {
    _updateCatalogStateIfMounted(
      (state) => state.withRemovedUpdatingStatusProductId(productId),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.identity.isMock) {
      _priceTableRepository = null;
      _basePriceRepository = null;
      return;
    }

    final firestore = FirebaseFirestore.instance;
    _priceTableRepository = FirestoreTabelaPrecoRepository(firestore);
    _basePriceRepository = FirestoreProductBasePriceRepository(firestore);
  }

  Future<ProductCatalogErpDisableSelection?>
  _requestDisableErpSyncSelection() async {
    final selected = await showDisableErpSyncDialog(context);
    if (selected == null) {
      return null;
    }

    if (selected == DisableErpSyncAction.deactivateErpProducts) {
      return ProductCatalogErpDisableSelection.deactivateErpProducts;
    }

    return ProductCatalogErpDisableSelection.keepCurrent;
  }

  Future<void> _setErpSyncEnabled(bool enabled) async {
    final feedbackMessages = await _catalogAsyncFlowCoordinator.updateErpSync(
      enabled: enabled,
      tenantId: widget.identity.tenantId,
      requestDisableSelection: _requestDisableErpSyncSelection,
      deactivateErpProducts: () {
        return _erpProductsDeactivationCoordinator.execute(
          repository: widget.repository,
          tenantId: widget.identity.tenantId,
        );
      },
      persistSyncEnabled: ({required tenantId, required enabled}) {
        return _workspaceService.setProductSyncFromErpEnabled(
          tenantId: tenantId,
          enabled: enabled,
        );
      },
      onLoadingChanged: _setErpSyncUpdating,
      resolveError: _resolveCatalogError,
    );

    runIfMounted(() {
      for (final message in feedbackMessages) {
        _showCatalogFeedback(message);
      }
    });
  }

  void _openProductEditor({Produto? produto}) {
    _setCatalogEditorState(
      _editorActionCoordinator.openEditor(
        produto: produto,
        currentBrandFilter: _brandFilter,
      ),
    );
  }

  void _openExistingProductEditor(Produto produto) {
    _openProductEditor(produto: produto);
  }

  void _closeProductEditor() {
    _setCatalogEditorState(
      _editorActionCoordinator.closeEditor(currentBrandFilter: _brandFilter),
    );
  }

  void _applyEditorActionOutcome(ProductCatalogEditorActionOutcome outcome) {
    runIfMounted(() {
      _setCatalogEditorState(outcome.editorState);
      _showCatalogFeedback(outcome.feedbackMessage);
    });
  }

  ValueChanged<Produto> _buildOnProductSavedHandler({required bool isNew}) =>
      (_) => _applyEditorActionOutcome(
        _editorActionCoordinator.onSaved(isNew: isNew),
      );

  void _handleProductDeleted() {
    _applyEditorActionOutcome(
      _editorActionCoordinator.onDeleted(currentBrandFilter: _brandFilter),
    );
  }

  String _formatCatalogPrice(Produto produto) {
    return ProductListPriceFormatter.format(
      produto,
      defaultCurrencyCode: _defaultCurrencyCode,
      currencyLabels: _currencyLabels,
    );
  }

  Future<void> _toggleProductStatus(Produto produto) async {
    final feedbackMessage = await _catalogAsyncFlowCoordinator
        .toggleProductStatus(
          produto: produto,
          updatingStatusProductIds: _updatingStatusProductIds,
          repository: widget.repository,
          onToggleStarted: _addUpdatingStatusProductId,
          onToggleFinished: _removeUpdatingStatusProductId,
          resolveError: _resolveCatalogError,
        );
    runIfMounted(() {
      _showCatalogFeedbackIfAny(feedbackMessage);
    });
  }

  Future<void> _ensureDefaultPriceTable() async {
    final repository = _priceTableRepository;
    if (repository == null) {
      return;
    }
    await DefaultPriceTableGuard.ensureDefaultPriceTable(
      identity: widget.identity,
      repository: repository,
      selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
      ensuredScopes: _ensuredDefaultScopes,
    );
  }

  void _showCatalogFeedback(String message) {
    ProductCatalogFeedback.showMessage(context, message);
  }

  void _showCatalogFeedbackIfAny(String? message) {
    if (message == null) {
      return;
    }
    _showCatalogFeedback(message);
  }

  Object _resolveCatalogError(Object? error) {
    return error ?? _unknownErrorMessage;
  }

  @override
  Widget build(BuildContext context) {
    return ProductCatalogWorkspaceSection(
      identity: widget.identity,
      repository: widget.repository,
      workspaceService: _workspaceService,
      selectedBrandFilter: _brandFilter,
      editorOpen: _editorOpen,
      editingProduct: _editingProduto,
      priceTableRepository: _priceTableRepository,
      basePriceRepository: _basePriceRepository,
      ensureDefaultPriceTable: _ensureDefaultPriceTable,
      representedCompanyName: widget.activeRepresentedCompanyName,
      representedCompanyId: widget.selectedRepresentedCompanyId,
      updatingStatusProductIds: _updatingStatusProductIds,
      onImportExcel: _openImportSheet,
      onCreateProduct: _openProductEditor,
      onBrandFilterChanged: _setCatalogBrandFilter,
      onErpSyncChanged: _setErpSyncEnabled,
      onToggleStatus: _toggleProductStatus,
      onOpenProduct: _openExistingProductEditor,
      priceFormatter: _formatCatalogPrice,
      onCloseEditor: _closeProductEditor,
      onSavedHandlerBuilder: _buildOnProductSavedHandler,
      onDeleted: _handleProductDeleted,
      erpSyncChangeEnabled: !_updatingErpSync,
      isMounted: () => mounted,
    );
  }
}
