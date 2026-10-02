import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';
import '../../../../shared/presentation/widgets/app_medium_controls.dart';
import 'product_editor_field_builder.dart';

class ProductInformationTabSection extends StatefulWidget {
  const ProductInformationTabSection({
    super.key,
    required this.readOnly,
    required this.codigoController,
    required this.status,
    required this.eanController,
    required this.marcaController,
    required this.descricaoLongaController,
    required this.availableBrands,
    required this.labelStyle,
    required this.inputTextStyle,
    required this.fieldHeight,
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
  final List<String> availableBrands;
  final TextStyle labelStyle;
  final TextStyle inputTextStyle;
  final double fieldHeight;
  final ProductEditorFieldBuilder editorFieldBuilder;
  final ValueChanged<ProductStatus> onStatusChanged;
  final ValueChanged<String> onBrandSelected;

  @override
  State<ProductInformationTabSection> createState() =>
      _ProductInformationTabSectionState();
}

class _ProductInformationTabSectionState
    extends State<ProductInformationTabSection> {
  static const double _fieldGap = 10;
  static const double _descriptionMinHeight = 96;
  static const double _descriptionMaxHeight = 320;

  double _descriptionHeight = 116;

  Widget _buildStatusField() {
    return AppMediumLabeledControl(
      label: 'Status',
      labelStyle: widget.labelStyle,
      height: widget.fieldHeight,
      child: AppMediumDropdown<ProductStatus>(
        value: widget.status,
        style: widget.inputTextStyle,
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
        onChanged: widget.readOnly
            ? null
            : (value) {
                if (value == null) {
                  return;
                }
                widget.onStatusChanged(value);
              },
      ),
    );
  }

  Widget _buildMainFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= 1200 ? 4 : (maxWidth >= 700 ? 2 : 1);
        final totalGaps = (columns - 1) * _fieldGap;
        final fieldWidth = (maxWidth - totalGaps) / columns;

        return Wrap(
          spacing: _fieldGap,
          runSpacing: _fieldGap,
          children: [
            SizedBox(
              width: fieldWidth,
              child: widget.editorFieldBuilder(
                widget.codigoController,
                'Codigo interno (UID)',
                readOnly: true,
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: widget.editorFieldBuilder(
                widget.eanController,
                'EAN/GTIN',
                readOnly: widget.readOnly,
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: widget.editorFieldBuilder(
                widget.marcaController,
                'Marca',
                readOnly: widget.readOnly,
              ),
            ),
            SizedBox(width: fieldWidth, child: _buildStatusField()),
          ],
        );
      },
    );
  }

  Widget _buildResizableDescriptionField(BuildContext context) {
    final outlineColor = Theme.of(context).colorScheme.outline
        .withValues(alpha: 0.45);
    final fillColor = Theme.of(context).colorScheme.surface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Descricao longa', style: widget.labelStyle),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: fillColor,
            border: Border.all(color: outlineColor),
          ),
          child: Stack(
            children: [
              SizedBox(
                height: _descriptionHeight,
                child: TextField(
                  controller: widget.descricaoLongaController,
                  readOnly: widget.readOnly,
                  keyboardType: TextInputType.multiline,
                  minLines: null,
                  maxLines: null,
                  expands: true,
                  style: widget.inputTextStyle,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.fromLTRB(10, 10, 10, 18),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {
                      setState(() {
                        _descriptionHeight =
                            (_descriptionHeight + details.delta.dy)
                                .clamp(
                                  _descriptionMinHeight,
                                  _descriptionMaxHeight,
                                )
                                .toDouble();
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 2, 8, 4),
                      child: Icon(
                        Icons.drag_handle,
                        size: 16,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildMainFields(),
        const SizedBox(height: 8),
        if (widget.availableBrands.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.availableBrands
                .where(
                  (item) =>
                      item.toLowerCase() !=
                      widget.marcaController.text.trim().toLowerCase(),
                )
                .take(12)
                .map(
                  (brand) => ActionChip(
                    label: Text(brand),
                    onPressed: widget.readOnly
                        ? null
                        : () => widget.onBrandSelected(brand),
                  ),
                )
                .toList(growable: false),
          ),
        const SizedBox(height: 10),
        _buildResizableDescriptionField(context),
      ],
    );
  }
}
