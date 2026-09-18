import 'package:flutter/material.dart';

import 'product_editor_field_builder.dart';

class ProductFiscalTabSection extends StatelessWidget {
  const ProductFiscalTabSection({
    super.key,
    required this.readOnly,
    required this.ncmController,
    required this.cfopController,
    required this.icmsController,
    required this.pisController,
    required this.cofinsController,
    required this.editorFieldBuilder,
  });

  final bool readOnly;
  final TextEditingController ncmController;
  final TextEditingController cfopController;
  final TextEditingController icmsController;
  final TextEditingController pisController;
  final TextEditingController cofinsController;
  final ProductEditorFieldBuilder editorFieldBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: editorFieldBuilder(ncmController, 'NCM', readOnly: readOnly)),
            const SizedBox(width: 10),
            Expanded(child: editorFieldBuilder(cfopController, 'CFOP', readOnly: readOnly)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: editorFieldBuilder(
                icmsController,
                'ICMS (%)',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: editorFieldBuilder(
                pisController,
                'PIS (%)',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: editorFieldBuilder(
                cofinsController,
                'COFINS (%)',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ProductWeightDimensionsTabSection extends StatelessWidget {
  const ProductWeightDimensionsTabSection({
    super.key,
    required this.readOnly,
    required this.pesoController,
    required this.comprimentoMmController,
    required this.larguraMmController,
    required this.alturaMmController,
    required this.editorFieldBuilder,
  });

  final bool readOnly;
  final TextEditingController pesoController;
  final TextEditingController comprimentoMmController;
  final TextEditingController larguraMmController;
  final TextEditingController alturaMmController;
  final ProductEditorFieldBuilder editorFieldBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        editorFieldBuilder(
          pesoController,
          'Peso (kg)',
          readOnly: readOnly,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: editorFieldBuilder(
                comprimentoMmController,
                'Comprimento (mm)',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: editorFieldBuilder(
                larguraMmController,
                'Largura (mm)',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: editorFieldBuilder(
                alturaMmController,
                'Altura (mm)',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
    );
  }
}