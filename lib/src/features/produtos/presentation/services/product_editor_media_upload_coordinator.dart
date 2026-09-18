import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_media_models.dart';
import 'product_editor_feedback.dart';
import 'product_media_editor_coordinator.dart';
import 'product_media_upload_service.dart';

class ProductEditorMediaUploadResult {
  const ProductEditorMediaUploadResult({
    required this.selection,
    required this.state,
    required this.feedbackMessage,
  });

  final ProductMediaSelection? selection;
  final ProductMediaEditorState? state;
  final String? feedbackMessage;
}

class ProductEditorMediaUploadCoordinator {
  const ProductEditorMediaUploadCoordinator();

  Future<ProductEditorMediaUploadResult> pickAndUpload({
    required ProductMediaUploadService uploadService,
    required ProductMediaEditorCoordinator mediaEditorCoordinator,
    required String tenantId,
    required String? representedCompanyId,
    required String scopeKey,
  }) async {
    try {
      final uploaded = await uploadService.pickAndUpload(
        tenantId: tenantId,
        representedCompanyId: representedCompanyId,
        scopeKey: scopeKey,
      );
      if (uploaded == null) {
        return const ProductEditorMediaUploadResult(
          selection: null,
          state: null,
          feedbackMessage: null,
        );
      }

      final asset = ProductMediaAsset(
        id: uploaded.assetId,
        tenantId: uploaded.tenantId,
        representedCompanyId: uploaded.representedCompanyId,
        scopeKey: uploaded.scopeKey,
        fileName: uploaded.fileName,
        downloadUrl: uploaded.downloadUrl,
        storagePath: uploaded.storagePath,
        thumbnailBase64: uploaded.thumbnailBase64,
        width: uploaded.width,
        height: uploaded.height,
        createdAt: uploaded.createdAt,
        updatedAt: uploaded.updatedAt,
      );
      final selection = ProductMediaSelection(
        asset: asset,
        previewBytes: uploaded.previewBytes,
      );

      return ProductEditorMediaUploadResult(
        selection: selection,
        state: mediaEditorCoordinator.stateFromAsset(
          asset: asset,
          previewBytes: uploaded.previewBytes,
        ),
        feedbackMessage: ProductEditorFeedback.imageUploadSuccessMessage,
      );
    } on FirebaseException catch (error) {
      return ProductEditorMediaUploadResult(
        selection: null,
        state: null,
        feedbackMessage: ProductEditorFeedback.uploadFirebaseFailureMessage(error),
      );
    } on TimeoutException {
      return const ProductEditorMediaUploadResult(
        selection: null,
        state: null,
        feedbackMessage: ProductEditorFeedback.uploadTimeoutFailureMessage,
      );
    } catch (error) {
      return ProductEditorMediaUploadResult(
        selection: null,
        state: null,
        feedbackMessage: ProductEditorFeedback.uploadGenericFailureMessage(error),
      );
    }
  }
}
