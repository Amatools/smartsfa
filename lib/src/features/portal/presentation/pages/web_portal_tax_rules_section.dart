part of 'web_portal_page.dart';

class _TaxRulesSection extends StatefulWidget {
  const _TaxRulesSection({
    required this.activeTenant,
    this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_TaxRulesSection> createState() => _TaxRulesSectionState();
}

class _TaxRulesSectionState extends State<_TaxRulesSection> {
  static const String _selectUfOption = 'SELECIONE';
  static const String _anyUfOption = 'QUALQUER';
  static final List<String> _ufOptions = <String>[
    _selectUfOption,
    ...brazilStates,
  ];
  static final List<String> _ufFilterOptions = <String>[
    _selectUfOption,
    _anyUfOption,
    ...brazilStates,
  ];

  static const Color _dialogChromeColor = Color(0xFFF5F6F8);
  static const Color _dialogBodyColor = Colors.white;
  static const Color _dialogBorderColor = Color(0xFFE3E6EA);
  static const Color _dialogFocusedBorderColor = Color(0xFFD0D6DE);
  static const double _dialogFieldVerticalGap = 14;
  static const int _rulesPageSize = 100;
  static const Duration _textFilterDebounceDelay = Duration(milliseconds: 250);

  final FirestoreTaxRuleRepository _repository = FirestoreTaxRuleRepository(
    FirebaseFirestore.instance,
  );
  final TextEditingController _filterNcmController = TextEditingController();
  final TextEditingController _filterCestController = TextEditingController();

  bool _working = false;
  int _visibleRulesCount = _rulesPageSize;
  String _filterNcm = '';
  String _filterCest = '';
  String _filterUfDestino = _selectUfOption;
  int _textFilterDebounceToken = 0;

  String get _selectedRepresentedCompanyId {
    return (widget.selectedRepresentedCompanyId ?? '').trim();
  }

  bool _isGlobalRuleScope(TaxRule rule) {
    return (rule.representedCompanyId ?? '').trim().isEmpty;
  }

  bool _isSelectedRepresentedRuleScope(TaxRule rule) {
    final selected = _selectedRepresentedCompanyId;
    if (selected.isEmpty) {
      return false;
    }
    return (rule.representedCompanyId ?? '').trim() == selected;
  }

  bool _matchesSelectedRepresentedScope(TaxRule rule) {
    final selected = _selectedRepresentedCompanyId;
    if (selected.isEmpty) {
      return false;
    }
    final scope = (rule.representedCompanyId ?? '').trim();
    return scope == selected || scope.isEmpty;
  }

  List<TaxRule> _sortRulesForDisplay(List<TaxRule> rules) {
    final sorted = List<TaxRule>.from(rules);
    sorted.sort((a, b) {
      final aIsSelectedScope = _isSelectedRepresentedRuleScope(a);
      final bIsSelectedScope = _isSelectedRepresentedRuleScope(b);
      if (aIsSelectedScope != bIsSelectedScope) {
        return aIsSelectedScope ? -1 : 1;
      }
      return b.priority.compareTo(a.priority);
    });
    return sorted;
  }

  String _scopeChipLabel(TaxRule rule) {
    return _isGlobalRuleScope(rule)
        ? 'Escopo: Global (ERP)'
        : 'Escopo: Representada';
  }

  String? _resolveRuleScopeForSave(TaxRule? existing) {
    if (existing != null) {
      final existingScope = (existing.representedCompanyId ?? '').trim();
      return existingScope.isEmpty ? null : existingScope;
    }

    final selected = _selectedRepresentedCompanyId;
    return selected.isEmpty ? null : selected;
  }

  @override
  void initState() {
    super.initState();
    _filterNcmController.text = _filterNcm;
    _filterCestController.text = _filterCest;
    _filterNcmController.addListener(_scheduleTextFiltersApply);
    _filterCestController.addListener(_scheduleTextFiltersApply);
  }

  @override
  void dispose() {
    _textFilterDebounceToken++;
    _filterNcmController.removeListener(_scheduleTextFiltersApply);
    _filterCestController.removeListener(_scheduleTextFiltersApply);
    _filterNcmController.dispose();
    _filterCestController.dispose();
    super.dispose();
  }

  void _scheduleTextFiltersApply() {
    final token = ++_textFilterDebounceToken;
    Future<void>.delayed(_textFilterDebounceDelay, () {
      if (!mounted || token != _textFilterDebounceToken) {
        return;
      }

      final nextNcm = _filterNcmController.text;
      final nextCest = _filterCestController.text;
      if (nextNcm == _filterNcm && nextCest == _filterCest) {
        return;
      }

      setState(() {
        _filterNcm = nextNcm;
        _filterCest = nextCest;
        _resetVisibleCountAfterFilterChange();
      });
    });
  }

  void _ensureVisibleRulesCountWithin(List<TaxRule> rules) {
    final total = rules.length;
    if (total == 0) {
      if (_visibleRulesCount != _rulesPageSize) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _visibleRulesCount = _rulesPageSize;
          });
        });
      }
      return;
    }

    final minVisible = total < _rulesPageSize ? total : _rulesPageSize;
    final clamped = _visibleRulesCount.clamp(minVisible, total);
    if (clamped != _visibleRulesCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _visibleRulesCount = clamped;
        });
      });
    }
  }

  void _loadMoreRules(List<TaxRule> rules) {
    final total = rules.length;
    if (total == 0 || _visibleRulesCount >= total) {
      return;
    }

    setState(() {
      _visibleRulesCount = (_visibleRulesCount + _rulesPageSize).clamp(
        _rulesPageSize,
        total,
      );
    });
  }

  bool _hasActiveFilters() {
    return _normalizeNcmDigits(_filterNcm).isNotEmpty ||
        _normalizeCestDigits(_filterCest).isNotEmpty ||
        _filterUfDestino != _selectUfOption;
  }

  bool _matchesFilters(TaxRule rule) {
    final ncmFilter = _normalizeNcmDigits(_filterNcm);
    if (ncmFilter.isNotEmpty) {
      final ruleNcm = _normalizeNcmDigits(rule.ncm);
      if (!ruleNcm.contains(ncmFilter)) {
        return false;
      }
    }

    final cestFilter = _normalizeCestDigits(_filterCest);
    if (cestFilter.isNotEmpty) {
      final ruleCest = _normalizeCestDigits(rule.cest);
      if (!ruleCest.contains(cestFilter)) {
        return false;
      }
    }

    final ufFilter = _filterUfDestino.trim().toUpperCase();
    final ruleUf = (rule.ufDestino).trim().toUpperCase();
    if (ufFilter == _anyUfOption) {
      return ruleUf.isEmpty || ruleUf == 'ANY';
    }
    if (ufFilter != _selectUfOption && ruleUf != ufFilter) {
      return false;
    }

    return true;
  }

  List<TaxRule> _applyFilters(List<TaxRule> rules) {
    return rules.where(_matchesFilters).toList(growable: false);
  }

  void _resetVisibleCountAfterFilterChange() {
    _visibleRulesCount = _rulesPageSize;
  }

  Widget _buildFiltersSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 180,
            child: TextFormField(
              controller: _filterNcmController,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Filtrar NCM',
                hintText: 'Ex.: 8421',
              ),
            ),
          ),
          SizedBox(
            width: 180,
            child: TextFormField(
              controller: _filterCestController,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Filtrar CEST',
                hintText: 'Ex.: 21.117',
              ),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              initialValue: _filterUfDestino,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Filtrar UF destino',
              ),
              items: _ufFilterOptions
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                final next = (value ?? _selectUfOption).trim().toUpperCase();
                if (next == _filterUfDestino) {
                  return;
                }
                setState(() {
                  _filterUfDestino = next;
                  _resetVisibleCountAfterFilterChange();
                });
              },
            ),
          ),
          if (_hasActiveFilters())
            OutlinedButton.icon(
              onPressed: () {
                _textFilterDebounceToken++;
                _filterNcmController.clear();
                _filterCestController.clear();
                setState(() {
                  _filterNcm = '';
                  _filterCest = '';
                  _filterUfDestino = _selectUfOption;
                  _resetVisibleCountAfterFilterChange();
                });
              },
              icon: const Icon(Icons.clear),
              label: const Text('Limpar filtros'),
            ),
        ],
      ),
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
    final selectedRepresentedCompanyId = _selectedRepresentedCompanyId;

    if (selectedRepresentedCompanyId.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Selecione uma representada ativa para gerenciar as regras de tributação deste escopo.',
          ),
        ),
      );
    }

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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: canEditSettings && !_working
                          ? () => _downloadTaxTemplate()
                          : null,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Baixar modelo XLSX'),
                    ),
                    OutlinedButton.icon(
                      onPressed: canEditSettings && !_working
                          ? () => _openTaxImportSheet()
                          : null,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Importar planilha'),
                    ),
                    OutlinedButton.icon(
                      onPressed: canEditSettings && !_working
                          ? () => _cleanRulesWithoutNcm()
                          : null,
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Limpar sem NCM'),
                    ),
                    FilledButton.icon(
                      onPressed: canEditSettings && !_working
                          ? () => _openRuleDialog()
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Nova regra'),
                    ),
                  ],
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
            _buildFiltersSection(),
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
                final scopedRules = _sortRulesForDisplay(
                  rules
                    .where(_matchesSelectedRepresentedScope)
                    .toList(growable: false),
                );
                final filteredRules = _applyFilters(scopedRules);
                _ensureVisibleRulesCountWithin(filteredRules);
                final totalContextRules = scopedRules.length;
                final missingNcmCount = scopedRules
                    .where((rule) => _normalizeNcmDigits(rule.ncm).isEmpty)
                    .length;
                final withNcmCount = totalContextRules - missingNcmCount;
                final missingCestCount = scopedRules
                    .where((rule) => _normalizeCestDigits(rule.cest).isEmpty)
                    .length;
                if (snapshot.connectionState == ConnectionState.waiting &&
                    filteredRules.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (scopedRules.isEmpty) {
                  return const Text(
                    'Nenhuma regra fiscal cadastrada ainda para este contexto (representada/global). Crie a primeira para começar a política tributária.',
                  );
                }

                if (filteredRules.isEmpty) {
                  return const Text(
                    'Nenhuma regra encontrada com os filtros informados.',
                  );
                }

                final totalRules = filteredRules.length;
                final visibleCount = _visibleRulesCount.clamp(
                  0,
                  totalRules,
                );
                final visibleRules = filteredRules
                    .take(visibleCount)
                    .toList(growable: false);
                final hasMore = visibleCount < totalRules;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ruleChip(
                          context,
                          'Total no contexto: $totalContextRules',
                        ),
                        _ruleChip(context, 'Com NCM: $withNcmCount'),
                        _ruleChip(context, 'Sem NCM: $missingNcmCount'),
                        _ruleChip(context, 'Sem CEST: $missingCestCount'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Exibindo $visibleCount de $totalRules regra(s) filtrada(s). Total no contexto: ${scopedRules.length}.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visibleRules.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final rule = visibleRules[index];
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
                                _ruleChip(context, _scopeChipLabel(rule)),
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
                                          rules: filteredRules,
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
                                        index < filteredRules.length - 1
                                      ? () => _moveRule(
                                        rules: filteredRules,
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
                    ),
                    if (hasMore)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: OutlinedButton.icon(
                          onPressed: _working
                              ? null
                              : () => _loadMoreRules(filteredRules),
                          icon: const Icon(Icons.expand_more),
                          label: Text(
                            'Carregar mais (${totalRules - visibleCount} restante(s))',
                          ),
                        ),
                      ),
                  ],
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

    if (rule.salePurpose != null) {
      parts.add('Finalidade: ${rule.salePurpose!.label}');
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

  Future<void> _downloadTaxTemplate() async {
    setState(() {
      _working = true;
    });

    try {
      final existingRules = await _repository.fetchAll(
        tenantId: widget.activeTenant.tenantId,
      );

      final rows = existingRules
          .map(
            (rule) => <String>[
              rule.status,
              _withFallback(rule.ncm, ''),
              _withFallback(rule.cest, ''),
              _withFallback(rule.ufOrigem, 'ANY'),
              _withFallback(rule.ufDestino, ''),
              _withFallback(rule.salePurpose?.value, ''),
              _withFallback(rule.stCalculationType, 'mva'),
              rule.stPriceForCalculation?.toString() ?? '',
              rule.stBaseReductionPercent?.toString() ?? '',
              rule.stBaseAmount?.toString() ?? '',
              rule.aliquotaDestino?.toString() ?? '',
              rule.aliquotaCredito?.toString() ?? '',
              rule.aliquotaDifal?.toString() ?? '',
              _withFallback(rule.cstCsosn, ''),
              rule.mvaIva?.toString() ?? '',
              _withFallback(rule.fiscalException, ''),
              rule.validFrom?.toIso8601String().substring(0, 10) ?? '',
              rule.validUntil?.toIso8601String().substring(0, 10) ?? '',
              rule.priority.toString(),
            ],
          )
          .toList(growable: false);

      final templateRows = rows.isEmpty
          ? const <List<String>>[
              <String>[
                'active',
                '0000.00.00',
                '00.000.00',
                'ANY',
                'SP',
                'revenda',
                'mva',
                '100.00',
                '0',
                '',
                '18',
                '12',
                '2',
                '060',
                '40',
                'REGRA EXEMPLO',
                '',
                '',
                '1',
              ],
            ]
          : rows;

      final bytes = TabularSpreadsheetService.buildXlsxWithSheets(
        sheets: <TabularSpreadsheetSheet>[
          TabularSpreadsheetSheet(
            sheetName: 'Tributacao',
            headers: const <String>[
              'Status',
              'NCM',
              'CEST',
              'UF origem',
              'UF destino',
              'Finalidade da venda',
              'Tipo ST',
              'Preco para calculo ST',
              'Reducao base ICMS ST',
              'Base calculo ICMS ST',
              'Aliquota destino',
              'Aliquota credito',
              'Aliquota DIFAL',
              'CST/CSOSN',
              'MVA',
              'Excecao fiscal',
              'Vigencia inicial',
              'Vigencia final',
              'Prioridade',
            ],
            rows: templateRows,
          ),
          const TabularSpreadsheetSheet(
            sheetName: 'Instrucoes',
            headers: <String>['Campo', 'Obrigatorio', 'Regra'],
            rows: <List<String>>[
              <String>[
                'NCM',
                'Sim',
                'Obrigatorio. Deve ter 8 digitos no formato 0000.00.00.',
              ],
              <String>[
                'CEST',
                'Opcional',
                'Quando informado, deve ter 7 digitos no formato 00.000.00.',
              ],
              <String>[
                'Status',
                'Nao',
                'Use active ou inactive. Vazio assume active.',
              ],
              <String>[
                'UF origem',
                'Opcional',
                'Use sigla UF (SP, RJ, MG...) ou ANY. Vazio usa ANY.',
              ],
              <String>['UF destino', 'Sim', 'Use sigla UF (SP, RJ, MG...).'],
              <String>[
                'Finalidade da venda',
                'Opcional',
                'Uso opcional para diferenciar regras por uso/consumo, revenda ou industrializacao.',
              ],
              <String>['Tipo ST', 'Sim', 'Aceito apenas MVA ou PMC.'],
              <String>[
                'Preco para calculo ST',
                'Opcional',
                'Numerico. Usado como preco base de referencia no calculo.',
              ],
              <String>[
                'MVA',
                'Condicional',
                'Obrigatorio quando Tipo ST = MVA.',
              ],
              <String>[
                'Reducao base ICMS ST',
                'Condicional',
                'Obrigatorio quando Tipo ST = MVA.',
              ],
              <String>[
                'Base calculo ICMS ST',
                'Condicional',
                'Obrigatorio quando Tipo ST = PMC.',
              ],
              <String>[
                'Aliquota destino',
                'Sim',
                'Percentual numerico. Ex.: 18 ou 18,5',
              ],
              <String>[
                'Aliquota credito',
                'Sim',
                'Percentual numerico. Ex.: 12 ou 12,0',
              ],
              <String>[
                'Aliquota DIFAL',
                'Opcional',
                'Percentual numerico. Ex.: 2 ou 2,5',
              ],
              <String>['CST/CSOSN', 'Opcional', 'Codigo fiscal da regra.'],
              <String>[
                'Excecao fiscal',
                'Opcional',
                'Texto livre para observacoes da regra.',
              ],
              <String>[
                'Vigencia inicial',
                'Opcional',
                'Data no formato AAAA-MM-DD ou DD/MM/AAAA.',
              ],
              <String>[
                'Vigencia final',
                'Opcional',
                'Data no formato AAAA-MM-DD ou DD/MM/AAAA.',
              ],
              <String>[
                'Prioridade',
                'Opcional',
                'Inteiro. Se vazio, o sistema gera automaticamente.',
              ],
            ],
          ),
        ],
      );

      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      await downloadFileBytes(
        bytes: bytes,
        fileName: 'modelo_tributacao_$stamp.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (error) {
      _showMessage(
        'Falha ao baixar modelo de tributacao: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _openTaxImportSheet() async {
    if (_selectedRepresentedCompanyId.isEmpty) {
      _showMessage(
        'Selecione uma representada ativa antes de importar regras fiscais.',
      );
      return;
    }

    PlatformFile? selectedFile;
    _TaxImportValidation? validation;
    var importing = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickFile() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const <String>['xlsx', 'xls', 'csv'],
                allowMultiple: false,
                withData: true,
              );
              final file = result?.files.isNotEmpty == true
                  ? result!.files.first
                  : null;
              if (file == null) {
                return;
              }

              setSheetState(() {
                selectedFile = file;
                validation = null;
              });
            }

            Future<void> validate() async {
              final file = selectedFile;
              if (file == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Selecione uma planilha primeiro.'),
                  ),
                );
                return;
              }

              final report = _validateTaxImportFile(file);
              setSheetState(() {
                validation = report;
              });
            }

            Future<void> importFile() async {
              final file = selectedFile;
              if (file == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Selecione uma planilha para importar.'),
                  ),
                );
                return;
              }

              final report = validation ?? _validateTaxImportFile(file);
              if (!report.ok) {
                setSheetState(() {
                  validation = report;
                });
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(report.message)));
                return;
              }

              setSheetState(() {
                importing = true;
              });

              setState(() {
                _working = true;
              });

              try {
                final importResult = await _importTaxRows(report.rows);
                if (!context.mounted) {
                  return;
                }

                Navigator.of(sheetContext).pop();
                final skipped = importResult.skipped;
                final skippedNoChange = importResult.skippedNoChange;
                if (skipped > 0) {
                  _showMessage(
                    'Importacao concluida: ${importResult.imported} importada(s), $skipped ignorada(s) ($skippedNoChange sem alteracao).',
                  );
                } else {
                  _showMessage(
                    'Importacao concluida com ${importResult.imported} regra(s) fiscal(is).',
                  );
                }
              } catch (error) {
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Falha ao importar tributacao: ${_extractErrorMessage(error)}',
                    ),
                  ),
                );
              } finally {
                if (context.mounted) {
                  setSheetState(() {
                    importing = false;
                  });
                }

                if (mounted) {
                  setState(() {
                    _working = false;
                  });
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Importar regras de tributacao',
                      style: Theme.of(sheetContext).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use o modelo XLSX para garantir os nomes de colunas e formatos.',
                    ),
                    const SizedBox(height: 12),
                    if (selectedFile != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(selectedFile!.name),
                        subtitle: Text(
                          '${(selectedFile!.size / 1024).toStringAsFixed(1)} KB',
                        ),
                      ),
                    if (validation != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          validation!.ok
                              ? Icons.verified_outlined
                              : Icons.error_outline,
                          color: validation!.ok ? Colors.green : Colors.red,
                        ),
                        title: Text(
                          validation!.ok
                              ? 'Validacao concluida'
                              : 'Validacao com erro',
                        ),
                        subtitle: Text(validation!.message),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: importing ? null : pickFile,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Selecionar planilha'),
                        ),
                        OutlinedButton.icon(
                          onPressed: importing ? null : validate,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('Validar estrutura'),
                        ),
                        FilledButton.icon(
                          onPressed: importing ? null : importFile,
                          icon: const Icon(
                            Icons.playlist_add_check_circle_outlined,
                          ),
                          label: Text(
                            importing ? 'Importando...' : 'Importar agora',
                          ),
                        ),
                        TextButton(
                          onPressed: importing
                              ? null
                              : () => Navigator.of(sheetContext).pop(),
                          child: const Text('Fechar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  _TaxImportValidation _validateTaxImportFile(PlatformFile file) {
    final parsed = TabularSpreadsheetService.parseFile(file);
    if (!parsed.ok) {
      return _TaxImportValidation(
        ok: false,
        message: parsed.message,
        rows: const <Map<String, String>>[],
      );
    }

    final headers = parsed.headers;
    final hasUfDestino =
        headers.contains('ufdestino') || headers.contains('uf_destino');
    if (!hasUfDestino) {
      return const _TaxImportValidation(
        ok: false,
        message: 'Cabecalho invalido. Campo obrigatorio: UF destino.',
        rows: <Map<String, String>>[],
      );
    }

    if (parsed.rows.isEmpty) {
      return const _TaxImportValidation(
        ok: false,
        message: 'Planilha sem linhas validas para importacao.',
        rows: <Map<String, String>>[],
      );
    }

    final missingUfDestinoLines = <int>[];
    final invalidNcmLines = <int>[];
    final invalidTypeLines = <int>[];
    final missingAliquotasLines = <int>[];
    final invalidByTypeLines = <int>[];

    for (var index = 0; index < parsed.rows.length; index++) {
      final row = parsed.rows[index];
      final line = index + 2;

      final ufDestino = _normalizeUfForStorage(
        _readTaxCell(row, const <String>[
          'ufdestino',
          'uf_destino',
          'uf destino',
        ]),
      );
      final rawNcm = _normalizeNcmDigits(
        _readTaxCell(row, const <String>['ncm']),
      );
      if (ufDestino.isEmpty) {
        missingUfDestinoLines.add(line);
      }
      if (rawNcm.isEmpty || !_isValidNcmDigits(rawNcm)) {
        invalidNcmLines.add(line);
      }

      final stTypeRaw = _readTaxCell(row, const <String>[
        'stcalculationtype',
        'st_calculation_type',
        'tipost',
        'tipo st',
      ]);
      final stType = _parseStTypeForImport(stTypeRaw);
      if (stType == null) {
        invalidTypeLines.add(line);
        continue;
      }

      final aliquotaDestino = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'aliquotadestino',
          'aliquota_destino',
          'aliquotast',
        ]),
      );
      final aliquotaCredito = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'aliquotacredito',
          'aliquota_credito',
          'aliquotaicms',
        ]),
      );
      if (aliquotaDestino == null || aliquotaCredito == null) {
        missingAliquotasLines.add(line);
      }

      final stBaseReductionPercent = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'stbasereductionpercent',
          'st_base_reduction_percent',
          'reducaobaseicmsst',
          'reducao base icms st',
        ]),
      );
      final stBaseAmount = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'stbaseamount',
          'st_base_amount',
          'basecalculoicmsst',
          'base calculo icms st',
        ]),
      );
      final mvaIva = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>['mvaiva', 'stmvapercent', 'mva']),
      );

      final hasRequiredByType = stType == 'mva'
          ? (mvaIva != null && stBaseReductionPercent != null)
          : stBaseAmount != null;
      if (!hasRequiredByType) {
        invalidByTypeLines.add(line);
      }
    }

    if (missingUfDestinoLines.isNotEmpty ||
      invalidNcmLines.isNotEmpty ||
        invalidTypeLines.isNotEmpty ||
        missingAliquotasLines.isNotEmpty ||
        invalidByTypeLines.isNotEmpty) {
      String sample(List<int> lines) {
        final values = lines.take(10).join(', ');
        return '$values${lines.length > 10 ? ' ...' : ''}';
      }

      final parts = <String>[];
      if (missingUfDestinoLines.isNotEmpty) {
        parts.add('UF destino ausente: ${sample(missingUfDestinoLines)}');
      }
      if (invalidNcmLines.isNotEmpty) {
        parts.add('NCM obrigatório/inválido: ${sample(invalidNcmLines)}');
      }
      if (invalidTypeLines.isNotEmpty) {
        parts.add('Tipo ST invalido: ${sample(invalidTypeLines)}');
      }
      if (missingAliquotasLines.isNotEmpty) {
        parts.add(
          'Aliquota destino/credito obrigatoria: ${sample(missingAliquotasLines)}',
        );
      }
      if (invalidByTypeLines.isNotEmpty) {
        parts.add(
          'Campos condicionais MVA/PMC invalidos: ${sample(invalidByTypeLines)}',
        );
      }

      return _TaxImportValidation(
        ok: false,
        message: 'Inconsistencias na planilha (${parts.join(' | ')}).',
        rows: parsed.rows,
      );
    }

    return _TaxImportValidation(
      ok: true,
      message: 'Arquivo valido com ${parsed.rows.length} linha(s).',
      rows: parsed.rows,
    );
  }

  Future<void> _cleanRulesWithoutNcm() async {
    final selectedRepresentedCompanyId = _selectedRepresentedCompanyId;
    if (selectedRepresentedCompanyId.isEmpty) {
      _showMessage(
        'Selecione uma representada ativa antes de limpar regras fiscais.',
      );
      return;
    }

    List<TaxRule> missingNcmRules;
    try {
      final allRules = await _repository.fetchAll(
        tenantId: widget.activeTenant.tenantId,
      );
      missingNcmRules = allRules
          .where(_matchesSelectedRepresentedScope)
          .where((rule) => _normalizeNcmDigits(rule.ncm).isEmpty)
          .toList(growable: false);
    } catch (error) {
      _showMessage(
        'Falha ao analisar regras sem NCM: ${_extractErrorMessage(error)}',
      );
      return;
    }

    if (missingNcmRules.isEmpty) {
      _showMessage('Nenhuma regra sem NCM encontrada neste contexto.');
      return;
    }

    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Limpar regras sem NCM'),
          content: Text(
            'Foram encontradas ${missingNcmRules.length} regra(s) sem NCM no contexto atual. Deseja excluir todas antes da nova importacao?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir todas'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _working = true;
    });

    var deleted = 0;
    try {
      for (final rule in missingNcmRules) {
        await _repository.delete(
          tenantId: widget.activeTenant.tenantId,
          id: rule.id,
        );
        deleted += 1;
      }

      _showMessage('Limpeza concluida: $deleted regra(s) sem NCM removida(s).');
    } catch (error) {
      _showMessage(
        'Falha ao limpar regras sem NCM: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<_TaxImportResult> _importTaxRows(
    List<Map<String, String>> rows,
  ) async {
    final selectedRepresentedCompanyId = _selectedRepresentedCompanyId;
    final existingRules = await _repository.fetchAll(
      tenantId: widget.activeTenant.tenantId,
    );
    final scopedExistingRules = existingRules
        .where((rule) {
          return (rule.representedCompanyId ?? '').trim() ==
              selectedRepresentedCompanyId;
        })
        .toList(growable: false);
    final existingById = <String, TaxRule>{
      for (final item in scopedExistingRules) item.id: item,
    };
    final existingFingerprints = <String>{
      for (final item in scopedExistingRules) _taxRuleFingerprintFromEntity(item),
    };
    var maxPriority = 0;
    for (final rule in scopedExistingRules) {
      if (rule.priority > maxPriority) {
        maxPriority = rule.priority;
      }
    }

    var imported = 0;
    var skipped = 0;
    var skippedNoChange = 0;
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final rawNcm = _normalizeNcmDigits(
        _readTaxCell(row, const <String>['ncm']),
      );
      final rawCest = _normalizeCestDigits(
        _readTaxCell(row, const <String>['cest']),
      );
      final ufDestino = _normalizeUfForStorage(
        _readTaxCell(row, const <String>[
          'ufdestino',
          'uf_destino',
          'uf destino',
        ]),
      );

      final hasUfDestinoHeader =
          row.containsKey('ufdestino') || row.containsKey('uf_destino');
      if (hasUfDestinoHeader && ufDestino.isEmpty) {
        skipped++;
        continue;
      }
      if (rawNcm.isEmpty) {
        skipped++;
        continue;
      }
      if (rawNcm.isNotEmpty && !_isValidNcmDigits(rawNcm)) {
        skipped++;
        continue;
      }
      if (rawCest.isNotEmpty && !_isValidCestDigits(rawCest)) {
        skipped++;
        continue;
      }

      final now = DateTime.now().toUtc();
      final sourceId = _readTaxCell(row, const <String>[
        'id',
        'ruleid',
        'rule_id',
        'id regra',
        'regraid',
        'codigo regra',
      ]);
      final id = sourceId.isEmpty
          ? FirebaseFirestore.instance.collection('tax_rules').doc().id
          : sourceId;
        final existing = existingById[id];

      final aliquotaDestino = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'aliquotadestino',
          'aliquota_destino',
          'aliquotast',
        ]),
      );
      final aliquotaCredito = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'aliquotacredito',
          'aliquota_credito',
          'aliquotaicms',
        ]),
      );

      final stTypeRaw = _readTaxCell(row, const <String>[
        'stcalculationtype',
        'st_calculation_type',
        'tipost',
        'tipo st',
      ]);
      final stType = _parseStTypeForImport(stTypeRaw);
      if (stType == null) {
        skipped++;
        continue;
      }

      final stPriceForCalculation = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'stpriceforcalculation',
          'st_price_for_calculation',
          'precoparacalculost',
          'preco para calculo st',
        ]),
      );
      final stBaseReductionPercent = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'stbasereductionpercent',
          'st_base_reduction_percent',
          'reducaobaseicmsst',
          'reducao base icms st',
        ]),
      );
      final stBaseAmount = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'stbaseamount',
          'st_base_amount',
          'basecalculoicmsst',
          'base calculo icms st',
        ]),
      );
      final mvaIva = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>['mvaiva', 'stmvapercent', 'mva']),
      );

      final hasRequiredByType = stType == 'mva'
          ? (mvaIva != null && stBaseReductionPercent != null)
          : stBaseAmount != null;
      if (!hasRequiredByType ||
          aliquotaDestino == null ||
          aliquotaCredito == null) {
        skipped++;
        continue;
      }

      final importedPriority = int.tryParse(
        _readTaxCell(row, const <String>['priority', 'prioridade']).trim(),
      );
      final priority =
          importedPriority ??
          existing?.priority ??
          (maxPriority + imported + 1);

      final entity = TaxRule(
        id: id,
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: selectedRepresentedCompanyId,
        status: _normalizeTaxStatus(
          _readTaxCell(row, const <String>['status']),
        ),
        ncm: rawNcm.isEmpty ? null : _formatNcmMasked(rawNcm),
        cest: rawCest.isEmpty ? null : _formatCestMasked(rawCest),
        fiscalException: _nullable(
          _readTaxCell(row, const <String>[
            'fiscalexception',
            'fiscal_exception',
            'excecaofiscal',
            'excecao fiscal',
          ]),
        ),
        stCalculationType: stType,
        stPriceForCalculation: stPriceForCalculation,
        stBaseReductionPercent: stBaseReductionPercent,
        stBaseAmount: stBaseAmount,
        aliquotaDestino: aliquotaDestino,
        aliquotaCredito: aliquotaCredito,
        grupoFiscalId: _nullable(
          _readTaxCell(row, const <String>['grupofiscalid', 'grupo_fiscal_id']),
        ),
        ufOrigem: _normalizeUfOrigem(
          _readTaxCell(row, const <String>[
            'uforigem',
            'uf_origem',
            'uf origem',
          ]),
          fallback: existing?.ufOrigem,
        ),
        ufDestino: _normalizeUfForStorage(
          _readTaxCell(row, const <String>[
            'ufdestino',
            'uf_destino',
            'uf destino',
          ]),
        ),
        salePurpose: _nullableSalePurpose(
          _readTaxCell(row, const <String>[
            'salepurpose',
            'sale_purpose',
            'finalidade da venda',
            'finalidade_venda',
            'finalidadevenda',
          ]),
        ),
        cstCsosn: _nullable(
          _readTaxCell(row, const <String>['cstcsosn', 'cst/csosn']),
        ),
        aliquotaIcms: aliquotaCredito,
        mvaIva: mvaIva,
        aliquotaSt: aliquotaDestino,
        aliquotaDifal: TabularSpreadsheetService.parseDecimal(
          _readTaxCell(row, const <String>[
            'aliquotadifal',
            'aliquota_difal',
            'aliquota difal',
          ]),
        ),
        priority: priority,
        validFrom: _toUtcStartOfDay(
          TabularSpreadsheetService.parseDate(
            _readTaxCell(row, const <String>['validfrom', 'vigenciainicial']),
          ),
        ),
        validUntil: _toUtcEndOfDay(
          TabularSpreadsheetService.parseDate(
            _readTaxCell(row, const <String>['validuntil', 'vigenciafinal']),
          ),
        ),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );

      final previousFingerprint =
          existing == null ? null : _taxRuleFingerprintFromEntity(existing);
      if (previousFingerprint != null) {
        existingFingerprints.remove(previousFingerprint);
      }
      final nextFingerprint = _taxRuleFingerprintFromEntity(entity);
      if (existingFingerprints.contains(nextFingerprint)) {
        skipped++;
        skippedNoChange++;
        if (previousFingerprint != null) {
          existingFingerprints.add(previousFingerprint);
        }
        continue;
      }

      if (previousFingerprint == nextFingerprint) {
        skipped++;
        skippedNoChange++;
        existingFingerprints.add(nextFingerprint);
        continue;
      }

      await _repository.save(entity);
      imported++;
      existingById[id] = entity;
      existingFingerprints.add(nextFingerprint);
    }

    return _TaxImportResult(
      imported: imported,
      skipped: skipped,
      skippedNoChange: skippedNoChange,
    );
  }

  String? _parseStTypeForImport(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized == 'mva') {
      return 'mva';
    }
    if (normalized == 'pmc') {
      return 'pmc';
    }
    return null;
  }

  String _readTaxCell(Map<String, String> row, List<String> aliases) {
    for (final alias in aliases) {
      final key = TabularSpreadsheetService.normalizeHeader(alias);
      final value = row[key]?.trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _normalizeTaxStatus(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'inactive' ||
        normalized == 'inativo' ||
        normalized == 'desativado') {
      return 'inactive';
    }
    return 'active';
  }

  String _normalizeUfOrigem(String raw, {String? fallback}) {
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty) {
      final fallbackValue = (fallback ?? '').trim().toUpperCase();
      return fallbackValue.isEmpty ? 'ANY' : fallbackValue;
    }

    if (normalized == 'ANY' || normalized == 'TODOS' || normalized == 'TODAS') {
      return 'ANY';
    }

    if (isBrazilState(normalized)) {
      return normalized;
    }

    return 'ANY';
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
        representedCompanyId: _resolveRuleScopeForSave(existing),
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
        salePurpose: draft.salePurpose,
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
      final selectedRepresentedCompanyId = _selectedRepresentedCompanyId;
      var maxPriority = 0;
      for (final item in existing) {
        if ((item.representedCompanyId ?? '').trim() !=
            selectedRepresentedCompanyId) {
          continue;
        }
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
      representedCompanyId: source.representedCompanyId,
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
      salePurpose: source.salePurpose,
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
    var selectedSalePurpose = existing?.salePurpose;
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
                                        child: _labeledSalePurposeDropdown(
                                          value: selectedSalePurpose,
                                          onChanged: (value) {
                                            setDialogState(() {
                                              selectedSalePurpose = value;
                                            });
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
                                        child: _labeledTextField(
                                          label: 'Exceção fiscal',
                                          controller: fiscalExceptionController,
                                        ),
                                      ),
                                      const Expanded(
                                        child: SizedBox.shrink(),
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
                                    salePurpose: selectedSalePurpose,
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

  Widget _labeledSalePurposeDropdown({
    required SalePurpose? value,
    required ValueChanged<SalePurpose?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Finalidade da venda (opcional)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<SalePurpose?>(
          initialValue: value,
          decoration: _dialogInputDecoration(),
          items: <DropdownMenuItem<SalePurpose?>>[
            const DropdownMenuItem<SalePurpose?>(
              value: null,
              child: Text('Todas'),
            ),
            ...SalePurpose.values.map(
              (item) => DropdownMenuItem<SalePurpose?>(
                value: item,
                child: Text(item.label),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  SalePurpose? _nullableSalePurpose(String? raw) {
    final normalized = (raw ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }

    final lowered = normalized.toLowerCase();
    if (lowered == 'todas' || lowered == 'todos' || lowered == 'any') {
      return null;
    }
    if (lowered == 'uso' || lowered == 'uso consumo' || lowered == 'uso/consumo') {
      return SalePurpose.usoConsumo;
    }
    if (lowered == 'revenda') {
      return SalePurpose.revenda;
    }
    if (lowered == 'industrializacao' || lowered == 'industrialização') {
      return SalePurpose.industrializacao;
    }

    return SalePurpose.fromValue(lowered.replaceAll(' ', '_').replaceAll('/', '_'));
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

  String _taxRuleFingerprintFromEntity(TaxRule rule) {
    String numberKey(double? value) {
      if (value == null) {
        return '';
      }
      return value.toStringAsFixed(6);
    }

    final scope = (rule.representedCompanyId ?? '').trim();
    final salePurpose = rule.salePurpose?.value.trim().toLowerCase() ?? 'any';
    final status = rule.status.trim().toLowerCase();
    final stType = (rule.stCalculationType ?? 'mva').trim().toLowerCase();
    final ncm = _normalizeNcmDigits(rule.ncm);
    final cest = _normalizeCestDigits(rule.cest);
    final ufOrigem = rule.ufOrigem.trim().toUpperCase();
    final ufDestino = rule.ufDestino.trim().toUpperCase();
    final fiscalException = (rule.fiscalException ?? '').trim().toLowerCase();
    final grupoFiscalId = (rule.grupoFiscalId ?? '').trim().toLowerCase();
    final cstCsosn = (rule.cstCsosn ?? '').trim().toLowerCase();
    final validFrom = rule.validFrom?.toUtc().toIso8601String() ?? '';
    final validUntil = rule.validUntil?.toUtc().toIso8601String() ?? '';

    return <String>[
      scope,
      status,
      ncm,
      cest,
      ufOrigem,
      ufDestino,
      salePurpose,
      stType,
      numberKey(rule.stPriceForCalculation),
      numberKey(rule.stBaseReductionPercent),
      numberKey(rule.stBaseAmount),
      numberKey(rule.aliquotaDestino),
      numberKey(rule.aliquotaCredito),
      numberKey(rule.aliquotaDifal),
      numberKey(rule.mvaIva),
      fiscalException,
      grupoFiscalId,
      cstCsosn,
      validFrom,
      validUntil,
    ].join('|');
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
    required this.salePurpose,
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
  final SalePurpose? salePurpose;
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

class _TaxImportValidation {
  const _TaxImportValidation({
    required this.ok,
    required this.message,
    required this.rows,
  });

  final bool ok;
  final String message;
  final List<Map<String, String>> rows;
}

class _TaxImportResult {
  const _TaxImportResult({
    required this.imported,
    required this.skipped,
    required this.skippedNoChange,
  });

  final int imported;
  final int skipped;
  final int skippedNoChange;
}
