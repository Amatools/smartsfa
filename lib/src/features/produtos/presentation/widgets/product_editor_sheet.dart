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
import '../services/product_editor_action_flow_coordinator.dart';
import '../services/product_editor_bootstrap_coordinator.dart';
import '../services/product_editor_default_table_price_coordinator.dart';
import '../services/product_editor_defaults.dart';
import '../services/product_editor_delete_outcome_coordinator.dart';
import '../services/product_editor_feedback.dart';
import '../services/product_editor_form_reset_coordinator.dart';
import '../services/product_editor_initialization_coordinator.dart';
import '../services/product_editor_local_view_state_coordinator.dart';
import '../services/product_editor_media_flow_coordinator.dart';
import '../services/product_editor_media_upload_coordinator.dart';
import '../services/product_editor_save_outcome_coordinator.dart';
import '../services/product_editor_thumbnail_preview_builder.dart';
import '../services/product_editor_title_builder.dart';
import '../services/product_editor_view_state.dart';
import '../services/product_media_editor_coordinator.dart';
import '../services/product_media_upload_service.dart';
import 'product_category_dropdown_field.dart';
import 'product_editor_fields.dart';
import 'product_editor_sheet_layout.dart';

const List<String> _productBitolaUnits = <String>[
  ProductEditorDefaults.defaultBitolaUnit,
  'cm',
  'm',
];
const String _defaultCurrencyCode = 'BRL';

const Map<String, String> _currencyLabels = <String, String>{
  'BRL': 'R\$',
  'USD': 'US\$',
  'EUR': 'EUR',
};

const Map<String, String> _currencyHints = <String, String>{
  'BRL': '0,00',
  'USD': '0.00',
  'EUR': '0,00',
};

