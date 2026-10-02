import 'package:flutter/material.dart';

import 'product_editor_compact_tab.dart';
import 'product_editor_information_tab_section.dart';
import 'product_editor_price_tab_fields.dart';
import 'product_editor_tabs_payload.dart';
import 'product_editor_tabs_sections.dart';
import 'product_editor_tabs_shell.dart';
import 'product_editor_variations_tab_section.dart';

class ProductEditorTabsContent extends StatelessWidget {
  const ProductEditorTabsContent({super.key, required this.payload});

  final ProductEditorTabsPayload payload;

  @override
  Widget build(BuildContext context) {
    return ProductEditorTabsShell(
      priceTab: _buildPriceTab(),
      informationTab: _buildInformationTab(),
      taxationTab: _buildTaxationTab(),
      variationsTab: _buildVariationsTab(),
      weightDimensionsTab: _buildWeightAndDimensionsTab(),
    );
  }

  Widget _buildPriceTab() {
    return ProductEditorCompactTab(
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: payload.priceFieldGap,
          runSpacing: 12,
          children: [
            ProductCurrencySelectorField(
              readOnly: payload.readOnly,
              currencyCode: payload.currencyCode,
              currencyLabels: payload.currencyLabels,
              labelStyle: payload.labelStyle,
              inputTextStyle: payload.inputTextStyle,
              fieldHeight: payload.fieldHeight,
              onChanged: payload.onCurrencyCodeChanged,
            ),
            SizedBox(
              width: payload.priceFieldWidth,
              child: ProductGroupedMoneyField(
                label: 'Preco Minimo',
                controller: payload.controllers.precoMinimo,
                currencyCode: payload.currencyCode,
                currencyLabels: payload.currencyLabels,
                currencyHints: payload.currencyHints,
                readOnly: payload.readOnly,
                inputTextStyle: payload.inputTextStyle,
                labelStyle: payload.labelStyle,
                fieldHeight: payload.fieldHeight,
                fieldWidth: payload.priceFieldWidth,
                showInfoIcon: true,
              ),
            ),
            SizedBox(
              width: payload.priceFieldWidth,
              child: ProductGroupedMoneyField(
                label: '* Preco de Tabela',
                controller: payload.controllers.precoTabela,
                currencyCode: payload.currencyCode,
                currencyLabels: payload.currencyLabels,
                currencyHints: payload.currencyHints,
                readOnly: payload.readOnly,
                inputTextStyle: payload.inputTextStyle,
                labelStyle: payload.labelStyle,
                fieldHeight: payload.fieldHeight,
                fieldWidth: payload.priceFieldWidth,
              ),
            ),
          ],
        ),
        if (payload.loadingTablePrice) _buildPriceTableSyncLoadingIndicator(),
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

  Widget _buildInformationTab() {
    return ProductEditorCompactTab(
      children: [
        ProductInformationTabSection(
          readOnly: payload.readOnly,
          codigoController: payload.controllers.codigo,
          status: payload.status,
          eanController: payload.controllers.ean,
          marcaController: payload.controllers.marca,
          descricaoLongaController: payload.controllers.descricaoLonga,
          availableBrands: payload.availableBrands,
          labelStyle: payload.labelStyle,
          inputTextStyle: payload.inputTextStyle,
          fieldHeight: payload.fieldHeight,
          editorFieldBuilder: payload.editorFieldBuilder,
          onStatusChanged: payload.onStatusChanged,
          onBrandSelected: payload.onBrandSelected,
        ),
        const SizedBox(height: 10),
        ProductVariationsTabSection(
          readOnly: payload.readOnly,
          tenantId: payload.tenantId,
          unitCatalogService: payload.unitCatalogService,
          isEnterprise: payload.isEnterprise,
          bitolaController: payload.controllers.bitola,
          erpProductIdController: payload.controllers.erpProductId,
          erpSyncIdController: payload.controllers.erpSyncId,
          bitolaUnit: payload.bitolaUnit,
          labelStyle: payload.labelStyle,
          inputTextStyle: payload.inputTextStyle,
          fieldHeight: payload.fieldHeight,
          onBitolaUnitChanged: payload.onBitolaUnitChanged,
          editorFieldBuilder: payload.editorFieldBuilder,
        ),
      ],
    );
  }

  Widget _buildTaxationTab() {
    return ProductEditorCompactTab(
      children: [
        ProductTaxationTabSection(
          readOnly: payload.readOnly,
          ncmController: payload.controllers.ncm,
          cestController: payload.controllers.cest,
          ipiBaseController: payload.controllers.ipiBase,
          editorFieldBuilder: payload.editorFieldBuilder,
        ),
      ],
    );
  }

  Widget _buildVariationsTab() {
    return ProductEditorCompactTab(
      children: [
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Use esta aba para variacoes de produto (ex.: combinacoes de atributos, grade e regras especificas por variacao).',
              style: payload.inputTextStyle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeightAndDimensionsTab() {
    return ProductEditorCompactTab(
      children: [
        ProductWeightDimensionsTabSection(
          readOnly: payload.readOnly,
          pesoController: payload.controllers.peso,
          comprimentoMmController: payload.controllers.comprimentoMm,
          larguraMmController: payload.controllers.larguraMm,
          alturaMmController: payload.controllers.alturaMm,
          editorFieldBuilder: payload.editorFieldBuilder,
        ),
      ],
    );
  }
}
