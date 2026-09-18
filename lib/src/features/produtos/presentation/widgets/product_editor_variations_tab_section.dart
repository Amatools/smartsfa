import 'package:flutter/material.dart';

import '../../../../shared/presentation/widgets/app_medium_controls.dart';
import 'product_editor_field_builder.dart';

class ProductVariationsTabSection extends StatelessWidget {
  const ProductVariationsTabSection({
    super.key,
    required this.readOnly,
    required this.isEnterprise,
    required this.bitolaController,
    required this.subcategoriaController,
    required this.tabelaVersaoController,
    required this.multiploVendaController,
    required this.estoqueVersaoController,
    required this.erpProductIdController,
    required this.erpSyncIdController,
    required this.bitolaUnit,
    required this.bitolaUnits,
    required this.labelStyle,
    required this.inputTextStyle,
    required this.fieldHeight,
    required this.onBitolaUnitChanged,
    required this.editorFieldBuilder,
  });

  final bool readOnly;
  final bool isEnterprise;
  final TextEditingController bitolaController;
  final TextEditingController subcategoriaController;
  final TextEditingController tabelaVersaoController;
  final TextEditingController multiploVendaController;
  final TextEditingController estoqueVersaoController;
  final TextEditingController erpProductIdController;
  final TextEditingController erpSyncIdController;
  final String bitolaUnit;
  final List<String> bitolaUnits;
  final TextStyle labelStyle;
  final TextStyle inputTextStyle;
  final double fieldHeight;
  final ValueChanged<String> onBitolaUnitChanged;
  final ProductEditorFieldBuilder editorFieldBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: editorFieldBuilder(
                bitolaController,
                'Bitola / medida',
                readOnly: readOnly,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppMediumLabeledControl(
                label: 'Unidade da bitola',
                labelStyle: labelStyle,
                height: fieldHeight,
                child: AppMediumDropdown<String>(
                  value: bitolaUnit,
                  style: inputTextStyle,
                  icon: const Icon(Icons.expand_more, size: 16),
                  items: bitolaUnits
                      .map(
                        (unit) => DropdownMenuItem<String>(
                          value: unit,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(unit.toUpperCase(), textAlign: TextAlign.right),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: readOnly
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          onBitolaUnitChanged(value);
                        },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: editorFieldBuilder(
                subcategoriaController,
                'Subcategoria',
                readOnly: readOnly,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: editorFieldBuilder(
                tabelaVersaoController,
                'Versao de tabela',
                readOnly: readOnly,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        editorFieldBuilder(
          multiploVendaController,
          'Multiplo de venda',
          readOnly: readOnly,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 10),
        editorFieldBuilder(
          estoqueVersaoController,
          'Referencia de controle manual',
          readOnly: readOnly,
        ),
        if (isEnterprise) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: editorFieldBuilder(
                  erpProductIdController,
                  'ID do produto no ERP',
                  readOnly: readOnly,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: editorFieldBuilder(
                  erpSyncIdController,
                  'ID de sincronizacao ERP',
                  readOnly: readOnly,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}