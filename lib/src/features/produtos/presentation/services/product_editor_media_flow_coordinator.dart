import 'package:flutter/material.dart';

import '../models/product_media_models.dart';
import 'product_editor_media_upload_coordinator.dart';
import 'product_media_editor_coordinator.dart';
import 'product_media_upload_service.dart';

class ProductEditorMediaFlowCoordinator {
  const ProductEditorMediaFlowCoordinator();

  Future<void> openLibrary({
    required BuildContext context,
    required ProductMediaEditorCoordinator mediaEditorCoordinator,
    required ProductEditorMediaUploadCoordinator mediaUploadCoordinator,
    required ProductMediaUploadService uploadService,
    required String tenantId,
    required String? representedCompanyId,
    required String? representedCompanyName,
    required String selectedUrl,
    required String scopeKey,
    required bool Function() isUploadingImage,
    required void Function(bool) onUploadingChanged,
    required void Function(ProductMediaEditorState state) onStateReady,
    required void Function(String message) onFeedback,
  }) async {
    Future<ProductMediaSelection?> onUploadNew() async {
      if (isUploadingImage()) {
        return null;
      }

      onUploadingChanged(true);
      try {
        final result = await mediaUploadCoordinator.pickAndUpload(
          uploadService: uploadService,
          mediaEditorCoordinator: mediaEditorCoordinator,
          tenantId: tenantId,
          representedCompanyId: representedCompanyId,
          scopeKey: scopeKey,
        );

        final state = result.state;
        if (state != null) {
          onStateReady(state);
        }

        final feedbackMessage = result.feedbackMessage;
        if (feedbackMessage != null) {
          onFeedback(feedbackMessage);
        }

        return result.selection;
      } finally {
        onUploadingChanged(false);
      }
    }

    final mediaState = await mediaEditorCoordinator.openLibraryAndBuildState(
      context: context,
      tenantId: tenantId,
      representedCompanyId: representedCompanyId,
      representedCompanyName: representedCompanyName,
      selectedUrl: selectedUrl,
      onUploadNew: onUploadNew,
    );

    if (mediaState == null) {
      return;
    }

    onStateReady(mediaState);
  }
}
