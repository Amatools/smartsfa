import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';
import '../services/product_editor_initialization_coordinator.dart';
import 'product_editor_compact_tab.dart';
import 'product_editor_field_builder.dart';
import 'product_editor_information_tab_section.dart';
import 'product_editor_price_tab_fields.dart';
import 'product_editor_tabs_sections.dart';
import 'product_editor_tabs_shell.dart';
import 'product_editor_variations_tab_section.dart';
import 'product_image_library_field.dart';

class ProductEditorTabsContent extends StatelessWidget {
  const ProductEditorTabsContent({
    super.key,
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

  @override
  Widget build(BuildContext context) {
    return ProductEditorTabsShell(
      priceTab: _buildPriceTab(),
      informationTab: _buildInformationTab(context),
      fiscalTab: _buildFiscalTab(),
      variationsTab: _buildVariationsTab(),
      weightDimensionsTab: _buildWeightAndDimensionsTab(),
    );
  }

  Widget _buildPriceTab() {
    return ProductEditorCompactTab(
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: priceFieldGap,
          runSpacing: 12,
          children: [
            ProductCurrencySelectorField(
              readOnly: readOnly,
              currencyCode: currencyCode,
              currencyLabels: currencyLabels,
              labelStyle: labelStyle,
              inputTextStyle: inputTextStyle,
              fieldHeight: fieldHeight,
              onChanged: onCurrencyCodeChanged,
            ),
            SizedBox(
              width: priceFieldWidth,
              child: ProductGroupedMoneyField(
                label: 'Preco Minimo',
                controller: controllers.precoMinimo,
                currencyCode: currencyCode,
                currencyLabels: currencyLabels,
                currencyHints: currencyHints,
                readOnly: readOnly,
                inputTextStyle: inputTextStyle,
                labelStyle: labelStyle,
                fieldHeight: fieldHeight,
                fieldWidth: priceFieldWidth,
                showInfoIcon: true,
              ),
            ),
            SizedBox(
              width: priceFieldWidth,
              child: ProductGroupedMoneyField(
                label: '* Preco de Tabela',
                controller: controllers.precoTabela,
                currencyCode: currencyCode,
                currencyLabels: currencyLabels,
                currencyHints: currencyHints,
                readOnly: readOnly,
                inputTextStyle: inputTextStyle,
                labelStyle: labelStyle,
                fieldHeight: fieldHeight,
                fieldWidth: priceFieldWidth,
              ),
            ),
          ],
        ),
        if (loadingTablePrice) _buildPriceTableSyncLoadingIndicator(),
      ],
    );
  }

  Widget _buildPriceTableSyncLoadingIndicator() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 8),
        LinearProgressIndicator(minHeight: 2),
        SizedBox(height: 4),
        Text('Sincronizando valor com a tabela padrão...'),
      ],
    );
  }

  Widget _buildInformationTab(BuildContext context) {
    return ProductEditorCompactTab(
      children: [
        ProductInformationTabSection(
          readOnly: readOnly,
          codigoController: controllers.codigo,
          status: status,
          eanController: controllers.ean,
          marcaController: controllers.marca,
          descricaoLongaController: controllers.descricaoLonga,
          estoqueVersaoController: controllers.estoqueVersao,
          availableBrands: availableBrands,
          labelStyle: labelStyle,
          inputTextStyle: inputTextStyle,
          fieldHeight: fieldHeight,
          imageLibraryField: _buildInformationImageLibraryField(context),
          editorFieldBuilder: editorFieldBuilder,
          onStatusChanged: onStatusChanged,
          onBrandSelected: onBrandSelected,
        ),
      ],
    );
  }

  String _buildImageLibraryScopeLabel() {
    final representedName = (representedCompanyName ?? '').trim();
    if (representedName.isNotEmpty) {
      return representedName;
    }
    return 'Tenant principal';
  }

  Widget _buildInformationImageLibraryField(BuildContext context) {
    return ProductImageLibraryField(
      readOnly: readOnly,
      hasImage: controllers.fotoUrl.text.trim().isNotEmpty,
      scopeLabel: _buildImageLibraryScopeLabel(),
      helperTextStyle: Theme.of(context).textTheme.bodySmall,
      onOpenLibrary: onOpenMediaLibrary,
      onClearImage: onClearImage,
    );
  }

  Widget _buildFiscalTab() {
    return ProductEditorCompactTab(
      children: [
        ProductFiscalTabSection(
          readOnly: readOnly,
          ncmController: controllers.ncm,
          cfopController: controllers.cfop,
          icmsController: controllers.icms,
          pisController: controllers.pis,
          cofinsController: controllers.cofins,
          editorFieldBuilder: editorFieldBuilder,
        ),
      ],
    );
  }

  Widget _buildVariationsTab() {
    return ProductEditorCompactTab(
      children: [
        ProductVariationsTabSection(
          readOnly: readOnly,
          isEnterprise: isEnterprise,
          bitolaController: controllers.bitola,
          subcategoriaController: controllers.subcategoria,
          tabelaVersaoController: controllers.tabelaVersao,
          multiploVendaController: controllers.multiploVenda,
          estoqueVersaoController: controllers.estoqueVersao,
          erpProductIdController: controllers.erpProductId,
          erpSyncIdController: controllers.erpSyncId,
          bitolaUnit: bitolaUnit,
          bitolaUnits: bitolaUnits,
          labelStyle: labelStyle,
          inputTextStyle: inputTextStyle,
          fieldHeight: fieldHeight,
          onBitolaUnitChanged: onBitolaUnitChanged,
          editorFieldBuilder: editorFieldBuilder,
        ),
      ],
    );
  }

  Widget _buildWeightAndDimensionsTab() {
    return ProductEditorCompactTab(
      children: [
        ProductWeightDimensionsTabSection(
          readOnly: readOnly,
          pesoController: controllers.peso,
          comprimentoMmController: controllers.comprimentoMm,
          larguraMmController: controllers.larguraMm,
          alturaMmController: controllers.alturaMm,
          editorFieldBuilder: editorFieldBuilder,
        ),
      ],
    );
  }
}
