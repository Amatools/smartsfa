import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../services/product_editor_initialization_coordinator.dart';
import 'product_editor_field_builder.dart';
import 'product_editor_tabs_payload.dart';

class ProductEditorSheetLayoutPayload {
  const ProductEditorSheetLayoutPayload({
    required this.readOnly,
    required this.title,
    required this.status,
    required this.saving,
    required this.labelStyle,
    required this.onClose,
    required this.onStatusChanged,
    required this.thumbnailProduto,
    required this.imageTileSize,
    required this.uploadingImage,
    required this.currentImageStoragePath,
    required this.currentImagePreviewBytes,
    required this.onOpenMediaLibrary,
    required this.controllers,
    required this.categoryField,
    required this.editorFieldBuilder,
    required this.tabsPayload,
    required this.isEditing,
    required this.onDelete,
    required this.onSave,
    required this.onSaveAndCreateAnother,
  });

  final bool readOnly;
  final String title;
  final ProductStatus status;
  final bool saving;
  final TextStyle labelStyle;
  final VoidCallback onClose;
  final ValueChanged<ProductStatus> onStatusChanged;
  final Produto thumbnailProduto;
  final double imageTileSize;
  final bool uploadingImage;
  final String? currentImageStoragePath;
  final Uint8List? currentImagePreviewBytes;
  final VoidCallback? onOpenMediaLibrary;
  final ProductEditorFormControllers controllers;
  final Widget categoryField;
  final ProductEditorFieldBuilder editorFieldBuilder;
  final ProductEditorTabsPayload tabsPayload;
  final bool isEditing;
  final VoidCallback onDelete;
  final VoidCallback onSave;
  final VoidCallback onSaveAndCreateAnother;
}
