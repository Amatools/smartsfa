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
import '../services/product_catalog_defaults.dart';
import '../services/product_catalog_editor_action_coordinator.dart';
import '../services/product_catalog_editor_state_coordinator.dart';
import '../services/product_catalog_feedback.dart';
import '../services/product_catalog_page_state_coordinator.dart';
import '../services/product_catalog_page_view_state.dart';
import '../services/product_catalog_source_filter.dart';
import '../services/product_catalog_workspace_payload.dart';
import '../services/product_list_price_formatter.dart';
import '../widgets/product_catalog_workspace_section.dart';
import '../widgets/product_import_sheet.dart';

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({
    super.key,
    required this.identity,
    required this.repository,
    this.activeRepresentedCompanyName,
    this.selectedRepresentedCompanyId,
    this.onInlineBackActiveChanged,
  });

  final AppIdentity identity;
  final ProdutoRepository repository;
  final String? activeRepresentedCompanyName;
  final String? selectedRepresentedCompanyId;
  final ValueChanged<bool>? onInlineBackActiveChanged;

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
  final ProductCatalogPageStateCoordinator _pageStateCoordinator =
      const ProductCatalogPageStateCoordinator();
  late final TabelaPrecoRepository? _priceTableRepository;
  late final ProductBasePriceRepository? _basePriceRepository;

  ProductCatalogPageViewState _catalogState =
      ProductCatalogPageViewState.initial();
  final Set<String> _ensuredDefaultScopes = <String>{};

  Set<String> get _updatingStatusProductIds =>
      _catalogState.updatingStatusProductIds;
  String get _brandFilter => _catalogState.brandFilter;
  ProductCatalogSourceFilter get _sourceFilter => _catalogState.sourceFilter;
  Produto? get _editingProduto => _catalogState.editingProduto;
  bool get _editorOpen => _catalogState.editorOpen;

  void _notifyInlineBackActiveChanged() {
    final callback = widget.onInlineBackActiveChanged;
    if (callback == null) {
      return;
    }
    final isActive = _editorOpen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      callback(isActive);
    });
  }

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
      (currentState) => _pageStateCoordinator.applyEditorState(
        currentState: currentState,
        editorState: state,
      ),
    );
  }

  void _setCatalogBrandFilter(String value) {
    _updateCatalogState(
      (state) => _pageStateCoordinator.applyBrandFilter(
        currentState: state,
        brandFilter: value,
      ),
    );
  }

  void _setCatalogSourceFilter(ProductCatalogSourceFilter value) {
    _updateCatalogState(
      (state) => _pageStateCoordinator.applySourceFilter(
        currentState: state,
        sourceFilter: value,
      ),
    );
  }

  void _openImportSheet() {
    openProductImportSheet(
      context,
      identity: widget.identity,
      repository: widget.repository,
      representedCompanyId: widget.selectedRepresentedCompanyId,
    );
  }

  void _downloadImportModel() {
    downloadProductImportTemplate(
      context,
      identity: widget.identity,
      repository: widget.repository,
      representedCompanyId: widget.selectedRepresentedCompanyId,
    );
  }

  void _addUpdatingStatusProductId(String productId) {
    _updateCatalogState(
      (state) => _pageStateCoordinator.addUpdatingStatusProductId(
        currentState: state,
        productId: productId,
      ),
    );
  }

  void _removeUpdatingStatusProductId(String productId) {
    _updateCatalogStateIfMounted(
      (state) => _pageStateCoordinator.removeUpdatingStatusProductId(
        currentState: state,
        productId: productId,
      ),
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
    _notifyInlineBackActiveChanged();
  }

  @override
  void didUpdateWidget(covariant ProdutosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onInlineBackActiveChanged !=
        widget.onInlineBackActiveChanged) {
      _notifyInlineBackActiveChanged();
    }
  }

  @override
  void dispose() {
    widget.onInlineBackActiveChanged?.call(false);
    super.dispose();
  }

  void _openProductEditor({Produto? produto}) {
    _setCatalogEditorState(
      _editorActionCoordinator.openEditor(
        produto: produto,
        currentBrandFilter: _brandFilter,
      ),
    );
    _notifyInlineBackActiveChanged();
  }

  void _openExistingProductEditor(Produto produto) {
    _openProductEditor(produto: produto);
  }

  void _closeProductEditor() {
    _setCatalogEditorState(
      _editorActionCoordinator.closeEditor(currentBrandFilter: _brandFilter),
    );
    _notifyInlineBackActiveChanged();
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
      defaultCurrencyCode: ProductCatalogDefaults.defaultCurrencyCode,
      currencyLabels: ProductCatalogDefaults.currencyLabels,
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
    return error ?? ProductCatalogDefaults.unknownErrorMessage;
  }

  ProductCatalogWorkspacePayload _buildWorkspacePayload() {
    return ProductCatalogWorkspacePayload(
      identity: widget.identity,
      repository: widget.repository,
      workspaceService: _workspaceService,
      selectedBrandFilter: _brandFilter,
      selectedSourceFilter: _sourceFilter,
      editorOpen: _editorOpen,
      editingProduct: _editingProduto,
      priceTableRepository: _priceTableRepository,
      basePriceRepository: _basePriceRepository,
      ensureDefaultPriceTable: _ensureDefaultPriceTable,
      representedCompanyName: widget.activeRepresentedCompanyName,
      representedCompanyId: widget.selectedRepresentedCompanyId,
      updatingStatusProductIds: _updatingStatusProductIds,
      onImportExcel: _openImportSheet,
      onDownloadExcelModel: _downloadImportModel,
      onCreateProduct: _openProductEditor,
      onBrandFilterChanged: _setCatalogBrandFilter,
      onSourceFilterChanged: _setCatalogSourceFilter,
      onToggleStatus: _toggleProductStatus,
      onOpenProduct: _openExistingProductEditor,
      priceFormatter: _formatCatalogPrice,
      onCloseEditor: _closeProductEditor,
      onSavedHandlerBuilder: _buildOnProductSavedHandler,
      onDeleted: _handleProductDeleted,
      isMounted: () => mounted,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_editorOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        if (_editorOpen) {
          _closeProductEditor();
        }
      },
      child: ProductCatalogWorkspaceSection(payload: _buildWorkspacePayload()),
    );
  }
}