const String _unknownErrorMessage = 'erro desconhecido';

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
  final ProductEditorActionFlowCoordinator _actionFlowCoordinator =
      const ProductEditorActionFlowCoordinator();
  final ProductEditorThumbnailPreviewBuilder _thumbnailPreviewBuilder =
      const ProductEditorThumbnailPreviewBuilder();
  final ProductEditorBootstrapCoordinator _bootstrapCoordinator =
      const ProductEditorBootstrapCoordinator();
  final ProductEditorLocalViewStateCoordinator _localViewStateCoordinator =
      const ProductEditorLocalViewStateCoordinator();
  final ProductEditorMediaFlowCoordinator _mediaFlowCoordinator =
      const ProductEditorMediaFlowCoordinator();
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
    final bootstrap = _bootstrapCoordinator.build(
      identity: widget.identity,
      existingProduct: widget.produto,
      representedCompanyId: widget.representedCompanyId,
      basePriceRepository: widget.basePriceRepository,
      tableRepository: widget.priceTableRepository,
      existingProducts: widget.existingProducts,
      defaultCurrencyCode: _defaultCurrencyCode,
      currencyLabels: _currencyLabels,
      bitolaUnits: _productBitolaUnits,
    );
    final initialState = bootstrap.initializationState;
    _emptyDraft = bootstrap.emptyDraft;
    _formControllers = initialState.controllers;
    _editorState = ProductEditorViewState.initial(
      status: initialState.status,
      bitolaUnit: initialState.bitolaUnit,
      currencyCode: initialState.currencyCode,
      currentImageStoragePath: initialState.currentImageStoragePath,
      currentImageThumbBase64: initialState.currentImageThumbBase64,
    );
    _defaultPriceSyncService = bootstrap.defaultPriceSyncService;
    _defaultTablePriceCoordinator = bootstrap.defaultTablePriceCoordinator;
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
      (state) => _localViewStateCoordinator.applyStatus(state, value),
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
      _formControllers.categoria.text = value;
    });
  }

  void _setEditorCurrencyCode(String value) {
    _updateEditorState(
      (state) => _localViewStateCoordinator.applyCurrencyCode(state, value),
    );
  }

  void _setEditorBrand(String brand) {
    setStateIfMounted(() {
      _formControllers.marca.text = brand;
    });
  }

  void _setEditorBitolaUnit(String value) {
    _updateEditorState(
      (state) => _localViewStateCoordinator.applyBitolaUnit(state, value),
    );
  }

  void _clearImageSelectionInState() {
    setStateIfMounted(_clearImageSelection);
  }

  void _setSaving(bool value) {
    _updateEditorState(
      (state) => _localViewStateCoordinator.applySaving(state, value),
    );
  }

  void _setTablePriceLoading(bool value) {
    _updateEditorState(
      (state) =>
          _localViewStateCoordinator.applyLoadingTablePrice(state, value),
    );
  }

  void _setUploadingImage(bool value) {
    _updateEditorState(
      (state) => _localViewStateCoordinator.applyUploadingImage(state, value),
    );
  }

  Widget _buildQuickStartCategoryField(bool readOnly) {
    return ProductCategoryDropdownField(
      workspaceStream: _workspaceService.watchWorkspace(
        widget.identity.tenantId,
      ),
      representedCompanyId: widget.representedCompanyId,
      categoriaController: _formControllers.categoria,
      readOnly: readOnly,
      labelStyle: _fieldLabelStyle,
      inputTextStyle: _compactInputTextStyle,
      fieldHeight: _compactFieldHeight,
      onCategoryChanged: _setEditorCategory,
    );
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = !widget.allowManualActions;

    return ProductEditorSheetLayout(
      readOnly: readOnly,
      title: _buildEditorTitle(),
      status: _status,
      saving: _saving,
      labelStyle: _fieldLabelStyle,
      onClose: widget.onClose,
      onStatusChanged: _setEditorStatus,
      thumbnailProduto: _buildQuickStartThumbnailProduto(),
      imageTileSize: _imageTileSize,
      uploadingImage: _uploadingImage,
      currentImageStoragePath: _currentImageStoragePath,
      currentImagePreviewBytes: _currentImagePreviewBytes,
      onOpenMediaLibrary: readOnly ? null : _openProductMediaLibrary,
      controllers: _formControllers,
      categoryField: _buildQuickStartCategoryField(readOnly),
      editorFieldBuilder: _editorField,
      currencyCode: _currencyCode,
      bitolaUnit: _bitolaUnit,
      loadingTablePrice: _loadingTablePrice,
      isEnterprise: widget.isEnterprise,
      availableBrands: widget.availableBrands,
      bitolaUnits: _productBitolaUnits,
      currencyLabels: _currencyLabels,
      currencyHints: _currencyHints,
      inputTextStyle: _compactInputTextStyle,
      fieldHeight: _compactFieldHeight,
      priceFieldWidth: _priceFieldWidth,
      priceFieldGap: _priceFieldGap,
      representedCompanyName: widget.representedCompanyName,
      onCurrencyCodeChanged: _setEditorCurrencyCode,
      onBrandSelected: _setEditorBrand,
      onBitolaUnitChanged: _setEditorBitolaUnit,
      onClearImage: _clearImageSelectionInState,
      isEditing: widget.produto != null,
      onDelete: _delete,
      onSave: _save,
      onSaveAndCreateAnother: () => _save(createAnother: true),
    );
  }

  TextStyle get _compactInputTextStyle {
    return Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: AppFieldTokens.mediumFieldFontSize,
          height: 1.0,
        ) ??
        const TextStyle(
          fontSize: AppFieldTokens.mediumFieldFontSize,
          height: 1.0,
        );
  }

  TextStyle get _fieldLabelStyle {
    return Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: AppFieldTokens.mediumFieldLabelFontSize,
          fontWeight: FontWeight.w500,
          height: 1.15,
        ) ??
        const TextStyle(
          fontSize: AppFieldTokens.mediumFieldLabelFontSize,
          fontWeight: FontWeight.w500,
          height: 1.15,
        );
  }

  Widget _editorField(
    TextEditingController controller,
    String label, {
    required bool readOnly,
    TextInputType? keyboardType,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.right,
  }) {
    return buildProductEditorField(
      context: context,
      controller: controller,
      label: label,
      readOnly: readOnly,
      inputTextStyle: _compactInputTextStyle,
      labelStyle: _fieldLabelStyle,
      fieldHeight: _compactFieldHeight,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textAlign: textAlign,
    );
  }

  String get _mediaScopeKey =>
      DefaultPriceTableGuard.normalizeDefaultPricingScopeKey(
        widget.representedCompanyId,
      );

  Future<void> _openProductMediaLibrary() async {
    await _mediaFlowCoordinator.openLibrary(
      context: context,
      mediaEditorCoordinator: _mediaEditorCoordinator,
      mediaUploadCoordinator: _mediaUploadCoordinator,
      uploadService: _mediaUploadService,
      tenantId: widget.identity.tenantId,
      representedCompanyId: widget.representedCompanyId,
      representedCompanyName: widget.representedCompanyName,
      selectedUrl: _formControllers.fotoUrl.text.trim(),
      scopeKey: _mediaScopeKey,
      isUploadingImage: () => _uploadingImage,
      onUploadingChanged: _setUploadingImage,
      onStateReady: (state) {
        setStateIfMounted(() {
          _applyMediaEditorState(state);
        });
      },
      onFeedback: (message) {
        runIfMounted(() {
          _showEditorFeedback(message);
        });
      },
    );
  }

  Future<void> _save({bool createAnother = false}) async {
    final uiAction = await _actionFlowCoordinator.executeSave(
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
      defaultCurrencyCode: _defaultCurrencyCode,
      requiredDescriptionMessage:
          ProductEditorFeedback.requiredDescriptionMessage,
      requiredTablePriceMessage:
          ProductEditorFeedback.requiredTablePriceMessage,
      unknownErrorMessage: _unknownErrorMessage,
      onSaveStarted: () {
        _setSaving(true);
      },
    );

    runIfMounted(() {
      _handleSaveUiAction(uiAction);
    });
  }

  void _handleSaveUiAction(ProductEditorSaveOutcomeUiAction uiAction) {
    for (final message in uiAction.feedbackMessages) {
      _showEditorFeedback(message);
    }

    final resetValues = uiAction.resetValues;
    if (resetValues != null) {
      _applyPostSaveResetValues(resetValues);
    }

    final savedEntity = uiAction.savedEntity;
    if (savedEntity != null) {
      widget.onSaved(savedEntity);
      return;
    }

    if (uiAction.shouldStopSaving) {
      _stopSaving();
    }
  }

  void _stopSaving() {
    _setSaving(false);
  }

  void _showEditorFeedbackIfAny(String? message) {
    if (message == null) {
      return;
    }
    _showEditorFeedback(message);
  }

  void _applyPostSaveResetValues(ProductEditorFormResetValues resetValues) {
    _applyMediaEditorState(_mediaEditorCoordinator.emptySelectionState());
    _editorState = _localViewStateCoordinator.applyPostSaveReset(
      state: _editorState,
      resetValues: resetValues,
    );
  }

  Future<void> _delete() async {
    final existing = widget.produto;
    if (existing == null) {
      return;
    }

    final uiAction = await _actionFlowCoordinator.confirmAndExecuteDelete(
      context: context,
      existing: existing,
      tenantId: widget.identity.tenantId,
      repository: widget.repository,
      defaultPriceSyncService: _defaultPriceSyncService,
      unknownErrorMessage: _unknownErrorMessage,
      onExecutionStarted: () {
        _setSaving(true);
      },
    );

    runIfMounted(() {
      _handleDeleteUiAction(uiAction);
    });
  }

  void _handleDeleteUiAction(ProductEditorDeleteOutcomeUiAction uiAction) {
    _showEditorFeedbackIfAny(uiAction.feedbackMessage);

    switch (uiAction.followUpAction) {
      case ProductEditorDeleteFollowUpAction.none:
        break;
      case ProductEditorDeleteFollowUpAction.closeEditor:
        widget.onClose();
        return;
      case ProductEditorDeleteFollowUpAction.notifyDeleted:
        widget.onDeleted();
        return;
    }

    if (uiAction.shouldStopSaving) {
      _stopSaving();
    }
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
    final loadedState = await _defaultTablePriceCoordinator.loadForEditor(
      existingProduct: widget.produto,
      currentCurrencyCode: _currencyCode,
      currencyLabels: _currencyLabels,
      onLoadingChanged: _setTablePriceLoading,
    );

    if (loadedState == null) {
      return;
    }

    setStateIfMounted(() {
      final applyResult = _localViewStateCoordinator.applyLoadedTablePrice(
        state: _editorState,
        loadedState: loadedState,
      );
      _editorState = applyResult.state;
      _formControllers.precoTabela.text = applyResult.tablePriceText;
    });
  }

  Future<void> _syncDefaultTablePrice(Produto entity) async {
    await _defaultTablePriceCoordinator.syncForProduct(
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
    final applyResult = _localViewStateCoordinator.applyMediaState(
      state: _editorState,
      mediaState: state,
    );
    _editorState = applyResult.state;
    _formControllers.fotoUrl.text = applyResult.fotoUrlText;
  }
}
