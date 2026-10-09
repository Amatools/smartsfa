part of 'web_portal_page.dart';

class _CommercialAdjustmentsSection extends StatefulWidget {
  const _CommercialAdjustmentsSection({
    required this.activeTenant,
    required this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_CommercialAdjustmentsSection> createState() =>
      _CommercialAdjustmentsSectionState();
}

class _CommercialAdjustmentsSectionState
    extends State<_CommercialAdjustmentsSection> {
  final WorkspaceProfileService _service = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );
  final List<_CommercialAdjustmentDraftRow> _rows = [];
  String _loadedScope = '';
  bool _initialized = false;
  bool _dirty = false;
  bool _saving = false;

  static const List<String> _adjustmentTypes = <String>['discount', 'addition'];
  static const List<String> _valueTypes = <String>['percent', 'fixed'];
  static const List<String> _scopes = <String>[
    'geral',
    'categoria',
    'marca',
    'produto',
  ];

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String label,
    IconData? icon,
    String? prefixText,
  }) {
    final colors = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      prefixText: prefixText,
      isDense: true,
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.35),
      prefixIcon: icon == null ? null : Icon(icon, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: border(colors.outlineVariant.withValues(alpha: 0.45)),
      focusedBorder: border(colors.primary.withValues(alpha: 0.75), width: 1.4),
      errorBorder: border(colors.error.withValues(alpha: 0.75)),
      focusedErrorBorder: border(colors.error, width: 1.4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );
    final representedName = (widget.activeRepresentedCompanyName ?? '').trim();
    final scopeLabel = representedName.isEmpty
        ? widget.activeTenant.tenantName
        : representedName;

    return StreamBuilder<List<CommercialAdjustmentRule>>(
      stream: _service.watchCommercialAdjustmentRules(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: widget.selectedRepresentedCompanyId,
      ),
      builder: (context, ruleSnapshot) {
        final incoming = ruleSnapshot.data ?? const <CommercialAdjustmentRule>[];
        final scopeKey = _scopeKey();
        if (!_initialized || _loadedScope != scopeKey || !_dirty) {
          _resetRowsFromIncoming(incoming);
          _initialized = true;
          _loadedScope = scopeKey;
          _dirty = false;
        }

        return StreamBuilder<List<String>>(
          stream: _service.watchRepresentedProductCategories(
            tenantId: widget.activeTenant.tenantId,
            representedCompanyId: widget.selectedRepresentedCompanyId,
          ),
          builder: (context, categorySnapshot) {
            final categoryOptions =
                categorySnapshot.data ?? const <String>[];

            return StreamBuilder<CommercialAdjustmentTargetCatalog>(
              stream: _service.watchCommercialAdjustmentTargetCatalog(
                tenantId: widget.activeTenant.tenantId,
                representedCompanyId: widget.selectedRepresentedCompanyId,
              ),
              builder: (context, catalogSnapshot) {
                final catalog =
                    catalogSnapshot.data ??
                    const CommercialAdjustmentTargetCatalog();

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Acrescimos e descontos',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Construtor inicial de regras comerciais para $scopeLabel.',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Prioridade: regras no topo possuem maior prioridade na aplicacao.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed:
                                canEditSettings && !_saving ? _addRule : null,
                            icon: const Icon(Icons.add),
                            label: const Text('Adicionar regra'),
                            style: OutlinedButton.styleFrom(
                              shape: const StadiumBorder(),
                              side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ),
                        if (!canEditSettings) ...[
                          const SizedBox(height: 10),
                          _ownerOnlyReadOnlyNotice(
                            context,
                            message:
                                'Regras em modo somente leitura para este perfil. Apenas o owner pode alterar.',
                          ),
                        ],
                        const SizedBox(height: 10),
                        if (_rows.isEmpty)
                          const Text('Nenhuma regra cadastrada.')
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            proxyDecorator: (child, index, animation) {
                              // Keep drag feedback lightweight to reduce jank in web debug.
                              return child;
                            },
                            itemCount: _rows.length,
                            onReorderItem: (oldIndex, newIndex) {
                              if (!canEditSettings || _saving) {
                                return;
                              }
                              _reorderRules(
                                oldIndex,
                                newIndex,
                                alreadyAdjusted: true,
                              );
                            },
                            itemBuilder: (context, index) {
                              final row = _rows[index];
                              return Padding(
                                key: ValueKey(row.rowId),
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _buildRuleRow(
                                  index,
                                  canEditSettings,
                                  priority: index + 1,
                                  categoryOptions: categoryOptions,
                                  brandOptions: catalog.brands,
                                  productOptions: catalog.products,
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: canEditSettings && !_saving && _dirty
                                ? _save
                                : null,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              _saving ? 'Salvando...' : 'Salvar regras',
                            ),
                            style: FilledButton.styleFrom(
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRuleRow(
    int index,
    bool canEditSettings, {
    required int priority,
    required List<String> categoryOptions,
    required List<String> brandOptions,
    required List<String> productOptions,
  }) {
    final row = _rows[index];
    final scopeOptions = _targetsForScope(
      row.scope,
      categoryOptions: categoryOptions,
      brandOptions: brandOptions,
      productOptions: productOptions,
    );
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: colors.surfaceContainerHighest.withValues(alpha: 0.16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Prioridade $priority',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Spacer(),
              Tooltip(
                message: 'Mover para cima',
                child: IconButton(
                  onPressed: canEditSettings && !_saving && index > 0
                      ? () => _moveRule(index, up: true)
                      : null,
                  icon: const Icon(Icons.expand_less),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Tooltip(
                message: 'Mover para baixo',
                child: IconButton(
                  onPressed:
                      canEditSettings &&
                          !_saving &&
                          index < _rows.length - 1
                      ? () => _moveRule(index, up: false)
                      : null,
                  icon: const Icon(Icons.expand_more),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                enabled: canEditSettings && !_saving,
                child: IconButton.outlined(
                  tooltip: 'Arrastar para reordenar prioridade',
                  onPressed: canEditSettings && !_saving ? () {} : null,
                  icon: const Icon(Icons.drag_indicator),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.nameController,
                  enabled: canEditSettings && !_saving,
                  decoration: _fieldDecoration(
                    label: 'Nome da regra',
                    icon: Icons.rule_folder_outlined,
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: canEditSettings && !_saving
                    ? () => _removeRule(index)
                    : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: row.adjustmentType,
                  decoration: _fieldDecoration(
                    label: 'Tipo',
                    icon: Icons.swap_vert,
                  ),
                  items: _adjustmentTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(
                            type == 'discount' ? 'Desconto' : 'Acrescimo',
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: !canEditSettings || _saving
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            row.adjustmentType = value;
                            _dirty = true;
                          });
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: row.valueType,
                  decoration: _fieldDecoration(
                    label: 'Aplicar como',
                    icon: Icons.calculate_outlined,
                  ),
                  items: _valueTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(
                            type == 'percent' ? 'Percentual' : 'Valor fixo',
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: !canEditSettings || _saving
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            row.valueType = value;
                            _dirty = true;
                          });
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.valueController,
                  enabled: canEditSettings && !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDecoration(
                    label: row.valueType == 'percent'
                        ? 'Valor (%)'
                        : 'Valor (R\$)',
                    icon: Icons.request_quote_outlined,
                    prefixText: row.valueType == 'percent' ? null : 'R\$ ',
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: row.scope,
                  decoration: _fieldDecoration(
                    label: 'Escopo',
                    icon: Icons.filter_alt_outlined,
                  ),
                  items: _scopes
                      .map(
                        (scope) => DropdownMenuItem(
                          value: scope,
                          child: Text(
                            scope[0].toUpperCase() + scope.substring(1),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: !canEditSettings || _saving
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            row.scope = value;
                            if (value == 'geral') {
                              row.scopeTargets.clear();
                            } else {
                              row.scopeTargets = <String>{};
                            }
                            _dirty = true;
                          });
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _buildScopeTargetSelector(
                  row: row,
                  canEditSettings: canEditSettings,
                  availableOptions: scopeOptions,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _markDirty() {
    if (_dirty) {
      return;
    }
    setState(() {
      _dirty = true;
    });
  }

  Widget _buildScopeTargetSelector({
    required _CommercialAdjustmentDraftRow row,
    required bool canEditSettings,
    required List<String> availableOptions,
  }) {
    final colors = Theme.of(context).colorScheme;
    if (row.scope == 'geral') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: colors.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Text(
          'Escopo geral nao usa alvo especifico.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final selectedTargets = _normalizeScopeTargets(row.scopeTargets.toList());
    final selectableOptions = _normalizeScopeTargets(
      <String>[...availableOptions, ...selectedTargets],
    );
    final canInteract = canEditSettings && !_saving;
    final targetLabel = _scopeTargetLabel(row.scope);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colors.surfaceContainerHighest.withValues(alpha: 0.25),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Alvos de $targetLabel',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              if (selectedTargets.isNotEmpty)
                TextButton(
                  onPressed: canInteract
                      ? () {
                          setState(() {
                            row.scopeTargets.clear();
                            _dirty = true;
                          });
                        }
                      : null,
                  child: const Text('Limpar'),
                ),
            ],
          ),
          if (selectedTargets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Text(
                'Nenhum alvo selecionado.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final target in selectedTargets)
                  InputChip(
                    label: Text(target),
                    selected: true,
                    showCheckmark: false,
                    onDeleted: canInteract
                        ? () {
                            setState(() {
                              row.scopeTargets.removeWhere(
                                (item) => item.toLowerCase() == target.toLowerCase(),
                              );
                              _dirty = true;
                            });
                          }
                        : null,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: canInteract
                  ? () async {
                      final pickedTargets = await _openScopeTargetsPicker(
                        scope: row.scope,
                        options: selectableOptions,
                        selectedTargets: row.scopeTargets,
                      );
                      if (pickedTargets == null) {
                        return;
                      }
                      setState(() {
                        row.scopeTargets = pickedTargets;
                        _dirty = true;
                      });
                    }
                  : null,
              icon: const Icon(Icons.playlist_add_check_circle_outlined),
              label: Text('Selecionar $targetLabel'),
            ),
          ),
          if (selectableOptions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Nao ha opcoes de $targetLabel cadastradas ainda.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<Set<String>?> _openScopeTargetsPicker({
    required String scope,
    required List<String> options,
    required Set<String> selectedTargets,
  }) async {
    final mergedOptions = _normalizeScopeTargets(
      <String>[...options, ...selectedTargets],
    );
    final searchController = TextEditingController();
    var selected = <String>{...selectedTargets};
    var query = '';

    try {
      return await showDialog<Set<String>>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final normalizedQuery = query.trim().toLowerCase();
              final visibleOptions = mergedOptions.where((item) {
                if (normalizedQuery.isEmpty) {
                  return true;
                }
                return item.toLowerCase().contains(normalizedQuery);
              }).toList(growable: false);

              return AlertDialog(
                title: Text('Selecionar ${_scopeTargetLabel(scope)}'),
                content: SizedBox(
                  width: 460,
                  height: 420,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          labelText: 'Filtrar opcoes',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            query = value;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: visibleOptions.isEmpty
                            ? const Center(
                                child: Text('Nenhuma opcao encontrada.'),
                              )
                            : ListView.builder(
                                itemCount: visibleOptions.length,
                                itemBuilder: (context, index) {
                                  final option = visibleOptions[index];
                                  final isChecked = selected.any(
                                    (item) =>
                                        item.toLowerCase() ==
                                        option.toLowerCase(),
                                  );
                                  return CheckboxListTile(
                                    value: isChecked,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(option),
                                    onChanged: (checked) {
                                      setDialogState(() {
                                        if (checked == true) {
                                          selected.add(option);
                                        } else {
                                          selected.removeWhere(
                                            (item) =>
                                                item.toLowerCase() ==
                                                option.toLowerCase(),
                                          );
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      setDialogState(() {
                        selected = <String>{};
                      });
                    },
                    child: const Text('Limpar selecao'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(
                        _normalizeScopeTargets(selected.toList()).toSet(),
                      );
                    },
                    child: const Text('Aplicar'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      searchController.dispose();
    }
  }

  List<String> _targetsForScope(
    String scope, {
    required List<String> categoryOptions,
    required List<String> brandOptions,
    required List<String> productOptions,
  }) {
    if (scope == 'categoria') {
      return _normalizeScopeTargets(categoryOptions);
    }
    if (scope == 'marca') {
      return _normalizeScopeTargets(brandOptions);
    }
    if (scope == 'produto') {
      return _normalizeScopeTargets(productOptions);
    }
    return const <String>[];
  }

  List<String> _parseScopeTargets(String raw) {
    return _normalizeScopeTargets(raw.split(RegExp(r'[,;|\n]+')));
  }

  List<String> _normalizeScopeTargets(Iterable<String> values) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final clean = value.trim();
      if (clean.isEmpty) {
        continue;
      }
      final key = clean.toLowerCase();
      if (!seen.add(key)) {
        continue;
      }
      normalized.add(clean);
    }
    normalized.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return normalized;
  }

  String _joinScopeTargets(Iterable<String> targets) {
    return _normalizeScopeTargets(targets).join(' | ');
  }

  String _scopeTargetLabel(String scope) {
    if (scope == 'marca') {
      return 'marcas';
    }
    if (scope == 'categoria') {
      return 'categorias';
    }
    if (scope == 'produto') {
      return 'produtos';
    }
    return 'alvos';
  }

  void _addRule() {
    setState(() {
      _rows.add(_CommercialAdjustmentDraftRow());
      _dirty = true;
    });
  }

  void _removeRule(int index) {
    setState(() {
      _rows.removeAt(index).dispose();
      _dirty = true;
    });
  }

  void _reorderRules(
    int oldIndex,
    int newIndex, {
    bool alreadyAdjusted = false,
  }) {
    if (!alreadyAdjusted && oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex == newIndex) {
      return;
    }

    setState(() {
      final moved = _rows.removeAt(oldIndex);
      _rows.insert(newIndex, moved);
      _dirty = true;
    });
  }

  void _moveRule(int index, {required bool up}) {
    final targetIndex = up ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= _rows.length) {
      return;
    }

    setState(() {
      final moved = _rows.removeAt(index);
      _rows.insert(targetIndex, moved);
      _dirty = true;
    });
  }

  void _resetRowsFromIncoming(List<CommercialAdjustmentRule> incoming) {
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(
        incoming.map(
          (rule) => _CommercialAdjustmentDraftRow(
            name: rule.name,
            adjustmentType: rule.adjustmentType,
            valueType: rule.valueType,
            value: _formatValue(rule.value),
            scope: rule.scope,
            scopeTargets: rule.scopeTargets.isEmpty
                ? _parseScopeTargets(rule.scopeTarget)
                : _normalizeScopeTargets(rule.scopeTargets),
          ),
        ),
      );
  }

  String _formatValue(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _parseValue(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    final withDot = normalized.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(withDot) ??
        double.tryParse(normalized.replaceAll(',', '.')) ??
        0;
  }

  Future<void> _save() async {
    final rules = _rows
        .map(
          (row) {
            final normalizedTargets = row.scope == 'geral'
                ? const <String>[]
                : _normalizeScopeTargets(row.scopeTargets);
            return CommercialAdjustmentRule(
              name: row.nameController.text.trim(),
              adjustmentType: row.adjustmentType,
              valueType: row.valueType,
              value: _parseValue(row.valueController.text),
              scope: row.scope,
              scopeTarget: _joinScopeTargets(normalizedTargets),
              scopeTargets: normalizedTargets,
            );
          },
        )
        .where((rule) => rule.name.isNotEmpty)
        .toList(growable: false);

    setState(() {
      _saving = true;
    });

    try {
      await _service.updateCommercialAdjustmentRules(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: widget.selectedRepresentedCompanyId,
        rules: rules,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Regras de acrescimos e descontos salvas.'),
        ),
      );
      setState(() {
        _dirty = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao salvar regras: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _scopeKey() {
    final raw = (widget.selectedRepresentedCompanyId ?? '').trim();
    return raw.isEmpty ? 'tenant_default' : raw;
  }
}

class _CommercialAdjustmentDraftRow {
  static int _idSeed = 0;

  _CommercialAdjustmentDraftRow({
    String? rowId,
    String name = '',
    this.adjustmentType = 'discount',
    this.valueType = 'percent',
    String value = '',
    this.scope = 'geral',
    List<String> scopeTargets = const <String>[],
  }) : rowId =
           rowId ??
           'rule_${DateTime.now().microsecondsSinceEpoch}_${_idSeed++}',
       nameController = TextEditingController(text: name),
       valueController = TextEditingController(text: value),
       scopeTargets = <String>{...scopeTargets};

  final String rowId;
  final TextEditingController nameController;
  final TextEditingController valueController;
  String adjustmentType;
  String valueType;
  String scope;
  Set<String> scopeTargets;

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}
