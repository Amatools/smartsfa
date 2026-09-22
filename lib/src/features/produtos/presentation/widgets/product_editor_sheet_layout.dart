import 'package:flutter/material.dart';

import 'product_editor_footer.dart';
import 'product_editor_header.dart';
import 'product_editor_quick_start.dart';
import 'product_editor_sheet_layout_payload.dart';
import 'product_editor_tabs_content.dart';

class ProductEditorSheetLayout extends StatelessWidget {
  const ProductEditorSheetLayout({super.key, required this.payload});

  final ProductEditorSheetLayoutPayload payload;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DefaultTabController(
          length: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductEditorHeader(
                title: payload.title,
                status: payload.status,
                readOnly: payload.readOnly,
                saving: payload.saving,
                labelStyle: payload.labelStyle,
                onClose: payload.onClose,
                onStatusChanged: payload.onStatusChanged,
              ),
              const SizedBox(height: 12),
              ProductEditorQuickStart(
                readOnly: payload.readOnly,
                thumbnailProduto: payload.thumbnailProduto,
                imageTileSize: payload.imageTileSize,
                uploadingImage: payload.uploadingImage,
                currentImageStoragePath: payload.currentImageStoragePath,
                currentImagePreviewBytes: payload.currentImagePreviewBytes,
                onOpenMediaLibrary: payload.onOpenMediaLibrary,
                descricaoController: payload.controllers.descricao,
                codigoFabricanteController:
                    payload.controllers.codigoFabricante,
                unidadeController: payload.controllers.unidade,
                multiploVendaController: payload.controllers.multiploVenda,
                categoryField: payload.categoryField,
                editorFieldBuilder: payload.editorFieldBuilder,
              ),
              const SizedBox(height: 12),
              ProductEditorTabsContent(payload: payload.tabsPayload),
              const SizedBox(height: 40),
              ProductEditorFooter(
                readOnly: payload.readOnly,
                isEditing: payload.isEditing,
                saving: payload.saving,
                onClose: payload.onClose,
                onDelete: payload.onDelete,
                onSave: payload.onSave,
                onSaveAndCreateAnother: payload.onSaveAndCreateAnother,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
