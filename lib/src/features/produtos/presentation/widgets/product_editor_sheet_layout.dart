import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../services/product_editor_initialization_coordinator.dart';
import 'product_editor_field_builder.dart';
import 'product_editor_footer.dart';
import 'product_editor_header.dart';
import 'product_editor_quick_start.dart';
import 'product_editor_tabs_content.dart';

class ProductEditorSheetLayout extends StatelessWidget {
  const ProductEditorSheetLayout({
    super.key,
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
    required this.currencyCode,
    required this.bitolaUnit,
    required this.loadingTablePrice,
    required this.isEnterprise,
    required this.availableBrands,
    required this.bitolaUnits,
    required this.currencyLabels,
    required this.currencyHints,
    required this.inputTextStyle,
    required this.fieldHeight,
    required this.priceFieldWidth,
    required this.priceFieldGap,
    required this.representedCompanyName,
    required this.onCurrencyCodeChanged,
    required this.onBrandSelected,
    required this.onBitolaUnitChanged,
    required this.onClearImage,
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
  final String currencyCode;
  final String bitolaUnit;
  final bool loadingTablePrice;
  final bool isEnterprise;
  final List<String> availableBrands;
  final List<String> bitolaUnits;
  final Map<String, String> currencyLabels;
  final Map<String, String> currencyHints;
  final TextStyle inputTextStyle;
  final double fieldHeight;
  final double priceFieldWidth;
  final double priceFieldGap;
  final String? representedCompanyName;
  final ValueChanged<String> onCurrencyCodeChanged;
  final ValueChanged<String> onBrandSelected;
  final ValueChanged<String> onBitolaUnitChanged;
  final VoidCallback onClearImage;
  final bool isEditing;
  final VoidCallback onDelete;
  final VoidCallback onSave;
  final VoidCallback onSaveAndCreateAnother;

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
                title: title,
                status: status,
                readOnly: readOnly,
                saving: saving,
                labelStyle: labelStyle,
                onClose: onClose,
                onStatusChanged: onStatusChanged,
              ),
              const SizedBox(height: 12),
              ProductEditorQuickStart(
                readOnly: readOnly,
                thumbnailProduto: thumbnailProduto,
                imageTileSize: imageTileSize,
                uploadingImage: uploadingImage,
                currentImageStoragePath: currentImageStoragePath,
                currentImagePreviewBytes: currentImagePreviewBytes,
                onOpenMediaLibrary: onOpenMediaLibrary,
                descricaoController: controllers.descricao,
                codigoFabricanteController: controllers.codigoFabricante,
                unidadeController: controllers.unidade,
                multiploVendaController: controllers.multiploVenda,
                categoryField: categoryField,
                editorFieldBuilder: editorFieldBuilder,
              ),
              const SizedBox(height: 12),
              ProductEditorTabsContent(
                readOnly: readOnly,
                controllers: controllers,
                status: status,
                currencyCode: currencyCode,
                bitolaUnit: bitolaUnit,
                loadingTablePrice: loadingTablePrice,
                isEnterprise: isEnterprise,
                availableBrands: availableBrands,
                bitolaUnits: bitolaUnits,
                currencyLabels: currencyLabels,
                currencyHints: currencyHints,
                labelStyle: labelStyle,
                inputTextStyle: inputTextStyle,
                fieldHeight: fieldHeight,
                priceFieldWidth: priceFieldWidth,
                priceFieldGap: priceFieldGap,
                representedCompanyName: representedCompanyName,
                onStatusChanged: onStatusChanged,
                onCurrencyCodeChanged: onCurrencyCodeChanged,
                onBrandSelected: onBrandSelected,
                onBitolaUnitChanged: onBitolaUnitChanged,
                onOpenMediaLibrary: onOpenMediaLibrary ?? () {},
                onClearImage: onClearImage,
                editorFieldBuilder: editorFieldBuilder,
              ),
              const SizedBox(height: 8),
              ProductEditorFooter(
                readOnly: readOnly,
                isEditing: isEditing,
                saving: saving,
                onClose: onClose,
                onDelete: onDelete,
                onSave: onSave,
                onSaveAndCreateAnother: onSaveAndCreateAnother,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
