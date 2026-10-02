import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'product_editor_field_builder.dart';

class ProductTaxationTabSection extends StatelessWidget {
  static const double _maxFieldWidth = 200;

  const ProductTaxationTabSection({
    super.key,
    required this.readOnly,
    required this.ncmController,
    required this.cestController,
    required this.ipiBaseController,
    required this.editorFieldBuilder,
  });

  final bool readOnly;
  final TextEditingController ncmController;
  final TextEditingController cestController;
  final TextEditingController ipiBaseController;
  final ProductEditorFieldBuilder editorFieldBuilder;

  Widget _buildCompactField(
    BuildContext context,
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < _maxFieldWidth
            ? constraints.maxWidth
            : _maxFieldWidth;
        return SizedBox(
          width: width,
          child: editorFieldBuilder(
            controller,
            label,
            readOnly: readOnly,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildCompactField(
          context,
          ncmController,
          'NCM',
          keyboardType: TextInputType.number,
          inputFormatters: const [_NcmMaskedInputFormatter()],
        ),
        const SizedBox(height: 10),
        _buildCompactField(context, cestController, 'CEST'),
        const SizedBox(height: 10),
        _buildCompactField(
          context,
          ipiBaseController,
          'IPI base (%)',
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }
}

class _NcmMaskedInputFormatter extends TextInputFormatter {
  const _NcmMaskedInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    final masked = _applyMask(limited);

    final endOffset = masked.length;
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: endOffset),
      composing: TextRange.empty,
    );
  }

  String _applyMask(String digits) {
    if (digits.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 8; i++) {
      if (i == 4 || i == 6) {
        buffer.write('.');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
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
        Row(
          children: [
            Expanded(
              child: editorFieldBuilder(
                pesoController,
                'Peso (kg)',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
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
