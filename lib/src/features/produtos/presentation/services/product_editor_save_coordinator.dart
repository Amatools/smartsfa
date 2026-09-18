import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';
import 'product_editor_entity_mapper.dart';
import 'product_editor_feedback.dart';

enum ProductEditorSaveExecutionResultType {
  savedAndClose,
  savedAndCreateAnother,
  failed,
}

class ProductEditorSaveExecutionResult {
  const ProductEditorSaveExecutionResult({
    required this.type,
    this.entity,
    this.failureMessage,
    this.syncError,
  });

  final ProductEditorSaveExecutionResultType type;
  final Produto? entity;
  final String? failureMessage;
  final Object? syncError;
}

class ProductEditorSaveFormData {
  const ProductEditorSaveFormData({
    required this.imageExplicitlyCleared,
    required this.fotoUrlText,
    required this.descricaoLongaText,
    required this.codigoText,
    required this.descricaoText,
    required this.codigoFabricanteText,
    required this.eanText,
    required this.marcaText,
    required this.availableBrands,
    required this.categoriaText,
    required this.subcategoriaText,
    required this.bitolaText,
    required this.bitolaUnit,
    required this.comprimentoMmText,
    required this.larguraMmText,
    required this.alturaMmText,
    required this.precoMinimoText,
    required this.unidadeText,
    required this.multiploVendaText,
    required this.quantidadeMinimaText,
    required this.ncmText,
    required this.cfopText,
    required this.icmsText,
    required this.pisText,
    required this.cofinsText,
    required this.pesoText,
    required this.erpProductIdText,
    required this.erpSyncIdText,
    required this.tabelaVersaoText,
    required this.estoqueVersaoText,
    required this.currentImageStoragePath,
    required this.currentImageThumbBase64,
  });

  final bool imageExplicitlyCleared;
  final String fotoUrlText;
  final String descricaoLongaText;
  final String codigoText;
  final String descricaoText;
  final String codigoFabricanteText;
  final String eanText;
  final String marcaText;
  final List<String> availableBrands;
  final String categoriaText;
  final String subcategoriaText;
  final String bitolaText;
  final String bitolaUnit;
  final String comprimentoMmText;
  final String larguraMmText;
  final String alturaMmText;
  final String precoMinimoText;
  final String unidadeText;
  final String multiploVendaText;
  final String quantidadeMinimaText;
  final String ncmText;
  final String cfopText;
  final String icmsText;
  final String pisText;
  final String cofinsText;
  final String pesoText;
  final String erpProductIdText;
  final String erpSyncIdText;
  final String tabelaVersaoText;
  final String estoqueVersaoText;
  final String? currentImageStoragePath;
  final String? currentImageThumbBase64;
}

class ProductEditorSaveCommand {
  const ProductEditorSaveCommand({
    required this.repository,
    required this.identity,
    required this.existing,
    required this.createAnother,
    required this.isEnterprise,
    required this.status,
    required this.currencyCode,
    required this.tablePrice,
    required this.formData,
    required this.syncDefaultTablePrice,
  });

  final ProdutoRepository repository;
  final AppIdentity identity;
  final Produto? existing;
  final bool createAnother;
  final bool isEnterprise;
  final ProductStatus status;
  final String currencyCode;
  final double tablePrice;
  final ProductEditorSaveFormData formData;
  final Future<void> Function(Produto entity) syncDefaultTablePrice;

  bool get shouldCreateAnotherAfterSave {
    return createAnother && existing == null;
  }

  ProductEditorSaveExecutionResultType get successResultType {
    if (shouldCreateAnotherAfterSave) {
      return ProductEditorSaveExecutionResultType.savedAndCreateAnother;
    }

    return ProductEditorSaveExecutionResultType.savedAndClose;
  }
}

class ProductEditorSaveCoordinator {
  const ProductEditorSaveCoordinator();

  Future<ProductEditorSaveExecutionResult> execute(
    ProductEditorSaveCommand command,
  ) async {
    try {
      final entity = _buildEntityFromCommand(command);

      await command.repository.save(entity);

      final syncError = await _trySyncDefaultTablePrice(command, entity);
      return _buildSaveSuccessResult(
        command: command,
        entity: entity,
        syncError: syncError,
      );
    } catch (error) {
      return _buildSaveFailureResult(error);
    }
  }

  Produto _buildEntityFromCommand(ProductEditorSaveCommand command) {
    final now = DateTime.now().toUtc();
    final formData = command.formData;

    return ProductEditorEntityMapper.buildFromForm(
      identity: command.identity,
      existing: command.existing,
      now: now,
      codigo: formData.codigoText,
      descricao: formData.descricaoText,
      status: command.status,
      currencyCode: command.currencyCode,
      tablePrice: command.tablePrice,
      isEnterprise: command.isEnterprise,
      imageExplicitlyCleared: formData.imageExplicitlyCleared,
      fotoUrlText: formData.fotoUrlText,
      descricaoLongaText: formData.descricaoLongaText,
      codigoFabricanteText: formData.codigoFabricanteText,
      eanText: formData.eanText,
      marcaText: formData.marcaText,
      availableBrands: formData.availableBrands,
      categoriaText: formData.categoriaText,
      subcategoriaText: formData.subcategoriaText,
      bitolaText: formData.bitolaText,
      bitolaUnit: formData.bitolaUnit,
      comprimentoMmText: formData.comprimentoMmText,
      larguraMmText: formData.larguraMmText,
      alturaMmText: formData.alturaMmText,
      precoMinimoText: formData.precoMinimoText,
      unidadeText: formData.unidadeText,
      multiploVendaText: formData.multiploVendaText,
      quantidadeMinimaText: formData.quantidadeMinimaText,
      ncmText: formData.ncmText,
      cfopText: formData.cfopText,
      icmsText: formData.icmsText,
      pisText: formData.pisText,
      cofinsText: formData.cofinsText,
      pesoText: formData.pesoText,
      erpProductIdText: formData.erpProductIdText,
      erpSyncIdText: formData.erpSyncIdText,
      tabelaVersaoText: formData.tabelaVersaoText,
      estoqueVersaoText: formData.estoqueVersaoText,
      currentImageStoragePath: formData.currentImageStoragePath,
      currentImageThumbBase64: formData.currentImageThumbBase64,
    );
  }

  Future<Object?> _trySyncDefaultTablePrice(
    ProductEditorSaveCommand command,
    Produto entity,
  ) async {
    try {
      await command.syncDefaultTablePrice(entity);
      return null;
    } catch (error) {
      return error;
    }
  }

  ProductEditorSaveExecutionResult _buildSaveSuccessResult({
    required ProductEditorSaveCommand command,
    required Produto entity,
    required Object? syncError,
  }) {
    return ProductEditorSaveExecutionResult(
      type: command.successResultType,
      entity: entity,
      syncError: syncError,
    );
  }

  ProductEditorSaveExecutionResult _buildSaveFailureResult(Object error) {
    return ProductEditorSaveExecutionResult(
      type: ProductEditorSaveExecutionResultType.failed,
      failureMessage: ProductEditorFeedback.saveFailureMessage(error),
    );
  }
}
