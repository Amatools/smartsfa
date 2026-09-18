import 'package:flutter/material.dart';

import '../../../../shared/presentation/theme/app_field_tokens.dart';
import '../../../../shared/presentation/widgets/app_medium_controls.dart';

Widget buildProductEditorField({
  required BuildContext context,
  required TextEditingController controller,
  required String label,
  required bool readOnly,
  required TextStyle inputTextStyle,
  required TextStyle labelStyle,
  required double fieldHeight,
  TextInputType? keyboardType,
  int maxLines = 1,
  TextAlign textAlign = TextAlign.right,
}) {
  if (maxLines == 1) {
    return AppMediumLabeledControl(
      label: label,
      labelStyle: labelStyle,
      height: fieldHeight,
      child: AppMediumTextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        style: inputTextStyle,
        textAlign: textAlign,
        textAlignVertical: TextAlignVertical.center,
      ),
    );
  }

  return TextField(
    controller: controller,
    readOnly: readOnly,
    keyboardType: keyboardType,
    maxLines: maxLines,
    style: inputTextStyle,
    textAlignVertical: TextAlignVertical.top,
    decoration: _compactDecoration(
      context: context,
      inputTextStyle: inputTextStyle,
      labelText: label,
    ),
  );
}

InputDecoration _compactDecoration({
  required BuildContext context,
  required TextStyle inputTextStyle,
  String? labelText,
  String? hintText,
  BorderRadius? borderRadius,
}) {
  final outlineColor = Theme.of(context).colorScheme.outline.withValues(alpha: 0.45);

  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    labelStyle: inputTextStyle,
    isDense: true,
    filled: true,
    fillColor: Theme.of(context).colorScheme.surface,
    contentPadding: AppFieldTokens.mediumFieldContentPadding,
    border: OutlineInputBorder(
      borderSide: BorderSide(color: outlineColor),
      borderRadius: borderRadius ?? AppFieldTokens.mediumFieldRadius,
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: outlineColor),
      borderRadius: borderRadius ?? AppFieldTokens.mediumFieldRadius,
    ),
    disabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: outlineColor),
      borderRadius: borderRadius ?? AppFieldTokens.mediumFieldRadius,
    ),
  );
}