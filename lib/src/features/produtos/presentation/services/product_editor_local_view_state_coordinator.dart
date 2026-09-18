import '../../../../core/models/domain_types.dart';
import 'product_editor_default_table_price_loader.dart';
import 'product_editor_form_reset_coordinator.dart';
import 'product_editor_view_state.dart';
import 'product_media_editor_coordinator.dart';

class ProductEditorMediaStateApplyResult {
  const ProductEditorMediaStateApplyResult({
    required this.state,
    required this.fotoUrlText,
  });

  final ProductEditorViewState state;
  final String fotoUrlText;
}

class ProductEditorTablePriceStateApplyResult {
  const ProductEditorTablePriceStateApplyResult({
    required this.state,
    required this.tablePriceText,
  });

  final ProductEditorViewState state;
  final String tablePriceText;
}

class ProductEditorLocalViewStateCoordinator {
  const ProductEditorLocalViewStateCoordinator();

  ProductEditorViewState applyStatus(
    ProductEditorViewState state,
    ProductStatus value,
  ) {
    return state.withStatus(value);
  }

  ProductEditorViewState applyCurrencyCode(
    ProductEditorViewState state,
    String value,
  ) {
    return state.withCurrencyCode(value);
  }

  ProductEditorViewState applyBitolaUnit(
    ProductEditorViewState state,
    String value,
  ) {
    return state.withBitolaUnit(value);
  }

  ProductEditorViewState applySaving(ProductEditorViewState state, bool value) {
    return state.withSaving(value);
  }

  ProductEditorViewState applyLoadingTablePrice(
    ProductEditorViewState state,
    bool value,
  ) {
    return state.withLoadingTablePrice(value);
  }

  ProductEditorViewState applyUploadingImage(
    ProductEditorViewState state,
    bool value,
  ) {
    return state.withUploadingImage(value);
  }

  ProductEditorViewState applyPostSaveReset({
    required ProductEditorViewState state,
    required ProductEditorFormResetValues resetValues,
  }) {
    return state.withPostSaveReset(
      status: resetValues.status,
      bitolaUnit: resetValues.bitolaUnit,
      currencyCode: resetValues.currencyCode,
    );
  }

  ProductEditorMediaStateApplyResult applyMediaState({
    required ProductEditorViewState state,
    required ProductMediaEditorState mediaState,
  }) {
    return ProductEditorMediaStateApplyResult(
      state: state.withMediaState(
        imageExplicitlyCleared: mediaState.imageExplicitlyCleared,
        currentImagePreviewBytes: mediaState.currentImagePreviewBytes,
        currentImageStoragePath: mediaState.currentImageStoragePath,
        currentImageThumbBase64: mediaState.currentImageThumbBase64,
      ),
      fotoUrlText: mediaState.fotoUrl,
    );
  }

  ProductEditorTablePriceStateApplyResult applyLoadedTablePrice({
    required ProductEditorViewState state,
    required ProductEditorDefaultTablePriceState loadedState,
  }) {
    return ProductEditorTablePriceStateApplyResult(
      state: state.withCurrencyCode(loadedState.currencyCode),
      tablePriceText: loadedState.formattedValue,
    );
  }
}
