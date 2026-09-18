import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';
import '../../../../shared/presentation/widgets/app_medium_controls.dart';
import 'product_editor_field_builder.dart';

class ProductInformationTabSection extends StatelessWidget {
  const ProductInformationTabSection({
    super.key,
    required this.readOnly,
    required this.codigoController,
    required this.status,
    required this.eanController,
    required this.marcaController,
    required this.descricaoLongaController,
    required this.estoqueVersaoController,
    required this.availableBrands,
    required this.labelStyle,
    required this.inputTextStyle,
    required this.fieldHeight,
    required this.imageLibraryField,
    required this.editorFieldBuilder,
    required this.onStatusChanged,
    required this.onBrandSelected,
  });

  final bool readOnly;
  final TextEditingController codigoController;
  final ProductStatus status;
  final TextEditingController eanController;
  final TextEditingController marcaController;
  final TextEditingController descricaoLongaController;
  final TextEditingController estoqueVersaoController;
  final List<String> availableBrands;
  final TextStyle labelStyle;
  final TextStyle inputTextStyle;
  final double fieldHeight;
  final Widget imageLibraryField;
  final ProductEditorFieldBuilder editorFieldBuilder;
  final ValueChanged<ProductStatus> onStatusChanged;
  final ValueChanged<String> onBrandSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: editorFieldBuilder(
                codigoController,
                'Codigo interno',
                readOnly: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppMediumLabeledControl(
                label: 'Status',
                labelStyle: labelStyle,
                height: fieldHeight,
                child: AppMediumDropdown<ProductStatus>(
                  value: status,
                  style: inputTextStyle,
                  icon: const Icon(Icons.expand_more, size: 16),
                  items: ProductStatus.values
                      .map(
                        (item) => DropdownMenuItem<ProductStatus>(
                          value: item,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(item.label, textAlign: TextAlign.right),
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
                          onStatusChanged(value);
                        },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        editorFieldBuilder(eanController, 'EAN/GTIN', readOnly: readOnly),
        const SizedBox(height: 10),
        editorFieldBuilder(marcaController, 'Marca', readOnly: readOnly),
        const SizedBox(height: 8),
        if (availableBrands.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableBrands
                .where((item) => item.toLowerCase() != marcaController.text.trim().toLowerCase())
                .take(12)
                .map(
                  (brand) => ActionChip(
                    label: Text(brand),
                    onPressed: readOnly ? null : () => onBrandSelected(brand),
                  ),
                )
                .toList(growable: false),
          ),
        const SizedBox(height: 10),
        editorFieldBuilder(
          descricaoLongaController,
          'Descricao longa',
          readOnly: readOnly,
          maxLines: 3,
        ),
        const SizedBox(height: 10),
        imageLibraryField,
        const SizedBox(height: 10),
        editorFieldBuilder(
          estoqueVersaoController,
          'Referencia de controle manual',
          readOnly: readOnly,
        ),
      ],
    );
  }
}