import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/presentation/widgets/app_medium_controls.dart';
import '../services/product_unit_catalog_service.dart';
import 'product_editor_field_builder.dart';

class ProductVariationsTabSection extends StatefulWidget {
  const ProductVariationsTabSection({
    super.key,
    required this.readOnly,
    required this.tenantId,
    required this.unitCatalogService,
    required this.isEnterprise,
    required this.bitolaController,
    required this.erpProductIdController,
    required this.erpSyncIdController,
    required this.bitolaUnit,
    required this.labelStyle,
    required this.inputTextStyle,
    required this.fieldHeight,
    required this.onBitolaUnitChanged,
    required this.editorFieldBuilder,
  });

  final bool readOnly;
  final String tenantId;
  final ProductUnitCatalogService unitCatalogService;
  final bool isEnterprise;
  final TextEditingController bitolaController;
  final TextEditingController erpProductIdController;
  final TextEditingController erpSyncIdController;
  final String bitolaUnit;
  final TextStyle labelStyle;
  final TextStyle inputTextStyle;
  final double fieldHeight;
  final ValueChanged<String> onBitolaUnitChanged;
  final ProductEditorFieldBuilder editorFieldBuilder;

  @override
  State<ProductVariationsTabSection> createState() =>
      _ProductVariationsTabSectionState();
}

