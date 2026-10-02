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
      builder: (context, snapshot) {
        final incoming = snapshot.data ?? const <CommercialAdjustmentRule>[];
        final scopeKey = _scopeKey();
        if (!_initialized || _loadedScope != scopeKey || !_dirty) {
          _resetRowsFromIncoming(incoming);
          _initialized = true;
          _loadedScope = scopeKey;
          _dirty = false;
        }

        return Card(
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
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: canEditSettings && !_saving ? _addRule : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar regra'),
                  ),
                ),
                if (!canEditSettings) ...[
                  const SizedBox(height: 10),
                  _ownerOnlyReadOnlyNotice(
                    context,
                    message: 'Regras em modo somente leitura para este perfil. Apenas o owner pode alterar.',
                  ),
                ],
                const SizedBox(height: 10),
                if (_rows.isEmpty)
                  const Text('Nenhuma regra cadastrada.')
                else
                  Column(
                    children: [
                      for (var index = 0; index < _rows.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildRuleRow(index, canEditSettings),
                        ),
                    ],
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Salvando...' : 'Salvar regras'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRuleRow(int index, bool canEditSettings) {
    final row = _rows[index];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.nameController,
                  enabled: canEditSettings && !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Nome da regra',
                    isDense: true,
                    border: OutlineInputBorder(),
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
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    isDense: true,
                    border: OutlineInputBorder(),
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
                  decoration: const InputDecoration(
                    labelText: 'Aplicar como',
                    isDense: true,
                    border: OutlineInputBorder(),
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
                  decoration: InputDecoration(
                    labelText: row.valueType == 'percent'
                        ? 'Valor (%)'
                        : 'Valor (R\$)',
                    isDense: true,
                    border: const OutlineInputBorder(),
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
                  decoration: const InputDecoration(
                    labelText: 'Escopo',
                    isDense: true,
                    border: OutlineInputBorder(),
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
                            _dirty = true;
                          });
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: row.scopeTargetController,
                  enabled: canEditSettings && !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Alvo do escopo (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _markDirty(),
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
            scopeTarget: rule.scopeTarget,
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
          (row) => CommercialAdjustmentRule(
            name: row.nameController.text.trim(),
            adjustmentType: row.adjustmentType,
            valueType: row.valueType,
            value: _parseValue(row.valueController.text),
            scope: row.scope,
            scopeTarget: row.scopeTargetController.text.trim(),
          ),
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
  _CommercialAdjustmentDraftRow({
    String name = '',
    this.adjustmentType = 'discount',
    this.valueType = 'percent',
    String value = '',
    this.scope = 'geral',
    String scopeTarget = '',
  }) : nameController = TextEditingController(text: name),
       valueController = TextEditingController(text: value),
       scopeTargetController = TextEditingController(text: scopeTarget);

  final TextEditingController nameController;
  final TextEditingController valueController;
  final TextEditingController scopeTargetController;
  String adjustmentType;
  String valueType;
  String scope;

  void dispose() {
    nameController.dispose();
    valueController.dispose();
    scopeTargetController.dispose();
  }
}
