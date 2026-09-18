import 'package:flutter/material.dart';

import '../../../../shared/presentation/widgets/app_medium_controls.dart';
import '../services/product_category_options_resolver.dart';

class ProductCategoryDropdownField extends StatelessWidget {
  const ProductCategoryDropdownField({
    super.key,
    required this.workspaceStream,
    required this.representedCompanyId,
    required this.categoriaController,
    required this.readOnly,
    required this.labelStyle,
    required this.inputTextStyle,
    required this.fieldHeight,
    required this.onCategoryChanged,
  });

  final Stream<Map<String, dynamic>?> workspaceStream;
  final String? representedCompanyId;
  final TextEditingController categoriaController;
  final bool readOnly;
  final TextStyle labelStyle;
  final TextStyle inputTextStyle;
  final double fieldHeight;
  final ValueChanged<String> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: workspaceStream,
      initialData: const <String, dynamic>{},
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        final categorySelection = ProductCategoryOptionsResolver.resolve(
          workspaceData: data,
          representedCompanyId: representedCompanyId,
          currentCategory: categoriaController.text,
        );
        final options = categorySelection.options;
        final effectiveValue = categorySelection.effectiveValue;
        if (effectiveValue != null && categoriaController.text != effectiveValue) {
          categoriaController.text = effectiveValue;
        }

        return AppMediumLabeledControl(
          label: 'Categoria',
          labelStyle: labelStyle,
          height: fieldHeight,
          child: AppMediumDropdown<String>(
            value: effectiveValue,
            style: inputTextStyle,
            icon: const Icon(Icons.expand_more, size: 16),
            hint: const Text('Cadastre categorias em Configuracoes > Categorias'),
            items: options
                .map(
                  (category) => DropdownMenuItem<String>(
                    value: category,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(category, textAlign: TextAlign.right),
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: readOnly || options.isEmpty
                ? null
                : (value) => onCategoryChanged(value?.trim() ?? ''),
          ),
        );
      },
    );
  }
}