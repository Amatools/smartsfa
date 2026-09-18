import 'package:flutter/material.dart';

import '../../../../shared/presentation/widgets/app_medium_controls.dart';

class ProductCurrencySelectorField extends StatelessWidget {
  const ProductCurrencySelectorField({
    super.key,
    required this.readOnly,
    required this.currencyCode,
    required this.currencyLabels,
    required this.labelStyle,
    required this.inputTextStyle,
    required this.fieldHeight,
    required this.onChanged,
  });

  final bool readOnly;
  final String currencyCode;
  final Map<String, String> currencyLabels;
  final TextStyle labelStyle;
  final TextStyle inputTextStyle;
  final double fieldHeight;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppMediumLabeledControl(
      label: 'Moeda',
      width: 112,
      height: fieldHeight,
      labelStyle: labelStyle,
      child: AppMediumDropdown<String>(
        value: currencyCode,
        style: inputTextStyle,
        icon: const Icon(Icons.expand_more, size: 16),
        items: currencyLabels.entries
            .map(
              (entry) => DropdownMenuItem<String>(
                value: entry.key,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${entry.value} (${entry.key})',
                    style: inputTextStyle,
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            )
            .toList(growable: false),
        onChanged: readOnly
            ? null
            : (value) {
                if (value == null || value == currencyCode) {
                  return;
                }
                onChanged(value);
              },
      ),
    );
  }
}

class ProductGroupedMoneyField extends StatelessWidget {
  const ProductGroupedMoneyField({
    super.key,
    required this.label,
    required this.controller,
    required this.currencyCode,
    required this.currencyLabels,
    required this.currencyHints,
    required this.readOnly,
    required this.inputTextStyle,
    required this.labelStyle,
    required this.fieldHeight,
    required this.fieldWidth,
    this.showInfoIcon = false,
  });

  final String label;
  final TextEditingController controller;
  final String currencyCode;
  final Map<String, String> currencyLabels;
  final Map<String, String> currencyHints;
  final bool readOnly;
  final TextStyle inputTextStyle;
  final TextStyle labelStyle;
  final double fieldHeight;
  final double fieldWidth;
  final bool showInfoIcon;

  @override
  Widget build(BuildContext context) {
    final currencyLabel = currencyLabels[currencyCode] ?? currencyCode;
    final hint = currencyHints[currencyCode] ?? '0,00';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: labelStyle),
            if (showInfoIcon) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.info_outline,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: fieldWidth,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: fieldHeight,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      bottomLeft: Radius.circular(6),
                    ),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.45),
                    ),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.5),
                        blurRadius: 2,
                        spreadRadius: -1,
                        offset: const Offset(0, 1),
                        blurStyle: BlurStyle.inner,
                      ),
                    ],
                  ),
                  child: Text(
                    currencyLabel,
                    style: inputTextStyle,
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: fieldHeight,
                  child: AppMediumTextField(
                    controller: controller,
                    readOnly: readOnly,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: inputTextStyle,
                    hintText: hint,
                    hintStyle: inputTextStyle,
                    textAlign: TextAlign.right,
                    textAlignVertical: const TextAlignVertical(y: -0.05),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}