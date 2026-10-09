part of 'web_portal_page.dart';

class _OrderDiscountPoliciesSection extends StatefulWidget {
  const _OrderDiscountPoliciesSection({
    required this.activeTenant,
    required this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_OrderDiscountPoliciesSection> createState() =>
      _OrderDiscountPoliciesSectionState();
}

class _OrderDiscountPoliciesSectionState
    extends State<_OrderDiscountPoliciesSection> {
  final WorkspaceProfileService _service = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );

  final List<_OrderDiscountFieldDraftRow> _rows =
      <_OrderDiscountFieldDraftRow>[];
  bool _initialized = false;
  bool _dirty = false;
  bool _saving = false;
  String _loadedScope = '';

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
    String? suffixText,
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
      suffixText: suffixText,
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

    return StreamBuilder<OrderDiscountPolicy>(
      stream: _service.watchOrderDiscountPolicy(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: widget.selectedRepresentedCompanyId,
      ),
      builder: (context, snapshot) {
        final incoming = snapshot.data ?? const OrderDiscountPolicy();
        final scopeKey = _scopeKey();
        if (!_initialized || _loadedScope != scopeKey || !_dirty) {
          _resetRowsFromIncoming(incoming);
          _initialized = true;
          _loadedScope = scopeKey;
          _dirty = false;
        }

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
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Descontos pontuais no pedido',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Defina para $scopeLabel quantos campos de desconto podem ser usados e os intervalos permitidos de cada campo.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Chip(
                      avatar: const Icon(Icons.tune, size: 16),
                      label: Text('${_rows.length} campo(s)'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 260,
                        child: Text(
                          'Quantidade máxima de campos',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<int>(
                          initialValue: _rows.length,
                          decoration: _fieldDecoration(
                            label: 'Qtd. de campos',
                            icon: Icons.format_list_numbered,
                          ),
                          items: List<DropdownMenuItem<int>>.generate(
                            11,
                            (index) => DropdownMenuItem<int>(
                              value: index,
                              child: Text('$index'),
                            ),
                          ),
                          onChanged: !canEditSettings || _saving
                              ? null
                              : (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  _setFieldCount(value);
                                },
                        ),
                      ),
                    ],
                  ),
                ),
                if (!canEditSettings) ...[
                  const SizedBox(height: 10),
                  _ownerOnlyReadOnlyNotice(
                    context,
                    message:
                        'Política em modo somente leitura para este perfil. Apenas o owner pode alterar.',
                  ),
                ],
                const SizedBox(height: 12),
                if (_rows.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text('Nenhum campo de desconto configurado.'),
                  )
                else
                  Column(
                    children: [
                      for (var index = 0; index < _rows.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildFieldRow(index, canEditSettings),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed:
                        canEditSettings && !_saving && _dirty ? _save : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Salvando...' : 'Salvar política'),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFieldRow(int index, bool canEditSettings) {
    final row = _rows[index];
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
              Chip(
                avatar: const Icon(Icons.percent, size: 16),
                label: Text('Campo ${index + 1}'),
              ),
              const Spacer(),
              IconButton.outlined(
                tooltip: 'Remover campo',
                onPressed: canEditSettings && !_saving
                    ? () => _removeField(index)
                    : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              if (compact) {
                return Column(
                  children: [
                    TextField(
                      controller: row.labelController,
                      enabled: canEditSettings && !_saving,
                      decoration: _fieldDecoration(
                        label: 'Rótulo',
                        icon: Icons.label_outline,
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: row.minController,
                      enabled: canEditSettings && !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _fieldDecoration(
                        label: 'Mínimo',
                        icon: Icons.arrow_downward,
                        suffixText: '%',
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: row.maxController,
                      enabled: canEditSettings && !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _fieldDecoration(
                        label: 'Máximo',
                        icon: Icons.arrow_upward,
                        suffixText: '%',
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: row.labelController,
                      enabled: canEditSettings && !_saving,
                      decoration: _fieldDecoration(
                        label: 'Rótulo',
                        icon: Icons.label_outline,
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: row.minController,
                      enabled: canEditSettings && !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _fieldDecoration(
                        label: 'Mínimo',
                        icon: Icons.arrow_downward,
                        suffixText: '%',
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: row.maxController,
                      enabled: canEditSettings && !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _fieldDecoration(
                        label: 'Máximo',
                        icon: Icons.arrow_upward,
                        suffixText: '%',
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                  ),
                ],
              );
            },
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

  void _setFieldCount(int count) {
    final safeCount = count < 0 ? 0 : count;
    setState(() {
      if (_rows.length < safeCount) {
        final start = _rows.length;
        for (var i = start; i < safeCount; i++) {
          _rows.add(
            _OrderDiscountFieldDraftRow(
              label: 'Desconto ${i + 1}',
              minPercent: '0',
              maxPercent: '100',
            ),
          );
        }
      } else if (_rows.length > safeCount) {
        while (_rows.length > safeCount) {
          _rows.removeLast().dispose();
        }
      }
      _dirty = true;
    });
  }

  void _removeField(int index) {
    if (index < 0 || index >= _rows.length) {
      return;
    }

    setState(() {
      _rows.removeAt(index).dispose();
      _dirty = true;
      for (var i = 0; i < _rows.length; i++) {
        if (_rows[i].labelController.text.trim().isEmpty ||
            _rows[i].labelController.text.trim().startsWith('Desconto ')) {
          _rows[i].labelController.text = 'Desconto ${i + 1}';
        }
      }
    });
  }

  void _resetRowsFromIncoming(OrderDiscountPolicy incoming) {
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(
        incoming.fields.map(
          (field) => _OrderDiscountFieldDraftRow(
            label: field.label,
            minPercent: _formatPercent(field.minPercent),
            maxPercent: _formatPercent(field.maxPercent),
          ),
        ),
      );
  }

  String _formatPercent(double value) {
    final hasFraction = (value % 1).abs() > 0.00001;
    return hasFraction
        ? value.toStringAsFixed(2).replaceAll('.', ',')
        : value.toStringAsFixed(0);
  }

  double? _parsePercent(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized.replaceAll('.', '').replaceAll(',', '.')) ??
        double.tryParse(normalized.replaceAll(',', '.'));
  }

  Future<void> _save() async {
    final fields = <OrderDiscountFieldRule>[];
    for (var index = 0; index < _rows.length; index++) {
      final row = _rows[index];
      final label = row.labelController.text.trim().isEmpty
          ? 'Desconto ${index + 1}'
          : row.labelController.text.trim();

      final minPercent = _parsePercent(row.minController.text);
      final maxPercent = _parsePercent(row.maxController.text);
      if (minPercent == null || maxPercent == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Preencha mínimo e máximo válidos para o campo ${index + 1}.',
            ),
          ),
        );
        return;
      }

      fields.add(
        OrderDiscountFieldRule(
          label: label,
          minPercent: minPercent,
          maxPercent: maxPercent,
        ),
      );
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.updateOrderDiscountPolicy(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: widget.selectedRepresentedCompanyId,
        policy: OrderDiscountPolicy(fields: fields),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Política de descontos salva.')),
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
      ).showSnackBar(SnackBar(content: Text('Falha ao salvar política: $error')));
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

class _OrderDiscountFieldDraftRow {
  _OrderDiscountFieldDraftRow({
    required String label,
    required String minPercent,
    required String maxPercent,
  }) : labelController = TextEditingController(text: label),
       minController = TextEditingController(text: minPercent),
       maxController = TextEditingController(text: maxPercent);

  final TextEditingController labelController;
  final TextEditingController minController;
  final TextEditingController maxController;

  void dispose() {
    labelController.dispose();
    minController.dispose();
    maxController.dispose();
  }
}
