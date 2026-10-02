part of 'web_portal_page.dart';

class _PaymentConditionsSection extends StatefulWidget {
  const _PaymentConditionsSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  State<_PaymentConditionsSection> createState() =>
      _PaymentConditionsSectionState();
}

class _PaymentConditionsSectionState extends State<_PaymentConditionsSection> {
  final WorkspaceProfileService _service = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );
  final List<_PaymentConditionDraftRow> _rows = [];
  bool _initialized = false;
  bool _saving = false;
  String? _loadedTenantId;

  @override
  void didUpdateWidget(covariant _PaymentConditionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTenant.tenantId != widget.activeTenant.tenantId) {
      _clearControllers();
      _initialized = false;
      _loadedTenantId = null;
    }
  }

  @override
  void dispose() {
    _clearControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final representedName = widget.activeRepresentedCompanyName?.trim() ?? '';
    final canEditRules = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Condicoes de pagamento', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          representedName.isEmpty
              ? 'Cadastre as condicoes com descricao e valor minimo para elegibilidade no pedido.'
              : 'Cadastre as condicoes com descricao e valor minimo para a representada $representedName.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: StreamBuilder<List<PaymentConditionRule>>(
              stream: _service.watchPaymentConditionRules(
                tenantId: widget.activeTenant.tenantId,
              ),
              builder: (context, snapshot) {
                final rules = snapshot.data ?? const <PaymentConditionRule>[];
                if (!_initialized ||
                    _loadedTenantId != widget.activeTenant.tenantId) {
                  _syncControllers(rules);
                  _initialized = true;
                  _loadedTenantId = widget.activeTenant.tenantId;
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Condicoes de pagamento',
                                style: textTheme.titleMedium,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: canEditRules && !_saving
                                  ? _addRule
                                  : null,
                              icon: const Icon(Icons.add),
                              label: const Text('Nova condicao de pagamento'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Cada linha deve ter descricao e valor minimo para habilitar a condicao no pedido.',
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.35),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Descricao',
                                  style: textTheme.labelLarge,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 150,
                                child: Text(
                                  'Valor minimo',
                                  style: textTheme.labelLarge,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              const SizedBox(width: 44),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_rows.isEmpty)
                          const Text('Nenhuma condicao criada ainda.')
                        else
                          Column(
                            children: [
                              for (var index = 0; index < _rows.length; index++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final compact =
                                          constraints.maxWidth < 760;
                                      if (compact) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            TextField(
                                              controller: _rows[index]
                                                  .descriptionController,
                                              enabled: canEditRules && !_saving,
                                              decoration: const InputDecoration(
                                                labelText: 'Descricao *',
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller: _rows[index]
                                                        .minimumValueController,
                                                    enabled:
                                                        canEditRules &&
                                                        !_saving,
                                                    keyboardType:
                                                        const TextInputType.numberWithOptions(
                                                          decimal: true,
                                                        ),
                                                    textAlign: TextAlign.right,
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText:
                                                              'Valor minimo',
                                                          prefixText: 'R\$ ',
                                                          isDense: true,
                                                          border:
                                                              OutlineInputBorder(),
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Tooltip(
                                                  message: 'Remover linha',
                                                  child: IconButton.outlined(
                                                    onPressed:
                                                        canEditRules && !_saving
                                                        ? () =>
                                                              _removeRule(index)
                                                        : null,
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      }

                                      return Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _rows[index]
                                                  .descriptionController,
                                              enabled: canEditRules && !_saving,
                                              decoration: const InputDecoration(
                                                labelText: 'Descricao *',
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          SizedBox(
                                            width: 150,
                                            child: TextField(
                                              controller: _rows[index]
                                                  .minimumValueController,
                                              enabled: canEditRules && !_saving,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              textAlign: TextAlign.right,
                                              decoration: const InputDecoration(
                                                labelText: 'Valor minimo',
                                                prefixText: 'R\$ ',
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Tooltip(
                                            message: 'Remover linha',
                                            child: IconButton.outlined(
                                              onPressed:
                                                  canEditRules && !_saving
                                                  ? () => _removeRule(index)
                                                  : null,
                                              icon: const Icon(
                                                Icons.delete_outline,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        if (!canEditRules)
                          const Text(
                            'Esta conta esta em modo somente leitura. Apenas o owner pode alterar condicoes de pagamento.',
                          ),
                        if (canEditRules) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _saveRules,
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
                                _saving ? 'Salvando...' : 'Salvar condicoes',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _syncControllers(List<PaymentConditionRule> rules) {
    _clearControllers();
    if (rules.isEmpty) {
      _rows.add(_PaymentConditionDraftRow());
      return;
    }

    for (final rule in rules) {
      _rows.add(
        _PaymentConditionDraftRow(
          description: rule.description,
          minimumValue: _formatMoney(rule.minimumValue),
        ),
      );
    }
  }

  void _addRule() {
    setState(() {
      _rows.add(_PaymentConditionDraftRow());
    });
  }

  void _removeRule(int index) {
    if (_rows.length == 1) {
      _rows.first.descriptionController.clear();
      _rows.first.minimumValueController.text = '0,00';
      return;
    }

    setState(() {
      _rows.removeAt(index).dispose();
    });
  }

  Future<void> _saveRules() async {
    final values = _rows
        .map(
          (row) => PaymentConditionRule(
            description: row.descriptionController.text.trim(),
            minimumValue: _parseMoney(row.minimumValueController.text),
          ),
        )
        .where((rule) => rule.description.isNotEmpty)
        .toList(growable: false);

    if (values.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe ao menos uma condicao com descricao.'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.updatePaymentConditionRules(
        tenantId: widget.activeTenant.tenantId,
        values: values,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Condicoes de pagamento salvas.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar condicoes: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _clearControllers() {
    for (final row in _rows) {
      row.dispose();
    }
    _rows.clear();
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _parseMoney(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return 0;
    }

    final withDotDecimal = normalized.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(withDotDecimal) ??
        double.tryParse(normalized.replaceAll(',', '.')) ??
        0;
  }
}

class _PaymentConditionDraftRow {
  _PaymentConditionDraftRow({
    String description = '',
    String minimumValue = '0,00',
  }) : descriptionController = TextEditingController(text: description),
       minimumValueController = TextEditingController(text: minimumValue);

  final TextEditingController descriptionController;
  final TextEditingController minimumValueController;

  void dispose() {
    descriptionController.dispose();
    minimumValueController.dispose();
  }
}
