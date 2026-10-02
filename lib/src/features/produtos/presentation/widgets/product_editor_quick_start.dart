import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/models/produto.dart';
import '../../../../shared/presentation/widgets/app_medium_controls.dart';
import '../services/product_unit_catalog_service.dart';
import 'product_editor_field_builder.dart';
import 'product_thumbnail.dart';

class ProductEditorQuickStart extends StatelessWidget {
  static const String _addOptionValue = '__add_new_standard_unit__';

  const ProductEditorQuickStart({
    super.key,
    required this.readOnly,
    required this.tenantId,
    required this.unitCatalogService,
    required this.thumbnailProduto,
    required this.imageTileSize,
    required this.uploadingImage,
    required this.currentImageStoragePath,
    required this.currentImagePreviewBytes,
    required this.onOpenMediaLibrary,
    required this.descricaoController,
    required this.codigoFabricanteController,
    required this.unidadeController,
    required this.multiploVendaController,
    required this.labelStyle,
    required this.inputTextStyle,
    required this.fieldHeight,
    required this.onStandardUnitChanged,
    required this.categoryField,
    required this.subcategoryField,
    required this.editorFieldBuilder,
  });

  final bool readOnly;
  final String tenantId;
  final ProductUnitCatalogService unitCatalogService;
  final Produto thumbnailProduto;
  final double imageTileSize;
  final bool uploadingImage;
  final String? currentImageStoragePath;
  final Uint8List? currentImagePreviewBytes;
  final VoidCallback? onOpenMediaLibrary;
  final TextEditingController descricaoController;
  final TextEditingController codigoFabricanteController;
  final TextEditingController unidadeController;
  final TextEditingController multiploVendaController;
  final TextStyle labelStyle;
  final TextStyle inputTextStyle;
  final double fieldHeight;
  final ValueChanged<String> onStandardUnitChanged;
  final Widget categoryField;
  final Widget subcategoryField;
  final ProductEditorFieldBuilder editorFieldBuilder;

  List<String> _extractCatalogNames(List<ProductUnitCatalogEntry> entries) {
    return entries
        .map((entry) => entry.name.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  String _buildCreateErrorMessage(Object error) {
    if (error is StateError) {
      final message = error.message.toString().trim();
      if (message.isNotEmpty) {
        return message;
      }
    }
    return 'Nao foi possivel cadastrar a unidade.';
  }

  Future<String?> _promptCreateStandardUnit(BuildContext context) async {
    final nameController = TextEditingController();
    String? validationMessage;
    var saving = false;

    final createdName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Cadastrar unidade padrao'),
              content: SizedBox(
                width: 320,
                child: TextField(
                  controller: nameController,
                  autofocus: true,
                  enabled: !saving,
                  decoration: InputDecoration(
                    labelText: 'Nome da unidade',
                    errorText: validationMessage,
                  ),
                  onSubmitted: (_) async {
                    if (saving) {
                      return;
                    }
                    final value = nameController.text.trim();
                    if (value.isEmpty) {
                      setDialogState(() {
                        validationMessage = 'Informe o nome da unidade.';
                      });
                      return;
                    }

                    setDialogState(() {
                      saving = true;
                      validationMessage = null;
                    });

                    try {
                      await unitCatalogService.createUnit(
                        tenantId: tenantId,
                        type: ProductUnitCatalogType.standard,
                        name: value,
                      );
                      if (!dialogContext.mounted) {
                        return;
                      }
                      Navigator.of(dialogContext).pop(value);
                    } catch (error) {
                      if (!dialogContext.mounted) {
                        return;
                      }
                      setDialogState(() {
                        saving = false;
                        validationMessage = _buildCreateErrorMessage(error);
                      });
                    }
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final value = nameController.text.trim();
                          if (value.isEmpty) {
                            setDialogState(() {
                              validationMessage = 'Informe o nome da unidade.';
                            });
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                            validationMessage = null;
                          });

                          try {
                            await unitCatalogService.createUnit(
                              tenantId: tenantId,
                              type: ProductUnitCatalogType.standard,
                              name: value,
                            );
                            if (!dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop(value);
                          } catch (error) {
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {
                              saving = false;
                              validationMessage = _buildCreateErrorMessage(
                                error,
                              );
                            });
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    return createdName;
  }

  Widget _buildStandardUnitField() {
    return StreamBuilder<List<ProductUnitCatalogEntry>>(
      stream: unitCatalogService.watchUnits(
        tenantId: tenantId,
        type: ProductUnitCatalogType.standard,
      ),
      initialData: const <ProductUnitCatalogEntry>[],
      builder: (context, snapshot) {
        final hasError = snapshot.hasError;
        final canCreateInline = !readOnly && !hasError;
        final names = _extractCatalogNames(
          snapshot.data ?? const <ProductUnitCatalogEntry>[],
        );
        final currentValue = unidadeController.text.trim();
        final selectedValue = names.contains(currentValue)
            ? currentValue
            : null;

        if (!hasError && names.isNotEmpty && selectedValue == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onStandardUnitChanged(names.first);
          });
        }

        final hintWidget = hasError
            ? const Text('Sem acesso ao catalogo')
            : (names.isEmpty
                  ? const Text('Nenhuma cadastrada')
                  : const Text('Selecione'));

        final items = <DropdownMenuItem<String>>[
          ...names.map(
            (name) => DropdownMenuItem<String>(
              value: name,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(name, textAlign: TextAlign.left),
              ),
            ),
          ),
          if (canCreateInline)
            const DropdownMenuItem<String>(
              value: _addOptionValue,
              child: Row(
                children: [
                  Icon(Icons.add, size: 16),
                  SizedBox(width: 8),
                  Text('Cadastrar nova unidade'),
                ],
              ),
            ),
        ];

        return AppMediumLabeledControl(
          label: 'Unidade padrão',
          labelStyle: labelStyle,
          height: fieldHeight,
          child: AppMediumDropdown<String>(
            value: selectedValue,
            style: inputTextStyle,
            alignment: AlignmentDirectional.centerStart,
            icon: const Icon(Icons.expand_more, size: 16),
            hint: hintWidget,
            items: items,
            onChanged: readOnly || hasError
                ? null
                : (value) async {
                    if (value == null) {
                      return;
                    }

                    if (value == _addOptionValue) {
                      final createdName = await _promptCreateStandardUnit(
                        context,
                      );
                      if (createdName != null &&
                          createdName.trim().isNotEmpty) {
                        onStandardUnitChanged(createdName.trim());
                      }
                      return;
                    }

                    onStandardUnitChanged(value);
                  },
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductThumbnail(
              produto: thumbnailProduto,
              size: imageTileSize,
              uploading: uploadingImage,
              storagePath: currentImageStoragePath,
              previewBytes: currentImagePreviewBytes,
              onTap: onOpenMediaLibrary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: editorFieldBuilder(
                descricaoController,
                'Nome *',
                readOnly: readOnly,
                textAlign: TextAlign.left,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 160,
              child: editorFieldBuilder(
                codigoFabricanteController,
                'Codigo',
                readOnly: readOnly,
                textAlign: TextAlign.left,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.start,
          runAlignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(width: 180, child: _buildStandardUnitField()),
            SizedBox(
              width: 180,
              child: editorFieldBuilder(
                multiploVendaController,
                'Venda em multiplos de',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.left,
              ),
            ),
            SizedBox(width: 180, child: categoryField),
            SizedBox(width: 180, child: subcategoryField),
          ],
        ),
      ],
    );
  }
}
