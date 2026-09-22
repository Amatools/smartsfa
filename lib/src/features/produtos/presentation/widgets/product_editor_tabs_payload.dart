import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';
import '../services/product_editor_initialization_coordinator.dart';
import 'product_editor_field_builder.dart';

class ProductEditorTabsPayload {
  const ProductEditorTabsPayload({
    required this.readOnly,
    required this.controllers,
    required this.status,
    required this.currencyCode,
    required this.bitolaUnit,
    required this.loadingTablePrice,
    required this.isEnterprise,
    required this.availableBrands,
    required this.bitolaUnits,
    required this.currencyLabels,
    required this.currencyHints,
    required this.labelStyle,
    required this.inputTextStyle,
    required this.fieldHeight,
    required this.priceFieldWidth,
    required this.priceFieldGap,
    required this.representedCompanyName,
    required this.onStatusChanged,
    required this.onCurrencyCodeChanged,
    required this.onBrandSelected,
    required this.onBitolaUnitChanged,
    required this.onOpenMediaLibrary,
    required this.onClearImage,
    required this.editorFieldBuilder,
  });

  final bool readOnly;
  final ProductEditorFormControllers controllers;
  final ProductStatus status;
  final String currencyCode;
  final String bitolaUnit;
  final bool loadingTablePrice;
  final bool isEnterprise;
  final List<String> availableBrands;
  final List<String> bitolaUnits;
  final Map<String, String> currencyLabels;
  final Map<String, String> currencyHints;
  final TextStyle labelStyle;
  final TextStyle inputTextStyle;
  final double fieldHeight;
  final double priceFieldWidth;
  final double priceFieldGap;
  final String? representedCompanyName;
  final ValueChanged<ProductStatus> onStatusChanged;
  final ValueChanged<String> onCurrencyCodeChanged;
  final ValueChanged<String> onBrandSelected;
  final ValueChanged<String> onBitolaUnitChanged;
  final VoidCallback onOpenMediaLibrary;
  final VoidCallback onClearImage;
  final ProductEditorFieldBuilder editorFieldBuilder;
}
