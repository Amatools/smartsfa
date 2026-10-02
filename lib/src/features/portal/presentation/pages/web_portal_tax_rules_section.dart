part of 'web_portal_page.dart';

class _TaxRulesSection extends StatefulWidget {
  const _TaxRulesSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  State<_TaxRulesSection> createState() => _TaxRulesSectionState();
}

class _TaxRulesSectionState extends State<_TaxRulesSection> {
  static const String _selectUfOption = 'SELECIONE';
  static final List<String> _ufOptions = <String>[
    _selectUfOption,
    ...brazilStates,
  ];

  static const Color _dialogChromeColor = Color(0xFFF5F6F8);
  static const Color _dialogBodyColor = Colors.white;
  static const Color _dialogBorderColor = Color(0xFFE3E6EA);
  static const Color _dialogFocusedBorderColor = Color(0xFFD0D6DE);
  static const double _dialogFieldVerticalGap = 14;

  final FirestoreTaxRuleRepository _repository = FirestoreTaxRuleRepository(
    FirebaseFirestore.instance,
  );

  bool _working = false;

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

    return Card(
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
                        'Tributações',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cadastre regras fiscais por NCM e UF de destino para aplicar ST no cálculo do item para $scopeLabel.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: canEditSettings && !_working
                      ? () => _openRuleDialog()
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Nova regra'),
                ),
              ],
            ),
            if (!canEditSettings) ...[
              const SizedBox(height: 10),
              _ownerOnlyReadOnlyNotice(
                context,
                message: 'Tributações ficam em modo somente leitura para este perfil. Apenas o owner pode alterar.',
              ),
            ],
            const SizedBox(height: 14),
            StreamBuilder<List<TaxRule>>(
              stream: _repository.watchAll(
                tenantId: widget.activeTenant.tenantId,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  if (_isPermissionDeniedError(snapshot.error!)) {
                    return const Text(
                      'Sem permissão de leitura para regras fiscais neste tenant. Verifique o deploy das regras do Firestore.',
                    );
                  }
                  return Text(
                    'Falha ao carregar regras fiscais: ${_extractErrorMessage(snapshot.error!)}',
                  );
                }

                final rules = snapshot.data ?? const <TaxRule>[];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    rules.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (rules.isEmpty) {
                  return const Text(
                    'Nenhuma regra fiscal cadastrada ainda. Crie a primeira para começar a política tributária.',
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final rule = rules[index];
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(
                          14,
                          10,
                          8,
                          10,
                        ),
                        title: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ruleChip(
                              context,
                              'NCM ${_withFallback(rule.ncm, 'Todos')}',
                            ),
                            if ((rule.cest ?? '').trim().isNotEmpty)
                              _ruleChip(context, 'CEST ${rule.cest!.trim()}'),
                            _ruleChip(
                              context,
                              'UF destino ${_displayUf(rule.ufDestino)}',
                            ),
                            _ruleChip(
                              context,
                              _displayStType(rule.stCalculationType),
                            ),
                            _ruleChip(
                              context,
                              rule.isActive ? 'Ativa' : 'Inativa',
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _taxSummary(rule),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Mover para cima',
                              onPressed:
                                  canEditSettings && !_working && index > 0
                                  ? () => _moveRule(
                                      rules: rules,
                                      index: index,
                                      direction: -1,
                                    )
                                  : null,
                              icon: const Icon(Icons.keyboard_arrow_up),
                            ),
                            IconButton(
                              tooltip: 'Mover para baixo',
                              onPressed:
                                  canEditSettings &&
                                      !_working &&
                                      index < rules.length - 1
                                  ? () => _moveRule(
                                      rules: rules,
                                      index: index,
                                      direction: 1,
                                    )
                                  : null,
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                            IconButton(
                              tooltip: 'Editar regra',
                              onPressed: canEditSettings && !_working
                                  ? () => _openRuleDialog(existing: rule)
                                  : null,
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Excluir regra',
                              onPressed: canEditSettings && !_working
                                  ? () => _deleteRule(rule)
                                  : null,
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _ruleChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.6),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }

  String _taxSummary(TaxRule rule) {
    final parts = <String>[
      'Alíquota destino ${_formatPercent(rule.aliquotaDestino ?? rule.aliquotaSt)}',
      'Alíquota crédito ${_formatPercent(rule.aliquotaCredito ?? rule.aliquotaIcms)}',
      'DIFAL ${_formatPercent(rule.aliquotaDifal)}',
    ];

    final fiscalException = (rule.fiscalException ?? '').trim();
    if (fiscalException.isNotEmpty) {
      parts.add('Exceção: $fiscalException');
    }

    final cstCsosn = (rule.cstCsosn ?? '').trim();
    if (cstCsosn.isNotEmpty) {
      parts.add('CST/CSOSN: $cstCsosn');
    }

    if (rule.validFrom != null || rule.validUntil != null) {
      parts.add(
        'Vigência ${_formatDate(rule.validFrom)} a ${_formatDate(rule.validUntil)}',
      );
    }

    final stType = (rule.stCalculationType ?? 'mva').toLowerCase();
    if (stType == 'pmc') {
      parts.add('Base ICMS-ST ${_formatCurrency(rule.stBaseAmount)}');
    } else {
      parts.add('Preco calc. ${_formatCurrency(rule.stPriceForCalculation)}');
      parts.add('MVA ${_formatPercent(rule.mvaIva)}');
      parts.add('Redução base ${_formatPercent(rule.stBaseReductionPercent)}');
    }

    return parts.join(' | ');
  }

  String _formatCurrency(double? value) {
    if (value == null) {
      return '-';
    }
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _displayStType(String? value) {
    if ((value ?? '').trim().toLowerCase() == 'pmc') {
      return 'Tipo ST: PMC';
    }
    return 'Tipo ST: MVA';
  }

  String _formatPercent(double? value) {
    if (value == null) {
      return '-';
    }
    return '${value.toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  String _withFallback(String? value, String fallback) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return fallback;
    }
    return normalized;
  }

  Future<void> _openRuleDialog({TaxRule? existing}) async {
    final draft = await _showRuleFormDialog(existing: existing);
    if (draft == null) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      final now = DateTime.now().toUtc();
      final id =
          existing?.id ??
          FirebaseFirestore.instance.collection('tax_rules').doc().id;
      final nextPriority = existing?.priority ?? await _nextRulePriority();
      final entity = TaxRule(
        id: id,
        tenantId: widget.activeTenant.tenantId,
        status: draft.active ? 'active' : 'inactive',
        ncm: _formatNcmMasked(_normalizeNcmDigits(draft.ncm)),
        cest: _nullable(_formatCestMasked(_normalizeCestDigits(draft.cest))),
        fiscalException: _nullable(draft.fiscalException),
        stCalculationType: draft.stCalculationType,
        stPriceForCalculation: _nullableDouble(draft.stPriceForCalculation),
        stBaseReductionPercent: _nullableDouble(draft.stBaseReductionPercent),
        stBaseAmount: _nullableDouble(draft.stBaseAmount),
        aliquotaDestino: _nullableDouble(draft.aliquotaDestino),
        aliquotaCredito: _nullableDouble(draft.aliquotaCredito),
        grupoFiscalId: null,
        ufOrigem: _nullable(existing?.ufOrigem)?.toUpperCase() ?? 'ANY',
        ufDestino: _normalizeUfForStorage(draft.ufDestino),
        cstCsosn: _nullable(draft.cstCsosn),
        aliquotaIcms: _nullableDouble(draft.aliquotaCredito),
        mvaIva: _nullableDouble(draft.mvaIva),
        aliquotaSt: _nullableDouble(draft.aliquotaDestino),
        aliquotaDifal: _nullableDouble(draft.aliquotaDifal),
        priority: nextPriority,
        validFrom: _toUtcStartOfDay(draft.validFrom),
        validUntil: _toUtcEndOfDay(draft.validUntil),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );

      await _repository.save(entity);
      _showMessage(
        existing == null
            ? 'Regra fiscal criada com sucesso.'
            : 'Regra fiscal atualizada com sucesso.',
      );
    } catch (error) {
      _showMessage(
        'Falha ao salvar regra fiscal: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _moveRule({
    required List<TaxRule> rules,
    required int index,
    required int direction,
  }) async {
    final targetIndex = index + direction;
    if (targetIndex < 0 || targetIndex >= rules.length) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      final reordered = List<TaxRule>.from(rules);
      final current = reordered[index];
      reordered[index] = reordered[targetIndex];
      reordered[targetIndex] = current;

      final now = DateTime.now().toUtc();
      final maxPriority = reordered.length;
      for (var i = 0; i < reordered.length; i++) {
        final targetPriority = maxPriority - i;
        final rule = reordered[i];
        if (rule.priority == targetPriority) {
          continue;
        }

        await _repository.save(
          _copyRuleWith(rule, priority: targetPriority, updatedAt: now),
        );
      }
    } catch (error) {
      _showMessage(
        'Falha ao reordenar regra fiscal: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<int> _nextRulePriority() async {
    try {
      final existing = await _repository.fetchAll(
        tenantId: widget.activeTenant.tenantId,
      );
      var maxPriority = 0;
      for (final item in existing) {
        if (item.priority > maxPriority) {
          maxPriority = item.priority;
        }
      }
      return maxPriority + 1;
    } catch (_) {
      return DateTime.now().microsecondsSinceEpoch;
    }
  }

  TaxRule _copyRuleWith(
    TaxRule source, {
    required int priority,
    required DateTime updatedAt,
  }) {
    return TaxRule(
      id: source.id,
      tenantId: source.tenantId,
      status: source.status,
      ncm: source.ncm,
      cest: source.cest,
      fiscalException: source.fiscalException,
      stCalculationType: source.stCalculationType,
      stPriceForCalculation: source.stPriceForCalculation,
      stBaseReductionPercent: source.stBaseReductionPercent,
      stBaseAmount: source.stBaseAmount,
      aliquotaDestino: source.aliquotaDestino,
      aliquotaCredito: source.aliquotaCredito,
      grupoFiscalId: source.grupoFiscalId,
      ufOrigem: source.ufOrigem,
      ufDestino: source.ufDestino,
      cstCsosn: source.cstCsosn,
      aliquotaIcms: source.aliquotaIcms,
      mvaIva: source.mvaIva,
      aliquotaSt: source.aliquotaSt,
      aliquotaDifal: source.aliquotaDifal,
      priority: priority,
      validFrom: source.validFrom,
      validUntil: source.validUntil,
      createdAt: source.createdAt,
      updatedAt: updatedAt,
    );
  }

  Future<void> _deleteRule(TaxRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir regra fiscal'),
          content: const Text('Deseja excluir esta regra fiscal?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      await _repository.delete(
        tenantId: widget.activeTenant.tenantId,
        id: rule.id,
      );
      _showMessage('Regra fiscal removida.');
    } catch (error) {
      _showMessage(
        'Falha ao remover regra fiscal: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<_TaxRuleDraft?> _showRuleFormDialog({TaxRule? existing}) async {
    final formKey = GlobalKey<FormState>();
    final ncmController = TextEditingController(
      text: _formatNcmMasked(_normalizeNcmDigits(existing?.ncm)),
    );
    final cestController = TextEditingController(
      text: _formatCestMasked(_normalizeCestDigits(existing?.cest)),
    );
    final fiscalExceptionController = TextEditingController(
      text: existing?.fiscalException ?? '',
    );
    var selectedUfDestino = _normalizeUfForDropdown(existing?.ufDestino);
    var stCalculationType = _readStCalculationType(existing?.stCalculationType);
    final cstCsosnController = TextEditingController(
      text: existing?.cstCsosn ?? '',
    );
    final stPriceForCalculationController = TextEditingController(
      text: _formatDecimalForInput(existing?.stPriceForCalculation),
    );
    final mvaController = TextEditingController(
      text: _formatDecimalForInput(existing?.mvaIva),
    );
    final stBaseReductionController = TextEditingController(
      text: _formatDecimalForInput(existing?.stBaseReductionPercent),
    );
    final stBaseAmountController = TextEditingController(
      text: _formatDecimalForInput(existing?.stBaseAmount),
    );
    final aliquotaDestinoController = TextEditingController(
      text: _formatDecimalForInput(
        existing?.aliquotaDestino ?? existing?.aliquotaSt,
      ),
    );
    final aliquotaCreditoController = TextEditingController(
      text: _formatDecimalForInput(
        existing?.aliquotaCredito ?? existing?.aliquotaIcms,
      ),
    );
    final aliquotaDifalController = TextEditingController(
      text: _formatDecimalForInput(existing?.aliquotaDifal),
    );
    var validFrom = existing?.validFrom?.toLocal();
    var validUntil = existing?.validUntil?.toLocal();
    var active = existing?.isActive ?? true;

    final result = await showDialog<_TaxRuleDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Container(
                  decoration: BoxDecoration(
                    color: _dialogBodyColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _dialogBorderColor, width: 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        color: _dialogChromeColor,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Text(
                          existing == null
                              ? 'Nova regra fiscal'
                              : 'Editar regra fiscal',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Container(
                        color: _dialogBodyColor,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: SizedBox(
                          width: 620,
                          child: Form(
                            key: formKey,
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: SwitchListTile.adaptive(
                                      contentPadding: EdgeInsets.zero,
                                      value: active,
                                      onChanged: (value) {
                                        setDialogState(() {
                                          active = value;
                                        });
                                      },
                                      title: const Text('Regra ativa'),
                                    ),
                                  ),
                                  const SizedBox(
                                    height: _dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _labeledTextField(
                                          label: 'NCM *',
                                          controller: ncmController,
                                          hintText: '0000.00.00',
                                          inputFormatters: <TextInputFormatter>[
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            _NcmInputFormatter(),
                                          ],
                                          validator: (raw) {
                                            final digits = _normalizeNcmDigits(
                                              raw,
                                            );
                                            if (digits.isEmpty) {
                                              return 'NCM obrigatório';
                                            }
                                            if (!_isValidNcmDigits(digits)) {
                                              return 'NCM deve ter 8 dígitos';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _labeledTextField(
                                          label: 'CEST (opcional)',
                                          controller: cestController,
                                          hintText: '00.000.00',
                                          inputFormatters: <TextInputFormatter>[
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            _CestInputFormatter(),
                                          ],
                                          validator: (raw) {
                                            final digits = _normalizeCestDigits(
                                              raw,
                                            );
                                            if (digits.isEmpty) {
                                              return null;
                                            }
                                            if (!_isValidCestDigits(digits)) {
                                              return 'CEST deve ter 7 dígitos';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: _dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _labeledUfDropdown(
                                          label: 'UF destino *',
                                          value: selectedUfDestino,
                                          onChanged: (value) {
                                            setDialogState(() {
                                              selectedUfDestino =
                                                  value ?? _selectUfOption;
                                            });
                                          },
                                          validator: (value) {
                                            if ((value ?? _selectUfOption) ==
                                                _selectUfOption) {
                                              return 'Selecione a UF destino';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _labeledTextField(
                                          label: 'Exceção fiscal',
                                          controller: fiscalExceptionController,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: _dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _labeledTextField(
                                          label: 'CST/CSOSN',
                                          controller: cstCsosnController,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _unitField(
                                          controller: aliquotaDifalController,
                                          label: 'Alíquota DIFAL',
                                          suffixText: '%',
                                          min: 0,
                                          max: 100,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: _dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _labeledDateField(
                                          label: 'Vigência inicial',
                                          value: validFrom,
                                          onPick: () async {
                                            final picked = await _pickDate(
                                              context,
                                              initialDate: validFrom,
                                            );
                                            if (picked == null) {
                                              return;
                                            }
                                            setDialogState(() {
                                              validFrom = picked;
                                            });
                                          },
                                          onClear: validFrom == null
                                              ? null
                                              : () {
                                                  setDialogState(() {
                                                    validFrom = null;
                                                  });
                                                },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _labeledDateField(
                                          label: 'Vigência final',
                                          value: validUntil,
                                          onPick: () async {
                                            final picked = await _pickDate(
                                              context,
                                              initialDate: validUntil,
                                            );
                                            if (picked == null) {
                                              return;
                                            }
                                            setDialogState(() {
                                              validUntil = picked;
                                            });
                                          },
                                          onClear: validUntil == null
                                              ? null
                                              : () {
                                                  setDialogState(() {
                                                    validUntil = null;
                                                  });
                                                },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: _dialogFieldVerticalGap,
                                  ),
                                  _labeledStCalculationTypeDropdown(
                                    value: stCalculationType,
                                    onChanged: (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        stCalculationType = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(
                                    height: _dialogFieldVerticalGap,
                                  ),
                                  if (stCalculationType ==
                                      _StCalculationType.mva) ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _unitField(
                                            controller:
                                                stPriceForCalculationController,
                                            label: 'Preço considerado no cálculo (opcional)',
                                            prefixText: 'R\$',
                                            required: false,
                                            min: 0,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _unitField(
                                            controller: mvaController,
                                            label: 'Margem de valor agregado',
                                            suffixText: '%',
                                            required: true,
                                            min: 0,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(
                                      height: _dialogFieldVerticalGap,
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _unitField(
                                            controller:
                                                stBaseReductionController,
                                            label: 'Redução de base ICMS-ST',
                                            suffixText: '%',
                                            required: true,
                                            min: 0,
                                            max: 100,
                                          ),
                                        ),
                                        const Expanded(
                                          child: SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _unitField(
                                            controller: stBaseAmountController,
                                            label: 'Base de cálculo ICMS-ST',
                                            prefixText: 'R\$',
                                            required: true,
                                            min: 0,
                                          ),
                                        ),
                                        const Expanded(
                                          child: SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(
                                    height: _dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _unitField(
                                          controller: aliquotaDestinoController,
                                          label: 'Alíquota destino',
                                          suffixText: '%',
                                          required: true,
                                          min: 0,
                                          max: 100,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _unitField(
                                          controller: aliquotaCreditoController,
                                          label: 'Alíquota crédito',
                                          suffixText: '%',
                                          required: true,
                                          min: 0,
                                          max: 100,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        color: _dialogChromeColor,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('Cancelar'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () {
                                if (!(formKey.currentState?.validate() ??
                                    true)) {
                                  return;
                                }

                                if (!_isValidDateWindow(
                                  validFrom,
                                  validUntil,
                                )) {
                                  ScaffoldMessenger.of(dialogContext)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'A vigência final não pode ser anterior à vigência inicial.',
                                        ),
                                      ),
                                    );
                                  return;
                                }

                                Navigator.of(dialogContext).pop(
                                  _TaxRuleDraft(
                                    active: active,
                                    ncm: ncmController.text,
                                    cest: cestController.text,
                                    fiscalException:
                                        fiscalExceptionController.text,
                                    ufDestino: selectedUfDestino,
                                    stCalculationType:
                                        _stCalculationTypeToStorage(
                                          stCalculationType,
                                        ),
                                    stPriceForCalculation:
                                        stPriceForCalculationController.text,
                                    mvaIva: mvaController.text,
                                    stBaseReductionPercent:
                                        stBaseReductionController.text,
                                    stBaseAmount: stBaseAmountController.text,
                                    aliquotaDestino:
                                        aliquotaDestinoController.text,
                                    aliquotaCredito:
                                        aliquotaCreditoController.text,
                                    aliquotaDifal: aliquotaDifalController.text,
                                    cstCsosn: cstCsosnController.text,
                                    validFrom: validFrom,
                                    validUntil: validUntil,
                                  ),
                                );
                              },
                              child: const Text('Salvar'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // Os controllers ficam anexados aos campos durante a animacao de fechamento
    // do dialogo. Dispor aqui pode causar "used after disposed" no frame seguinte.

    return result;
  }

  Widget _labeledTextField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    FormFieldValidator<String>? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          decoration: _dialogInputDecoration(hintText: hintText),
        ),
      ],
    );
  }

  Widget _labeledUfDropdown({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
    FormFieldValidator<String>? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: _dialogInputDecoration(),
          validator: validator,
          items: _ufOptions
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item == _selectUfOption ? 'Selecione' : item),
                ),
              )
              .toList(growable: false),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _labeledDateField({
    required String label,
    required DateTime? value,
    required VoidCallback onPick,
    VoidCallback? onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: _dialogInputDecoration(
              hintText: 'Sem limite',
              suffixText: onClear == null ? null : 'X',
            ),
            child: Row(
              children: [
                Expanded(child: Text(_formatDate(value))),
                IconButton(
                  tooltip: onClear == null ? 'Selecionar data' : 'Limpar data',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear ?? onPick,
                  icon: Icon(
                    onClear == null
                        ? Icons.calendar_today_outlined
                        : Icons.clear_outlined,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _labeledStCalculationTypeDropdown({
    required _StCalculationType value,
    required ValueChanged<_StCalculationType?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tipo de subs. tributária',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<_StCalculationType>(
          initialValue: value,
          decoration: _dialogInputDecoration(),
          items: const [
            DropdownMenuItem<_StCalculationType>(
              value: _StCalculationType.mva,
              child: Text('Por MVA'),
            ),
            DropdownMenuItem<_StCalculationType>(
              value: _StCalculationType.pmc,
              child: Text('Por PMC'),
            ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _unitField({
    required TextEditingController controller,
    required String label,
    String? prefixText,
    String? suffixText,
    bool required = false,
    double? min,
    double? max,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9,\\.]')),
          ],
          decoration: _dialogInputDecoration(
            prefixText: prefixText,
            suffixText: suffixText,
            suffixBackground: _dialogChromeColor,
            prefixBackground: _dialogChromeColor,
          ),
          validator: (raw) {
            final source = (raw ?? '').trim();
            if (required && source.isEmpty) {
              return 'Campo obrigatório';
            }
            final value = _nullableDouble(raw);
            if (source.isNotEmpty && value == null) {
              return 'Número inválido';
            }
            if (value == null) {
              return null;
            }
            if (min != null && value < min) {
              return 'Valor mínimo: ${min.toStringAsFixed(0)}';
            }
            if (max != null && value > max) {
              return 'Valor máximo: ${max.toStringAsFixed(0)}';
            }
            return null;
          },
        ),
      ],
    );
  }

  InputDecoration _dialogInputDecoration({
    String? prefixText,
    String? suffixText,
    Color? prefixBackground,
    Color? suffixBackground,
    String? hintText,
  }) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: _dialogBodyColor,
      hintText: hintText,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: _dialogFieldBorder(_dialogBorderColor),
      enabledBorder: _dialogFieldBorder(_dialogBorderColor),
      focusedBorder: _dialogFieldBorder(_dialogFocusedBorderColor),
      prefixIcon: prefixText == null
          ? null
          : Container(
              width: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: prefixBackground ?? _dialogBodyColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
                border: Border(
                  right: BorderSide(color: _dialogBorderColor, width: 1),
                ),
              ),
              child: Text(
                prefixText,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
      suffixIcon: suffixText == null
          ? null
          : Container(
              width: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: suffixBackground ?? _dialogBodyColor,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border(
                  left: BorderSide(color: _dialogBorderColor, width: 1),
                ),
              ),
              child: Text(
                suffixText,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
    );
  }

  OutlineInputBorder _dialogFieldBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color, width: 1),
    );
  }

  bool _isPermissionDeniedError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('permission-denied') ||
        text.contains('insufficient permissions');
  }

  String _normalizeUfForStorage(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    if (normalized.isEmpty ||
        normalized == _selectUfOption ||
        normalized == 'ANY') {
      return '';
    }
    return normalized;
  }

  String _normalizeUfForDropdown(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    if (normalized.isEmpty || normalized == 'ANY') {
      return _selectUfOption;
    }
    if (isBrazilState(normalized)) {
      return normalized;
    }
    return _selectUfOption;
  }

  String _displayUf(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    if (normalized.isEmpty || normalized == 'ANY') {
      return 'Qualquer';
    }
    return normalized;
  }

  Future<DateTime?> _pickDate(BuildContext context, {DateTime? initialDate}) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initialDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
  }

  bool _isValidDateWindow(DateTime? validFrom, DateTime? validUntil) {
    if (validFrom == null || validUntil == null) {
      return true;
    }
    return !validUntil.isBefore(validFrom);
  }

  DateTime? _toUtcStartOfDay(DateTime? value) {
    if (value == null) {
      return null;
    }
    return DateTime.utc(value.year, value.month, value.day);
  }

  DateTime? _toUtcEndOfDay(DateTime? value) {
    if (value == null) {
      return null;
    }
    return DateTime.utc(value.year, value.month, value.day, 23, 59, 59, 999);
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Sem limite';
    }
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }

  String? _nullable(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  double? _nullableDouble(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return _parseDouble(normalized);
  }

  double? _parseDouble(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    if (RegExp(r'[^0-9.]').hasMatch(normalized)) {
      return null;
    }
    if ('.'.allMatches(normalized).length > 1) {
      return null;
    }
    return double.tryParse(normalized);
  }

  String _normalizeNcmDigits(String? value) {
    return (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _normalizeCestDigits(String? value) {
    return (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  }

  bool _isValidNcmDigits(String digits) {
    return RegExp(r'^\d{8}$').hasMatch(digits);
  }

  bool _isValidCestDigits(String digits) {
    return RegExp(r'^\d{7}$').hasMatch(digits);
  }

  String _formatNcmMasked(String? value) {
    final digits = _normalizeNcmDigits(value);
    if (digits.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 8; i++) {
      if (i == 4 || i == 6) {
        buffer.write('.');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  String _formatCestMasked(String? value) {
    final digits = _normalizeCestDigits(value);
    if (digits.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 7; i++) {
      if (i == 2 || i == 5) {
        buffer.write('.');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  _StCalculationType _readStCalculationType(String? value) {
    if ((value ?? '').trim().toLowerCase() == 'pmc') {
      return _StCalculationType.pmc;
    }
    return _StCalculationType.mva;
  }

  String _stCalculationTypeToStorage(_StCalculationType value) {
    return value == _StCalculationType.pmc ? 'pmc' : 'mva';
  }

  String _formatDecimalForInput(double? value) {
    if (value == null) {
      return '';
    }
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _extractErrorMessage(Object error) {
    final text = error.toString().trim();
    const prefix = 'Bad state: ';
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length);
    }
    return text;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _StCalculationType { mva, pmc }

class _NcmInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final truncated = digits.length > 8 ? digits.substring(0, 8) : digits;

    final buffer = StringBuffer();
    for (var i = 0; i < truncated.length; i++) {
      if (i == 4 || i == 6) {
        buffer.write('.');
      }
      buffer.write(truncated[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _CestInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final truncated = digits.length > 7 ? digits.substring(0, 7) : digits;

    final buffer = StringBuffer();
    for (var i = 0; i < truncated.length; i++) {
      if (i == 2 || i == 5) {
        buffer.write('.');
      }
      buffer.write(truncated[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _TaxRuleDraft {
  const _TaxRuleDraft({
    required this.active,
    required this.ncm,
    required this.cest,
    required this.fiscalException,
    required this.ufDestino,
    required this.stCalculationType,
    required this.stPriceForCalculation,
    required this.mvaIva,
    required this.stBaseReductionPercent,
    required this.stBaseAmount,
    required this.aliquotaDestino,
    required this.aliquotaCredito,
    required this.aliquotaDifal,
    required this.cstCsosn,
    required this.validFrom,
    required this.validUntil,
  });

  final bool active;
  final String ncm;
  final String cest;
  final String fiscalException;
  final String ufDestino;
  final String stCalculationType;
  final String stPriceForCalculation;
  final String mvaIva;
  final String stBaseReductionPercent;
  final String stBaseAmount;
  final String aliquotaDestino;
  final String aliquotaCredito;
  final String aliquotaDifal;
  final String cstCsosn;
  final DateTime? validFrom;
  final DateTime? validUntil;
}
