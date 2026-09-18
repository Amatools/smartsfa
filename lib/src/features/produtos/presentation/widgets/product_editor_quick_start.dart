import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/models/produto.dart';
import 'product_editor_field_builder.dart';
import 'product_thumbnail.dart';

class ProductEditorQuickStart extends StatelessWidget {
  const ProductEditorQuickStart({
    super.key,
    required this.readOnly,
    required this.thumbnailProduto,
    required this.imageTileSize,
    required this.uploadingImage,
    required this.currentImageStoragePath,
    required this.currentImagePreviewBytes,
    required this.onOpenMediaLibrary,
    required this.descricaoController,
    required this.codigoFabricanteController,
    required this.unidadeController,
    required this.multiploVendaController,
    required this.categoryField,
    required this.editorFieldBuilder,
  });

  final bool readOnly;
  final Produto thumbnailProduto;
  final double imageTileSize;
  final bool uploadingImage;
  final String? currentImageStoragePath;
  final Uint8List? currentImagePreviewBytes;
  final VoidCallback? onOpenMediaLibrary;
  final TextEditingController descricaoController;
  final TextEditingController codigoFabricanteController;
  final TextEditingController unidadeController;
  final TextEditingController multiploVendaController;
  final Widget categoryField;
  final ProductEditorFieldBuilder editorFieldBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductThumbnail(
              produto: thumbnailProduto,
              size: imageTileSize,
              uploading: uploadingImage,
              storagePath: currentImageStoragePath,
              previewBytes: currentImagePreviewBytes,
              onTap: onOpenMediaLibrary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: editorFieldBuilder(descricaoController, 'Nome *', readOnly: readOnly),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 160,
              child: editorFieldBuilder(
                codigoFabricanteController,
                'Codigo',
                readOnly: readOnly,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 180,
              child: editorFieldBuilder(
                unidadeController,
                'Unidade de medida',
                readOnly: readOnly,
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 180,
              child: editorFieldBuilder(
                multiploVendaController,
                'Venda em multiplos de',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: categoryField,
            ),
          ],
        ),
      ],
    );
  }
}