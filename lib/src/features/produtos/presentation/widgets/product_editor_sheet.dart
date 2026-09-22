import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/product_base_price_repository.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';
import '../../../../shared/presentation/state/mounted_state_mixin.dart';
import '../../../../shared/presentation/theme/app_field_tokens.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../../../precos/presentation/services/default_price_table_guard.dart';
import '../services/product_default_price_sync_service.dart';
import '../services/product_editor_async_actions_coordinator.dart';
import '../services/product_editor_controller_binding_coordinator.dart';
import '../services/product_editor_default_table_price_coordinator.dart';
import '../services/product_editor_defaults.dart';
import '../services/product_editor_feedback.dart';
import '../services/product_editor_form_reset_coordinator.dart';
import '../services/product_editor_initialization_coordinator.dart';
import '../services/product_editor_media_upload_coordinator.dart';
import '../services/product_editor_outcome_dispatcher.dart';
import '../services/product_editor_sheet_bootstrap_coordinator.dart';
import '../services/product_editor_thumbnail_preview_builder.dart';
import '../services/product_editor_title_builder.dart';
import '../services/product_editor_view_state.dart';
import '../services/product_media_editor_coordinator.dart';
import '../services/product_media_upload_service.dart';
import 'product_category_dropdown_field.dart';
import 'product_editor_field_builder.dart';
import 'product_editor_field_style_factory.dart';
import 'product_editor_sheet_layout.dart';
import 'product_editor_sheet_layout_payload.dart';
import 'product_editor_tabs_payload.dart';

class ProductEditorSheet extends StatefulWidget {
  const ProductEditorSheet({
    super.key,
    required this.identity,
    required this.repository,
    required this.priceTableRepository,
    required this.basePriceRepository,
    required this.ensureDefaultTable,
    required this.isEnterprise,
    required this.existingProducts,
    required this.availableBrands,
    required this.allowManualActions,
    required this.onClose,
    required this.onSaved,
    required this.onDeleted,
    this.representedCompanyName,
    this.representedCompanyId,
    this.produto,
  });

  final AppIdentity identity;
  final ProdutoRepository repository;
  final TabelaPrecoRepository? priceTableRepository;
  final ProductBasePriceRepository? basePriceRepository;
  final Future<void> Function() ensureDefaultTable;
  final bool isEnterprise;
  final List<Produto> existingProducts;
  final List<String> availableBrands;
  final bool allowManualActions;
  final VoidCallback onClose;
  final ValueChanged<Produto> onSaved;
  final VoidCallback onDeleted;
  final String? representedCompanyName;
  final String? representedCompanyId;
  final Produto? produto;

  @override
  State<ProductEditorSheet> createState() => _ProductEditorSheetState();
}