class _ProductVariationsTabSectionState
    extends State<ProductVariationsTabSection> {
  static const double _fieldGap = 10;
  static const double _maxMeasureFieldWidth = 200;
  static const double _measureBadgeWidth = 50;
  static const String _addOptionValue = '__add_new_measure_unit__';
  bool _selectionSyncQueued = false;

  List<String> _extractCatalogNames(List<ProductUnitCatalogEntry> entries) {
    return entries
        .map((entry) => entry.name.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  ProductUnitCatalogEntry? _findEntryByName({
    required List<ProductUnitCatalogEntry> entries,
    required String? name,
  }) {
    if (name == null || name.trim().isEmpty) {
      return null;
    }

    final normalized = name.trim().toLowerCase();
    for (final entry in entries) {
      if (entry.name.trim().toLowerCase() == normalized) {
        return entry;
      }
    }
    return null;
  }

  String _resolveMeasureShortCode(ProductUnitCatalogEntry? entry) {
    final value = (entry?.shortCode ?? '').trim().toLowerCase();
    if (value.isNotEmpty) {
      return value;
    }
    return '--';
  }

  String _formatMeasureLabel(ProductUnitCatalogEntry entry) {
    final shortCode = entry.shortCode.trim();
    if (shortCode.isEmpty) {
      return entry.name;
    }
    return '${entry.name} ($shortCode)';
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

  Future<String?> _promptCreateMeasureUnit(BuildContext context) async {
    final nameController = TextEditingController();
    final shortCodeController = TextEditingController();
    String? validationMessage;
    var saving = false;

    final createdName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Cadastrar unidade de medida'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      enabled: !saving,
                      decoration: InputDecoration(
                        labelText: 'Nome da unidade',
                        errorText: validationMessage,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: shortCodeController,
                      enabled: !saving,
                      maxLength: 4,
                      textCapitalization: TextCapitalization.none,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Sigla (ate 4 letras)',
                        counterText: '',
                      ),
                      onSubmitted: (_) async {
                        if (saving) {
                          return;
                        }
                        final value = nameController.text.trim();
                        final shortCode = shortCodeController.text.trim();
                        if (value.isEmpty) {
                          setDialogState(() {
                            validationMessage = 'Informe o nome da unidade.';
                          });
                          return;
                        }
                        if (shortCode.isEmpty) {
                          setDialogState(() {
                            validationMessage =
                                'Informe a sigla com ate 4 letras.';
                          });
                          return;
                        }

                        setDialogState(() {
                          saving = true;
                          validationMessage = null;
                        });

                        try {
                          await widget.unitCatalogService.createUnit(
                            tenantId: widget.tenantId,
                            type: ProductUnitCatalogType.measure,
                            name: value,
                            shortCode: shortCode,
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
                  ],
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
                          final shortCode = shortCodeController.text.trim();
                          if (value.isEmpty) {
                            setDialogState(() {
                              validationMessage = 'Informe o nome da unidade.';
                            });
                            return;
                          }
                          if (shortCode.isEmpty) {
                            setDialogState(() {
                              validationMessage =
                                  'Informe a sigla com ate 4 letras.';
                            });
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                            validationMessage = null;
                          });

                          try {
                            await widget.unitCatalogService.createUnit(
                              tenantId: widget.tenantId,
                              type: ProductUnitCatalogType.measure,
                              name: value,
                              shortCode: shortCode,
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
    shortCodeController.dispose();
    return createdName;
  }

  Widget _buildGroupedMeasureValueField({
    required double width,
    required String measureShortCode,
  }) {
    final outlineColor = Theme.of(context).colorScheme.outline
        .withValues(alpha: 0.45);
    final badgeColor = Theme.of(context).colorScheme.surfaceContainerHighest
        .withValues(alpha: 0.35);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Medida', style: widget.labelStyle),
          const SizedBox(height: 4),
          SizedBox(
            height: widget.fieldHeight,
            child: Row(
              children: [
                SizedBox(
                  width: _measureBadgeWidth,
                  height: widget.fieldHeight,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(6),
                        bottomLeft: Radius.circular(6),
                      ),
                      border: Border.all(color: outlineColor),
                      color: badgeColor,
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
                    child: Text(measureShortCode, style: widget.inputTextStyle),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: widget.fieldHeight,
                    child: AppMediumTextField(
                      controller: widget.bitolaController,
                      readOnly: widget.readOnly,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: widget.inputTextStyle,
                      textAlign: TextAlign.left,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(6),
                        bottomRight: Radius.circular(6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _syncSelectedMeasure(List<String> names) {
    if (_selectionSyncQueued || names.isEmpty) {
      return;
    }

    final current = widget.bitolaUnit.trim();
    if (names.contains(current)) {
      return;
    }

    _selectionSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionSyncQueued = false;
      if (!mounted) {
        return;
      }
      widget.onBitolaUnitChanged(names.first);
    });
  }

  Widget _buildMeasureHeaderFields() {
    return StreamBuilder<List<ProductUnitCatalogEntry>>(
      stream: widget.unitCatalogService.watchUnits(
        tenantId: widget.tenantId,
        type: ProductUnitCatalogType.measure,
      ),
      initialData: const <ProductUnitCatalogEntry>[],
      builder: (context, snapshot) {
        final hasError = snapshot.hasError;
        final canCreateInline = !widget.readOnly && !hasError;
        final entries = snapshot.data ?? const <ProductUnitCatalogEntry>[];
        final names = _extractCatalogNames(entries);
        if (!hasError) {
          _syncSelectedMeasure(names);
        }
        final selectedValue = names.contains(widget.bitolaUnit)
            ? widget.bitolaUnit
            : null;
        final selectedEntry = _findEntryByName(
          entries: entries,
          name: selectedValue ?? widget.bitolaUnit,
        );
        final measureShortCode = _resolveMeasureShortCode(selectedEntry);

        final items = <DropdownMenuItem<String>>[
          ...entries.map(
            (entry) => DropdownMenuItem<String>(
              value: entry.name,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _formatMeasureLabel(entry),
                  textAlign: TextAlign.left,
                ),
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

        return LayoutBuilder(
          builder: (context, constraints) {
            final compactFieldWidth =
                constraints.maxWidth < _maxMeasureFieldWidth
                ? constraints.maxWidth
                : _maxMeasureFieldWidth;

            return Wrap(
              spacing: _fieldGap,
              runSpacing: _fieldGap,
              children: [
                SizedBox(
                  width: compactFieldWidth,
                  child: AppMediumLabeledControl(
                    label: 'Unidade de medida',
                    labelStyle: widget.labelStyle,
                    height: widget.fieldHeight,
                    child: AppMediumDropdown<String>(
                      value: selectedValue,
                      style: widget.inputTextStyle,
                      alignment: AlignmentDirectional.centerStart,
                      icon: const Icon(Icons.expand_more, size: 16),
                      hint: hasError
                          ? const Text('Sem acesso ao catalogo')
                          : (names.isEmpty
                                ? const Text('Nenhuma cadastrada')
                                : const Text('Selecione')),
                      items: items,
                      onChanged: widget.readOnly || hasError
                          ? null
                          : (value) async {
                              if (value == null) {
                                return;
                              }

                              if (value == _addOptionValue) {
                                final createdName =
                                    await _promptCreateMeasureUnit(context);
                                if (createdName != null &&
                                    createdName.trim().isNotEmpty) {
                                  widget.onBitolaUnitChanged(
                                    createdName.trim(),
                                  );
                                }
                                return;
                              }

                              widget.onBitolaUnitChanged(value);
                            },
                    ),
                  ),
                ),
                _buildGroupedMeasureValueField(
                  width: compactFieldWidth,
                  measureShortCode: measureShortCode,
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildMeasureHeaderFields(),
        if (widget.isEnterprise) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: widget.editorFieldBuilder(
                  widget.erpProductIdController,
                  'ID do produto no ERP',
                  readOnly: widget.readOnly,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: widget.editorFieldBuilder(
                  widget.erpSyncIdController,
                  'ID de sincronizacao ERP',
                  readOnly: widget.readOnly,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
