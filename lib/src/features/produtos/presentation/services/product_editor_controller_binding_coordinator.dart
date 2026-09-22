import '../../../../core/models/domain_types.dart';
import 'product_editor_form_reset_coordinator.dart';
import 'product_editor_initialization_coordinator.dart';
import 'product_editor_integration_flow_coordinator.dart';
import 'product_editor_local_view_state_coordinator.dart';
import 'product_editor_view_state.dart';
import 'product_media_editor_coordinator.dart';

class ProductEditorControllerBindingCoordinator {
  const ProductEditorControllerBindingCoordinator({
    this.localViewStateCoordinator =
        const ProductEditorLocalViewStateCoordinator(),
  });

  final ProductEditorLocalViewStateCoordinator localViewStateCoordinator;

  ProductEditorViewState applyStatus(
    ProductEditorViewState state,
    ProductStatus value,
  ) {
    return localViewStateCoordinator.applyStatus(state, value);
  }

  ProductEditorViewState applyCurrencyCode(
    ProductEditorViewState state,
    String value,
  ) {
    return localViewStateCoordinator.applyCurrencyCode(state, value);
  }

  ProductEditorViewState applyBitolaUnit(
    ProductEditorViewState state,
    String value,
  ) {
    return localViewStateCoordinator.applyBitolaUnit(state, value);
  }

  ProductEditorViewState applySaving(ProductEditorViewState state, bool value) {
    return localViewStateCoordinator.applySaving(state, value);
  }

  ProductEditorViewState applyLoadingTablePrice(
    ProductEditorViewState state,
    bool value,
  ) {
    return localViewStateCoordinator.applyLoadingTablePrice(state, value);
  }

  ProductEditorViewState applyUploadingImage(
    ProductEditorViewState state,
    bool value,
  ) {
    return localViewStateCoordinator.applyUploadingImage(state, value);
  }

  void setCategory(ProductEditorFormControllers controllers, String value) {
    controllers.categoria.text = value;
  }

  void setBrand(ProductEditorFormControllers controllers, String value) {
    controllers.marca.text = value;
  }

  ProductEditorViewState applyPostSaveReset({
    required ProductEditorViewState state,
    required ProductEditorFormResetValues resetValues,
  }) {
    return localViewStateCoordinator.applyPostSaveReset(
      state: state,
      resetValues: resetValues,
    );
  }

  ProductEditorViewState applyMediaState({
    required ProductEditorViewState state,
    required ProductMediaEditorState mediaState,
    required ProductEditorFormControllers controllers,
  }) {
    final applyResult = localViewStateCoordinator.applyMediaState(
      state: state,
      mediaState: mediaState,
    );
    controllers.fotoUrl.text = applyResult.fotoUrlText;
    return applyResult.state;
  }

  ProductEditorViewState applyMediaIntegrationAction({
    required ProductEditorViewState state,
    required ProductEditorMediaIntegrationUiAction uiAction,
    required ProductEditorFormControllers controllers,
  }) {
    controllers.fotoUrl.text = uiAction.fotoUrlText;
    return uiAction.state;
  }

  ProductEditorViewState applyDefaultTableLoadAction({
    required ProductEditorViewState state,
    required ProductEditorDefaultTableLoadUiAction uiAction,
    required ProductEditorFormControllers controllers,
  }) {
    controllers.precoTabela.text = uiAction.tablePriceText;
    return uiAction.state;
  }
}
