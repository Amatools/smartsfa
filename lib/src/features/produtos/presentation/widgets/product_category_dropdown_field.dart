import 'package:flutter/material.dart';

import '../../../../shared/presentation/widgets/app_medium_controls.dart';
import '../services/product_category_options_resolver.dart';

class ProductCategoryDropdownField extends StatelessWidget {
  const ProductCategoryDropdownField({
    super.key,
    required this.workspaceStream,
    required this.representedCompanyId,
    required this.categoriaController,
    required this.subcategoriaController,
    required this.readOnly,
    required this.labelStyle,
    required this.inputTextStyle,
    required this.fieldHeight,
    required this.onCategoryChanged,
    required this.onSubcategoryChanged,
  });

  final Stream<Map<String, dynamic>?> workspaceStream;
  final String? representedCompanyId;
  final TextEditingController categoriaController;
  final TextEditingController subcategoriaController;
  final bool readOnly;
  final TextStyle labelStyle;
  final TextStyle inputTextStyle;
  final double fieldHeight;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onSubcategoryChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: workspaceStream,
      initialData: const <String, dynamic>{},
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        final taxonomySelection = ProductCategoryOptionsResolver.resolve(
          workspaceData: data,
          representedCompanyId: representedCompanyId,
          currentCategory: categoriaController.text,
          currentSubcategory: subcategoriaController.text,
        );
        final options = taxonomySelection.categories;
        final effectiveValue = taxonomySelection.effectiveCategory;
        if (effectiveValue != null &&
            categoriaController.text != effectiveValue) {
          categoriaController.text = effectiveValue;
        }
        if (taxonomySelection.effectiveSubcategory != null &&
            subcategoriaController.text !=
                taxonomySelection.effectiveSubcategory) {
          subcategoriaController.text = taxonomySelection.effectiveSubcategory!;
        }

        return AppMediumLabeledControl(
          label: 'Categoria',
          labelStyle: labelStyle,
          height: fieldHeight,
          child: AppMediumDropdown<String>(
            value: effectiveValue,
            style: inputTextStyle,
            alignment: AlignmentDirectional.centerStart,
            icon: const Icon(Icons.expand_more, size: 16),
            hint: const Text('Cadastre categorias em Configuracoes > Categorias'),
            items: options
                .map(
                  (category) => DropdownMenuItem<String>(
                    value: category,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(category, textAlign: TextAlign.left),
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: readOnly || options.isEmpty
                ? null
                : (value) {
                    final selectedCategory = value?.trim() ?? '';
                    onCategoryChanged(selectedCategory);
                    final subcategoryOptions =
                        taxonomySelection.subcategoriesByCategory[
                            selectedCategory] ??
                        const <String>[];
                    onSubcategoryChanged(
                      subcategoryOptions.isNotEmpty ? subcategoryOptions.first : '',
                    );
                  },
          ),
        );
      },
    );
  }
}

class ProductSubcategoryDropdownField extends StatelessWidget {
  const ProductSubcategoryDropdownField({
    super.key,
    required this.workspaceStream,
    required this.representedCompanyId,
    required this.categoriaController,
    required this.subcategoriaController,
    required this.readOnly,
    required this.labelStyle,
    required this.inputTextStyle,
    required this.fieldHeight,
    required this.onSubcategoryChanged,
  });

  final Stream<Map<String, dynamic>?> workspaceStream;
  final String? representedCompanyId;
  final TextEditingController categoriaController;
  final TextEditingController subcategoriaController;
  final bool readOnly;
  final TextStyle labelStyle;
  final TextStyle inputTextStyle;
  final double fieldHeight;
  final ValueChanged<String> onSubcategoryChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: workspaceStream,
      initialData: const <String, dynamic>{},
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        final taxonomySelection = ProductCategoryOptionsResolver.resolve(
          workspaceData: data,
          representedCompanyId: representedCompanyId,
          currentCategory: categoriaController.text,
          currentSubcategory: subcategoriaController.text,
        );

        final options = taxonomySelection.subcategoryOptions;
        final effectiveValue = taxonomySelection.effectiveSubcategory;
        if (effectiveValue != null &&
            subcategoriaController.text != effectiveValue) {
          subcategoriaController.text = effectiveValue;
        }

        return AppMediumLabeledControl(
          label: 'Subcategoria',
          labelStyle: labelStyle,
          height: fieldHeight,
          child: AppMediumDropdown<String>(
            value: effectiveValue,
            style: inputTextStyle,
            alignment: AlignmentDirectional.centerStart,
            icon: const Icon(Icons.expand_more, size: 16),
            hint: taxonomySelection.effectiveCategory == null
                ? const Text('Selecione uma categoria')
                : const Text('Cadastre subcategorias em Configuracoes > Categorias'),
            items: options
                .map(
                  (subcategory) => DropdownMenuItem<String>(
                    value: subcategory,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(subcategory, textAlign: TextAlign.left),
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: readOnly || options.isEmpty
                ? null
                : (value) => onSubcategoryChanged(value?.trim() ?? ''),
          ),
        );
      },
    );
  }
}