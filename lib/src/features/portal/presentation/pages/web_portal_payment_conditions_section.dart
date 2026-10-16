part of 'web_portal_page.dart';

class _PaymentConditionsSection extends StatefulWidget {
  const _PaymentConditionsSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
    this.selectedRepresentedCompanyId,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;
  final String? selectedRepresentedCompanyId;

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
  String? _loadedScope;

  String _currentScopeKey() {
    final representedCompanyId = (widget.selectedRepresentedCompanyId ?? '')
        .trim();
    if (representedCompanyId.isEmpty) {
      return '${widget.activeTenant.tenantId}::tenant_default';
    }
    return '${widget.activeTenant.tenantId}::${representedCompanyId.replaceAll('.', '_')}';
  }

  @override
  void didUpdateWidget(covariant _PaymentConditionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTenant.tenantId != widget.activeTenant.tenantId ||
        oldWidget.selectedRepresentedCompanyId !=
            widget.selectedRepresentedCompanyId) {
      _clearControllers();
      _initialized = false;
      _loadedScope = null;
    }
  }

  @override
  void dispose() {
    _clearControllers();
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
    final textTheme = Theme.of(context).textTheme;
    final representedName = widget.activeRepresentedCompanyName?.trim() ?? '';
    final representedCompanyId = (widget.selectedRepresentedCompanyId ?? '')
        .trim();
    final requiresRepresentedScope =
        widget.activeTenant.workspaceType == 'seller_solo_workspace' ||
        widget.activeTenant.workspaceType == 'rep_workspace';
    final hasRepresentedScope = representedCompanyId.isNotEmpty;
    final canEditRules = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Condições de pagamento', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          representedName.isEmpty
              ? 'Cadastre as condições com descrição e valor mínimo para elegibilidade no pedido.'
              : 'Cadastre as condições com descrição e valor mínimo para a representada $representedName.',
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
                representedCompanyId: widget.selectedRepresentedCompanyId,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        'Falha ao carregar condições de pagamento: $error',
                        style: textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  );
                }

                final rules = snapshot.data ?? const <PaymentConditionRule>[];
                final currentScope = _currentScopeKey();
                if (!_initialized || _loadedScope != currentScope) {
                  _syncControllers(rules);
                  _initialized = true;
                  _loadedScope = currentScope;
                }

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Condições de pagamento',
                                style: textTheme.titleMedium,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: canEditRules && !_saving
                                  ? _addRule
                                  : null,
                              icon: const Icon(Icons.add),
                              label: const Text('Nova condição de pagamento'),
                              style: OutlinedButton.styleFrom(
                                shape: const StadiumBorder(),
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Cada linha deve ter descrição e valor mínimo para habilitar a condição no pedido.',
                          style: textTheme.bodySmall,
                        ),
                        if (requiresRepresentedScope && !hasRepresentedScope)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Selecione a representada ativa no topo do portal para salvar neste módulo.',
                              style: textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
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
                                  'Descrição',
                                  style: textTheme.labelLarge,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 150,
                                child: Text(
                                  'Valor mínimo',
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
                          const Text('Nenhuma condição criada ainda.')
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
                                      final colors = Theme.of(context)
                                          .colorScheme;
                                      if (compact) {
                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            color: colors
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.16),
                                            border: Border.all(
                                              color: colors.outlineVariant
                                                  .withValues(alpha: 0.45),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              TextField(
                                                controller: _rows[index]
                                                    .descriptionController,
                                                enabled:
                                                    canEditRules && !_saving,
                                                decoration: _fieldDecoration(
                                                  label: 'Descrição *',
                                                  icon: Icons.short_text,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: TextField(
                                                      controller: _rows[index]
                                                          .minimumValueController,
                                                      focusNode: _rows[index]
                                                          .minimumValueFocusNode,
                                                      enabled:
                                                          canEditRules &&
                                                          !_saving,
                                                      keyboardType:
                                                          const TextInputType.numberWithOptions(
                                                            decimal: true,
                                                          ),
                                                      inputFormatters: [
                                                        FilteringTextInputFormatter.allow(
                                                          RegExp(r'[0-9,\.]'),
                                                        ),
                                                      ],
                                                      onEditingComplete: () {
                                                        _normalizeMoneyController(
                                                          _rows[index]
                                                              .minimumValueController,
                                                        );
                                                      },
                                                      onTapOutside: (_) {
                                                        _normalizeMoneyController(
                                                          _rows[index]
                                                              .minimumValueController,
                                                        );
                                                      },
                                                      textAlign:
                                                          TextAlign.right,
                                                      decoration: _fieldDecoration(
                                                        label: 'Valor mínimo',
                                                        icon: Icons
                                                            .payments_outlined,
                                                        prefixText: 'R\$ ',
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Tooltip(
                                                    message: 'Remover linha',
                                                    child: IconButton.outlined(
                                                      onPressed:
                                                          canEditRules &&
                                                              !_saving
                                                          ? () => _removeRule(
                                                              index,
                                                            )
                                                          : null,
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      }

                                      return Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          color: colors.surfaceContainerHighest
                                              .withValues(alpha: 0.16),
                                          border: Border.all(
                                            color: colors.outlineVariant
                                                .withValues(alpha: 0.45),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: _rows[index]
                                                    .descriptionController,
                                                enabled:
                                                    canEditRules && !_saving,
                                                decoration: _fieldDecoration(
                                                  label: 'Descrição *',
                                                  icon: Icons.short_text,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 180,
                                              child: TextField(
                                                controller: _rows[index]
                                                    .minimumValueController,
                                                focusNode: _rows[index]
                                                    .minimumValueFocusNode,
                                                enabled:
                                                    canEditRules && !_saving,
                                                keyboardType:
                                                    const TextInputType.numberWithOptions(
                                                      decimal: true,
                                                    ),
                                                inputFormatters: [
                                                  FilteringTextInputFormatter.allow(
                                                    RegExp(r'[0-9,\.]'),
                                                  ),
                                                ],
                                                onEditingComplete: () {
                                                  _normalizeMoneyController(
                                                    _rows[index]
                                                        .minimumValueController,
                                                  );
                                                },
                                                onTapOutside: (_) {
                                                  _normalizeMoneyController(
                                                    _rows[index]
                                                        .minimumValueController,
                                                  );
                                                },
                                                textAlign: TextAlign.right,
                                                decoration: _fieldDecoration(
                                                  label: 'Valor mínimo',
                                                  icon: Icons.payments_outlined,
                                                  prefixText: 'R\$ ',
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
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        if (!canEditRules)
                          const Text(
                            'Esta conta está em modo somente leitura. Apenas o owner pode alterar condições de pagamento.',
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
                                _saving ? 'Salvando...' : 'Salvar condições',
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
      _rows.add(_createDraftRow());
      return;
    }

    for (final rule in rules) {
      _rows.add(
        _createDraftRow(
          description: rule.description,
          minimumValue: _formatMoney(rule.minimumValue),
        ),
      );
    }
  }

  void _addRule() {
    setState(() {
      _rows.add(_createDraftRow());
    });
  }

  _PaymentConditionDraftRow _createDraftRow({
    String description = '',
    String minimumValue = '0,00',
  }) {
    final row = _PaymentConditionDraftRow(
      description: description,
      minimumValue: minimumValue,
    );
    row.minimumValueFocusNode.addListener(() {
      if (!row.minimumValueFocusNode.hasFocus) {
        _normalizeMoneyController(row.minimumValueController);
      }
    });
    return row;
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
    for (final row in _rows) {
      _normalizeMoneyController(row.minimumValueController);
    }

    final representedCompanyId = (widget.selectedRepresentedCompanyId ?? '')
        .trim();
    final requiresRepresentedScope =
        widget.activeTenant.workspaceType == 'seller_solo_workspace' ||
        widget.activeTenant.workspaceType == 'rep_workspace';
    if (requiresRepresentedScope && representedCompanyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecione a representada ativa no topo para salvar as condições.',
          ),
        ),
      );
      return;
    }

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
          content: Text('Informe ao menos uma condição com descrição.'),
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
        representedCompanyId: representedCompanyId,
      );

      _initialized = false;

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Condições de pagamento salvas.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FirebaseException
                ? 'Falha ao salvar condições (${error.code}): ${error.message ?? 'erro sem detalhes'}'
                : 'Falha ao salvar condições: $error',
          ),
        ),
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

  void _normalizeMoneyController(TextEditingController controller) {
    final parsed = _tryParseMoney(controller.text);
    if (parsed == null) {
      controller.text = '0,00';
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length),
      );
      return;
    }

    controller.text = _formatMoney(parsed);
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
  }

  double _parseMoney(String raw) {
    return _tryParseMoney(raw) ?? 0;
  }

  double? _tryParseMoney(String raw) {
    final sanitized = raw.trim();
    if (sanitized.isEmpty) {
      return null;
    }

    final normalized = sanitized.replaceAll(RegExp(r'[^0-9,\.]'), '');
    if (normalized.isEmpty) {
      return null;
    }

    final hasComma = normalized.contains(',');
    final hasDot = normalized.contains('.');

    // Pure integer: "600" -> 600.00
    if (!hasComma && !hasDot) {
      return double.tryParse(normalized);
    }

    final lastComma = normalized.lastIndexOf(',');
    final lastDot = normalized.lastIndexOf('.');
    final separatorIndex = lastComma > lastDot ? lastComma : lastDot;

    if (separatorIndex <= 0) {
      final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.isEmpty ? null : double.tryParse(digits);
    }

    final intDigits = normalized
        .substring(0, separatorIndex)
        .replaceAll(RegExp(r'[^0-9]'), '');
    var fracDigits = normalized
        .substring(separatorIndex + 1)
        .replaceAll(RegExp(r'[^0-9]'), '');

    final safeInt = intDigits.isEmpty ? '0' : intDigits;
    if (fracDigits.isEmpty) {
      fracDigits = '00';
    } else if (fracDigits.length == 1) {
      fracDigits = '${fracDigits}0';
    } else if (fracDigits.length > 2) {
      fracDigits = fracDigits.substring(0, 2);
    }

    return double.tryParse('$safeInt.$fracDigits');
  }
}

class _PaymentConditionDraftRow {
  _PaymentConditionDraftRow({
    String description = '',
    String minimumValue = '0,00',
  }) : descriptionController = TextEditingController(text: description),
       minimumValueController = TextEditingController(text: minimumValue),
       minimumValueFocusNode = FocusNode();

  final TextEditingController descriptionController;
  final TextEditingController minimumValueController;
  final FocusNode minimumValueFocusNode;

  void dispose() {
    descriptionController.dispose();
    minimumValueController.dispose();
    minimumValueFocusNode.dispose();
  }
}
