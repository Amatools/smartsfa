import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/product_media_models.dart';
import '../widgets/product_media_library_dialog.dart';

class ProductMediaEditorState {
  const ProductMediaEditorState({
    required this.imageExplicitlyCleared,
    required this.fotoUrl,
    required this.currentImagePreviewBytes,
    required this.currentImageStoragePath,
    required this.currentImageThumbBase64,
  });

  final bool imageExplicitlyCleared;
  final String fotoUrl;
  final Uint8List? currentImagePreviewBytes;
  final String? currentImageStoragePath;
  final String? currentImageThumbBase64;
}

class ProductMediaEditorCoordinator {
  const ProductMediaEditorCoordinator();

  Future<ProductMediaEditorState?> openLibraryAndBuildState({
    required BuildContext context,
    required String tenantId,
    required String? representedCompanyId,
    required String? representedCompanyName,
    required String selectedUrl,
    required Future<ProductMediaSelection?> Function() onUploadNew,
  }) async {
    final selection = await openLibrary(
      context: context,
      tenantId: tenantId,
      representedCompanyId: representedCompanyId,
      representedCompanyName: representedCompanyName,
      selectedUrl: selectedUrl,
      onUploadNew: onUploadNew,
    );
    if (selection == null) {
      return null;
    }
    return stateFromSelection(selection);
  }

  Future<ProductMediaSelection?> openLibrary({
    required BuildContext context,
    required String tenantId,
    required String? representedCompanyId,
    required String? representedCompanyName,
    required String selectedUrl,
    required Future<ProductMediaSelection?> Function() onUploadNew,
  }) {
    return showDialog<ProductMediaSelection>(
      context: context,
      builder: (dialogContext) {
        return ProductMediaLibraryDialog(
          tenantId: tenantId,
          representedCompanyId: representedCompanyId,
          representedCompanyName: representedCompanyName,
          selectedUrl: selectedUrl,
          onUploadNew: onUploadNew,
        );
      },
    );
  }

  ProductMediaEditorState clearSelectionState() {
    return const ProductMediaEditorState(
      imageExplicitlyCleared: true,
      fotoUrl: '',
      currentImagePreviewBytes: null,
      currentImageStoragePath: null,
      currentImageThumbBase64: null,
    );
  }

  ProductMediaEditorState emptySelectionState() {
    return const ProductMediaEditorState(
      imageExplicitlyCleared: false,
      fotoUrl: '',
      currentImagePreviewBytes: null,
      currentImageStoragePath: null,
      currentImageThumbBase64: null,
    );
  }

  ProductMediaEditorState stateFromSelection(ProductMediaSelection selection) {
    if (selection.withoutImage) {
      return clearSelectionState();
    }
    final selectedAsset = selection.asset;
    if (selectedAsset == null) {
      return clearSelectionState();
    }
    return stateFromAsset(
      asset: selectedAsset,
      previewBytes: selection.previewBytes,
    );
  }

  ProductMediaEditorState stateFromAsset({
    required ProductMediaAsset asset,
    Uint8List? previewBytes,
  }) {
    return ProductMediaEditorState(
      imageExplicitlyCleared: false,
      fotoUrl: asset.downloadUrl,
      currentImagePreviewBytes: previewBytes,
      currentImageStoragePath: asset.storagePath,
      currentImageThumbBase64: asset.thumbnailBase64,
    );
  }
}