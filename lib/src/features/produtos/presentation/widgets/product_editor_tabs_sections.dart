import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/presentation/widgets/app_medium_controls.dart';
import '../services/product_tax_group_catalog_service.dart';
import 'product_editor_field_builder.dart';

class ProductTaxationTabSection extends StatefulWidget {
  static const double _maxFieldWidth = 200;

  const ProductTaxationTabSection({
    super.key,
    required this.readOnly,
    required this.tenantId,
    required this.taxGroupCatalogService,
    required this.grupoTributarioIdController,
    required this.ncmController,
    required this.cestController,
    required this.ipiBaseController,
    required this.editorFieldBuilder,
  });

  final bool readOnly;
  final String tenantId;
  final ProductTaxGroupCatalogService taxGroupCatalogService;
  final TextEditingController grupoTributarioIdController;
  final TextEditingController ncmController;
  final TextEditingController cestController;
  final TextEditingController ipiBaseController;
  final ProductEditorFieldBuilder editorFieldBuilder;

  @override
  State<ProductTaxationTabSection> createState() =>
      _ProductTaxationTabSectionState();
}

class _ProductTaxationTabSectionState extends State<ProductTaxationTabSection> {
  static const double _maxFieldWidth = ProductTaxationTabSection._maxFieldWidth;

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
          child: widget.editorFieldBuilder(
            controller,
            label,
            readOnly: widget.readOnly,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
          ),
        );
      },
    );
  }

  Widget _buildGrupoTributarioField(BuildContext context) {
    return StreamBuilder<List<ProductTaxGroupCatalogEntry>>(
      stream: widget.taxGroupCatalogService.watchGroups(
        tenantId: widget.tenantId,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCompactField(
                context,
                widget.grupoTributarioIdController,
                'Grupo Tributario (ID)',
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Nao foi possivel carregar os grupos tributarios agora.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        }
        final allGroups =
            snapshot.data ?? const <ProductTaxGroupCatalogEntry>[];
        final availableGroups = allGroups
            .where((group) => group.isActive)
            .toList(growable: false);
        final currentValue = widget.grupoTributarioIdController.text.trim();
        final hasCurrent =
            currentValue.isEmpty ||
            availableGroups.any((group) => group.id == currentValue);
        final dropdownValue = hasCurrent ? currentValue : '';

        final items = <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: '',
            child: Text(
              availableGroups.isEmpty
                  ? 'Sem grupo (cadastre grupos tributarios)'
                  : 'Sem grupo',
              textAlign: TextAlign.left,
            ),
          ),
          ...availableGroups.map(
            (group) => DropdownMenuItem<String>(
              value: group.id,
              child: Text(group.displayLabel, textAlign: TextAlign.left),
            ),
          ),
        ];

        if (!hasCurrent && currentValue.isNotEmpty) {
          items.add(
            DropdownMenuItem<String>(
              value: currentValue,
              child: Text(
                'Grupo atual nao encontrado: $currentValue',
                textAlign: TextAlign.left,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < _maxFieldWidth
                    ? constraints.maxWidth
                    : _maxFieldWidth;
                return SizedBox(
                  width: width,
                  child: AppMediumLabeledControl(
                    label: 'Grupo Tributario',
                    child: AppMediumDropdown<String>(
                      value: dropdownValue,
                      alignment: AlignmentDirectional.centerStart,
                      style: Theme.of(context).textTheme.bodySmall,
                      hint: const Text('Selecione um grupo'),
                      items: items,
                      onChanged: widget.readOnly
                          ? null
                          : (value) {
                              widget.grupoTributarioIdController.text =
                                  (value ?? '').trim();
                              setState(() {});
                            },
                    ),
                  ),
                );
              },
            ),
            if (!widget.readOnly && availableGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Nenhum grupo tributario cadastrado para este workspace.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
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
        _buildGrupoTributarioField(context),
        const SizedBox(height: 10),
        _buildCompactField(
          context,
          widget.ncmController,
          'NCM',
          keyboardType: TextInputType.number,
          inputFormatters: const [_NcmMaskedInputFormatter()],
        ),
        const SizedBox(height: 10),
        _buildCompactField(context, widget.cestController, 'CEST'),
        const SizedBox(height: 10),
        _buildCompactField(
          context,
          widget.ipiBaseController,
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
