import 'package:flutter/material.dart';

import '../../../../shared/presentation/theme/app_field_tokens.dart';
import 'product_editor_fields.dart';

class ProductEditorFieldStyleFactory {
  const ProductEditorFieldStyleFactory();

  TextStyle inputTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: AppFieldTokens.mediumFieldFontSize,
          height: 1.0,
        ) ??
        const TextStyle(
          fontSize: AppFieldTokens.mediumFieldFontSize,
          height: 1.0,
        );
  }

  TextStyle labelStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: AppFieldTokens.mediumFieldLabelFontSize,
          fontWeight: FontWeight.w500,
          height: 1.15,
        ) ??
        const TextStyle(
          fontSize: AppFieldTokens.mediumFieldLabelFontSize,
          fontWeight: FontWeight.w500,
          height: 1.15,
        );
  }

  Widget buildEditorField({
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
    return buildProductEditorField(
      context: context,
      controller: controller,
      label: label,
      readOnly: readOnly,
      inputTextStyle: inputTextStyle,
      labelStyle: labelStyle,
      fieldHeight: fieldHeight,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textAlign: textAlign,
    );
  }
}