class _ProductEditorSheetState extends State<ProductEditorSheet>
    with MountedStateMixin<ProductEditorSheet> {
  static const double _compactFieldHeight = AppFieldTokens.mediumFieldHeight;
  static const double _priceFieldWidth = 180;
  static const double _priceFieldGap = 18;
  static const double _imageTileSize = 54;
  final WorkspaceProfileService _workspaceService = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );
  late final ProductDefaultPriceSyncService _defaultPriceSyncService;
  late final ProductEditorDefaultTablePriceCoordinator
  _defaultTablePriceCoordinator;
  final ProductEditorAsyncActionsCoordinator _asyncActionsCoordinator =
      const ProductEditorAsyncActionsCoordinator();
  final ProductEditorThumbnailPreviewBuilder _thumbnailPreviewBuilder =
      const ProductEditorThumbnailPreviewBuilder();
  final ProductEditorSheetBootstrapCoordinator _sheetBootstrapCoordinator =
      const ProductEditorSheetBootstrapCoordinator();
  final ProductEditorControllerBindingCoordinator _bindingCoordinator =
      const ProductEditorControllerBindingCoordinator();
  final ProductEditorOutcomeDispatcher _outcomeDispatcher =
      const ProductEditorOutcomeDispatcher();
  final ProductEditorFieldStyleFactory _fieldStyleFactory =
      const ProductEditorFieldStyleFactory();
  final ProductEditorMediaUploadCoordinator _mediaUploadCoordinator =
      const ProductEditorMediaUploadCoordinator();
  final ProductMediaEditorCoordinator _mediaEditorCoordinator =
      const ProductMediaEditorCoordinator();
  final ProductMediaUploadService _mediaUploadService =
      const ProductMediaUploadService();

  late final Produto _emptyDraft;
  late final ProductEditorFormControllers _formControllers;
  late ProductEditorViewState _editorState;

  ProductStatus get _status => _editorState.status;
  String get _bitolaUnit => _editorState.bitolaUnit;
  String get _currencyCode => _editorState.currencyCode;
  bool get _saving => _editorState.saving;
  bool get _loadingTablePrice => _editorState.loadingTablePrice;
  bool get _uploadingImage => _editorState.uploadingImage;
  bool get _imageExplicitlyCleared => _editorState.imageExplicitlyCleared;
  Uint8List? get _currentImagePreviewBytes =>
      _editorState.currentImagePreviewBytes;
  String? get _currentImageStoragePath => _editorState.currentImageStoragePath;
  String? get _currentImageThumbBase64 => _editorState.currentImageThumbBase64;

  @override
  void initState() {
    super.initState();
    final bootstrapState = _sheetBootstrapCoordinator.build(
      identity: widget.identity,
      existingProduct: widget.produto,
      representedCompanyId: widget.representedCompanyId,
      basePriceRepository: widget.basePriceRepository,
      tableRepository: widget.priceTableRepository,
      existingProducts: widget.existingProducts,
      defaultCurrencyCode: ProductEditorDefaults.defaultCurrencyCode,
      currencyLabels: ProductEditorDefaults.currencyLabels,
      bitolaUnits: ProductEditorDefaults.bitolaUnits,
    );
    _emptyDraft = bootstrapState.emptyDraft;
    _formControllers = bootstrapState.formControllers;
    _editorState = bootstrapState.editorState;
    _defaultPriceSyncService = bootstrapState.defaultPriceSyncService;
    _defaultTablePriceCoordinator = bootstrapState.defaultTablePriceCoordinator;
    _loadDefaultTablePriceForEditor();
  }

  @override
  void dispose() {
    _formControllers.dispose();
    super.dispose();
  }

  Produto _buildQuickStartThumbnailProduto() {
    return _thumbnailPreviewBuilder.build(
      existingProduct: widget.produto,
      fallbackDraft: _emptyDraft,
      descricao: _formControllers.descricao.text,
      fotoUrl: _formControllers.fotoUrl.text,
    );
  }

  void _setEditorStatus(ProductStatus value) {
    _updateEditorState(
      (state) => _bindingCoordinator.applyStatus(state, value),
    );
  }

  void _updateEditorState(
    ProductEditorViewState Function(ProductEditorViewState state) update,
  ) {
    setStateIfMounted(() {
      _editorState = update(_editorState);
    });
  }

  void _setEditorCategory(String value) {
    setStateIfMounted(() {
      _bindingCoordinator.setCategory(_formControllers, value);
    });
  }

  void _setEditorCurrencyCode(String value) {
    _updateEditorState(
      (state) => _bindingCoordinator.applyCurrencyCode(state, value),
    );
  }

  void _setEditorBrand(String brand) {
    setStateIfMounted(() {
      _bindingCoordinator.setBrand(_formControllers, brand);
    });
  }

  void _setEditorBitolaUnit(String value) {
    _updateEditorState(
      (state) => _bindingCoordinator.applyBitolaUnit(state, value),
    );
  }

  void _clearImageSelectionInState() {
    setStateIfMounted(_clearImageSelection);
  }

  void _setSaving(bool value) {
    _updateEditorState(
      (state) => _bindingCoordinator.applySaving(state, value),
    );
  }

  void _setTablePriceLoading(bool value) {
    _updateEditorState(
      (state) => _bindingCoordinator.applyLoadingTablePrice(state, value),
    );
  }

  void _setUploadingImage(bool value) {
    _updateEditorState(
      (state) => _bindingCoordinator.applyUploadingImage(state, value),
    );
  }

  Widget _buildQuickStartCategoryField({
    required bool readOnly,
    required TextStyle labelStyle,
    required TextStyle inputTextStyle,
  }) {
    return ProductCategoryDropdownField(
      workspaceStream: _workspaceService.watchWorkspace(
        widget.identity.tenantId,
      ),
      representedCompanyId: widget.representedCompanyId,
      categoriaController: _formControllers.categoria,
      readOnly: readOnly,
      labelStyle: labelStyle,
      inputTextStyle: inputTextStyle,
      fieldHeight: _compactFieldHeight,
      onCategoryChanged: _setEditorCategory,
    );
  }

  ProductEditorTabsPayload _buildTabsPayload({
    required bool readOnly,
    required TextStyle labelStyle,
    required TextStyle inputTextStyle,
    required ProductEditorFieldBuilder editorFieldBuilder,
  }) {
    return ProductEditorTabsPayload(
      readOnly: readOnly,
      controllers: _formControllers,
      status: _status,
      currencyCode: _currencyCode,
      bitolaUnit: _bitolaUnit,
      loadingTablePrice: _loadingTablePrice,
      isEnterprise: widget.isEnterprise,
      availableBrands: widget.availableBrands,
      bitolaUnits: ProductEditorDefaults.bitolaUnits,
      currencyLabels: ProductEditorDefaults.currencyLabels,
      currencyHints: ProductEditorDefaults.currencyHints,
      labelStyle: labelStyle,
      inputTextStyle: inputTextStyle,
      fieldHeight: _compactFieldHeight,
      priceFieldWidth: _priceFieldWidth,
      priceFieldGap: _priceFieldGap,
      representedCompanyName: widget.representedCompanyName,
      onStatusChanged: _setEditorStatus,
      onCurrencyCodeChanged: _setEditorCurrencyCode,
      onBrandSelected: _setEditorBrand,
      onBitolaUnitChanged: _setEditorBitolaUnit,
      onOpenMediaLibrary: _openProductMediaLibrary,
      onClearImage: _clearImageSelectionInState,
      editorFieldBuilder: editorFieldBuilder,
    );
  }

  ProductEditorSheetLayoutPayload _buildLayoutPayload({
    required bool readOnly,
    required TextStyle labelStyle,
    required Widget categoryField,
    required ProductEditorFieldBuilder editorFieldBuilder,
    required ProductEditorTabsPayload tabsPayload,
  }) {
    return ProductEditorSheetLayoutPayload(
      readOnly: readOnly,
      title: _buildEditorTitle(),
      status: _status,
      saving: _saving,
      labelStyle: labelStyle,
      onClose: widget.onClose,
      onStatusChanged: _setEditorStatus,
      thumbnailProduto: _buildQuickStartThumbnailProduto(),
      imageTileSize: _imageTileSize,
      uploadingImage: _uploadingImage,
      currentImageStoragePath: _currentImageStoragePath,
      currentImagePreviewBytes: _currentImagePreviewBytes,
      onOpenMediaLibrary: readOnly ? null : _openProductMediaLibrary,
      controllers: _formControllers,
      categoryField: categoryField,
      editorFieldBuilder: editorFieldBuilder,
      tabsPayload: tabsPayload,
      isEditing: widget.produto != null,
      onDelete: _delete,
      onSave: _save,
      onSaveAndCreateAnother: () => _save(createAnother: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = !widget.allowManualActions;
    final inputTextStyle = _fieldStyleFactory.inputTextStyle(context);
    final labelStyle = _fieldStyleFactory.labelStyle(context);

    Widget editorFieldBuilder(
      TextEditingController controller,
      String label, {
      required bool readOnly,
      TextInputType? keyboardType,
      int maxLines = 1,
      TextAlign textAlign = TextAlign.right,
    }) {
      return _fieldStyleFactory.buildEditorField(
        context: context,
        controller: controller,
        label: label,
        readOnly: readOnly,
        inputTextStyle: inputTextStyle,
        labelStyle: labelStyle,
        fieldHeight: _compactFieldHeight,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textAlign: textAlign,
      );
    }

    final tabsPayload = _buildTabsPayload(
      readOnly: readOnly,
      labelStyle: labelStyle,
      inputTextStyle: inputTextStyle,
      editorFieldBuilder: editorFieldBuilder,
    );
    final categoryField = _buildQuickStartCategoryField(
      readOnly: readOnly,
      labelStyle: labelStyle,
      inputTextStyle: inputTextStyle,
    );
    final layoutPayload = _buildLayoutPayload(
      readOnly: readOnly,
      labelStyle: labelStyle,
      categoryField: categoryField,
      editorFieldBuilder: editorFieldBuilder,
      tabsPayload: tabsPayload,
    );

    return ProductEditorSheetLayout(payload: layoutPayload);
  }

  String get _mediaScopeKey =>
      DefaultPriceTableGuard.normalizeDefaultPricingScopeKey(
        widget.representedCompanyId,
      );

  Future<void> _openProductMediaLibrary() async {
    final uiAction = await _asyncActionsCoordinator.openMediaLibrary(
      context: context,
      state: _editorState,
      selectedUrl: _formControllers.fotoUrl.text.trim(),
      tenantId: widget.identity.tenantId,
      representedCompanyId: widget.representedCompanyId,
      representedCompanyName: widget.representedCompanyName,
      scopeKey: _mediaScopeKey,
      mediaEditorCoordinator: _mediaEditorCoordinator,
      mediaUploadCoordinator: _mediaUploadCoordinator,
      uploadService: _mediaUploadService,
      isUploadingImage: () => _uploadingImage,
      onUploadingChanged: _setUploadingImage,
    );

    runIfMounted(() {
      for (final message in uiAction.feedbackMessages) {
        _showEditorFeedback(message);
      }

      if (!uiAction.hasStateChange) {
        return;
      }

      setStateIfMounted(() {
        _editorState = _bindingCoordinator.applyMediaIntegrationAction(
          state: _editorState,
          uiAction: uiAction,
          controllers: _formControllers,
        );
      });
    });
  }

  Future<void> _save({bool createAnother = false}) async {
    final uiAction = await _asyncActionsCoordinator.save(
      repository: widget.repository,
      identity: widget.identity,
      existingProduct: widget.produto,
      createAnother: createAnother,
      isEnterprise: widget.isEnterprise,
      status: _status,
      currencyCode: _currencyCode,
      tablePriceText: _formControllers.precoTabela.text,
      controllers: _formControllers,
      imageExplicitlyCleared: _imageExplicitlyCleared,
      availableBrands: widget.availableBrands,
      bitolaUnit: _bitolaUnit,
      currentImageStoragePath: _currentImageStoragePath,
      currentImageThumbBase64: _currentImageThumbBase64,
      syncDefaultTablePrice: _syncDefaultTablePrice,
      existingProducts: widget.existingProducts,
      defaultCurrencyCode: ProductEditorDefaults.defaultCurrencyCode,
      requiredDescriptionMessage:
          ProductEditorFeedback.requiredDescriptionMessage,
      requiredTablePriceMessage:
          ProductEditorFeedback.requiredTablePriceMessage,
      unknownErrorMessage: ProductEditorDefaults.unknownErrorMessage,
      onSaveStarted: () {
        _setSaving(true);
      },
    );

    runIfMounted(() {
      _outcomeDispatcher.dispatchSave(
        action: uiAction,
        onFeedback: _showEditorFeedback,
        onApplyResetValues: _applyPostSaveResetValues,
        onSaved: widget.onSaved,
        onStopSaving: _stopSaving,
      );
    });
  }

  void _stopSaving() {
    _setSaving(false);
  }

  void _applyPostSaveResetValues(ProductEditorFormResetValues resetValues) {
    _applyMediaEditorState(_mediaEditorCoordinator.emptySelectionState());
    _editorState = _bindingCoordinator.applyPostSaveReset(
      state: _editorState,
      resetValues: resetValues,
    );
  }

  Future<void> _delete() async {
    final uiAction = await _asyncActionsCoordinator.delete(
      context: context,
      existingProduct: widget.produto,
      tenantId: widget.identity.tenantId,
      repository: widget.repository,
      defaultPriceSyncService: _defaultPriceSyncService,
      unknownErrorMessage: ProductEditorDefaults.unknownErrorMessage,
      onExecutionStarted: () {
        _setSaving(true);
      },
    );

    if (uiAction == null) {
      return;
    }

    runIfMounted(() {
      _outcomeDispatcher.dispatchDelete(
        action: uiAction,
        onFeedback: _showEditorFeedback,
        onCloseEditor: widget.onClose,
        onDeleted: widget.onDeleted,
        onStopSaving: _stopSaving,
      );
    });
  }

  void _showEditorFeedback(String message) {
    ProductEditorFeedback.showMessage(context, message);
  }

  String _buildEditorTitle() {
    return ProductEditorTitleBuilder.build(
      tenantName: widget.identity.tenantName,
      representedCompanyName: widget.representedCompanyName,
      isNew: widget.produto == null,
    );
  }

  Future<void> _loadDefaultTablePriceForEditor() async {
    final uiAction = await _asyncActionsCoordinator.loadDefaultTablePrice(
      defaultTablePriceCoordinator: _defaultTablePriceCoordinator,
      state: _editorState,
      existingProduct: widget.produto,
      currentCurrencyCode: _currencyCode,
      currencyLabels: ProductEditorDefaults.currencyLabels,
      onLoadingChanged: _setTablePriceLoading,
    );

    if (uiAction == null) {
      return;
    }

    setStateIfMounted(() {
      _editorState = _bindingCoordinator.applyDefaultTableLoadAction(
        state: _editorState,
        uiAction: uiAction,
        controllers: _formControllers,
      );
    });
  }

  Future<void> _syncDefaultTablePrice(Produto entity) async {
    await _asyncActionsCoordinator.syncDefaultTablePrice(
      defaultTablePriceCoordinator: _defaultTablePriceCoordinator,
      produto: entity,
      tablePriceText: _formControllers.precoTabela.text,
      currencyCode: _currencyCode,
      ensureDefaultTable: widget.ensureDefaultTable,
    );
  }

  void _clearImageSelection() {
    _applyMediaEditorState(_mediaEditorCoordinator.clearSelectionState());
  }

  void _applyMediaEditorState(ProductMediaEditorState state) {
    _editorState = _bindingCoordinator.applyMediaState(
      state: _editorState,
      mediaState: state,
      controllers: _formControllers,
    );
  }
}
