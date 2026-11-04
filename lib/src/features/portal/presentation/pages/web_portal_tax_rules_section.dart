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
  static final List<String> _ufFilterOptions = <String>[
    _selectUfOption,
    _anyUfOption,
    ...brazilStates,
  ];

  static const int _rulesPageSize = 50;
  static const Duration _textFilterDebounceDelay = Duration(milliseconds: 250);

  final FirestoreTaxRuleRepository _repository = FirestoreTaxRuleRepository(
    FirebaseFirestore.instance,
  );
  final WorkspaceProfileService _workspaceService = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );
  final TextEditingController _filterNcmController = TextEditingController();
  final TextEditingController _filterCestController = TextEditingController();

  bool _working = false;
  bool _updatingReforma = false;
  int _visibleRulesCount = _rulesPageSize;
  String _filterNcm = '';
  String _filterCest = '';
  String _filterUfDestino = _selectUfOption;
  int _textFilterDebounceToken = 0;

  Stream<bool>? _reformaStream;
  String _reformaStreamKey = '';

  String get _selectedRepresentedCompanyId {
    return (widget.selectedRepresentedCompanyId ?? '').trim();
  }

  // Evita recriar a subscricao do Firestore a cada build (ex.: quando
  // _updatingReforma alterna via setState), o que causava um "flicker"
  // visual do switch voltando para desativado logo apos ativar.
  Stream<bool> _watchReformaStream() {
    final key =
        '${widget.activeTenant.tenantId}|${widget.activeTenant.workspaceType}|$_selectedRepresentedCompanyId';
    if (_reformaStream == null || _reformaStreamKey != key) {
      _reformaStreamKey = key;
      _reformaStream = _workspaceService.watchReformaTributariaEnabled(
        tenantId: widget.activeTenant.tenantId,
        workspaceType: widget.activeTenant.workspaceType,
        representedCompanyId: _selectedRepresentedCompanyId,
      );
    }
    return _reformaStream!;
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
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colors.surfaceContainerHighest.withValues(alpha: 0.2),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextFormField(
              controller: _filterNcmController,
              decoration: _filterFieldDecoration(
                labelText: 'Filtrar NCM',
                hintText: 'Ex.: 8421',
                icon: Icons.tag_outlined,
              ),
            ),
          ),
          SizedBox(
            width: 220,
            child: TextFormField(
              controller: _filterCestController,
              decoration: _filterFieldDecoration(
                labelText: 'Filtrar CEST',
                hintText: 'Ex.: 21.117',
                icon: Icons.qr_code_2_outlined,
              ),
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: _filterUfDestino,
              isDense: true,
              decoration: _filterFieldDecoration(
                labelText: 'Filtrar UF destino',
                hintText: 'Ex.: SP',
                icon: Icons.map_outlined,
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
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                side: BorderSide(color: colors.primary.withValues(alpha: 0.35)),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _filterFieldDecoration({
    required String labelText,
    required String hintText,
    IconData? icon,
  }) {
    final colors = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      isDense: true,
      labelText: labelText,
      hintText: hintText,
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

    return StreamBuilder<bool>(
      stream: _watchReformaStream(),
      builder: (context, reformaSnapshot) {
        final reformaTributariaEnabled = reformaSnapshot.data ?? false;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderRow(
                  canEditSettings: canEditSettings,
                  reformaTributariaEnabled: reformaTributariaEnabled,
                  scopeLabel: scopeLabel,
                ),
                if (!canEditSettings) ...[
                  const SizedBox(height: 10),
                  _ownerOnlyReadOnlyNotice(
                    context,
                    message: 'Tributações ficam em modo somente leitura para este perfil. Apenas o owner pode alterar.',
                  ),
                ],
                const SizedBox(height: 10),
                _buildReformaStatusBanner(
                  context,
                  enabled: reformaTributariaEnabled,
                  canEdit: canEditSettings,
                  updating: _updatingReforma,
                  onChanged: _setReformaTributariaEnabled,
                ),
                const SizedBox(height: 14),
                _buildFiltersSection(),
                const SizedBox(height: 14),
                _buildRulesStreamSection(
                  canEditSettings: canEditSettings,
                  reformaTributariaEnabled: reformaTributariaEnabled,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow({
    required bool canEditSettings,
    required bool reformaTributariaEnabled,
    required String scopeLabel,
  }) {
    return Row(
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
                  ? () => _openRuleDialog(
                      reformaEnabled: reformaTributariaEnabled,
                    )
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('Nova regra'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRulesStreamSection({
    required bool canEditSettings,
    required bool reformaTributariaEnabled,
  }) {
    return StreamBuilder<List<TaxRule>>(
      stream: _repository.watchAll(tenantId: widget.activeTenant.tenantId),
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
          rules.where(_matchesSelectedRepresentedScope).toList(growable: false),
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
        final visibleCount = _visibleRulesCount.clamp(0, totalRules);
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
                _ruleChip(context, 'Total no contexto: $totalContextRules'),
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
                    contentPadding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
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
                        if ((rule.taxGroupId ?? '').trim().isNotEmpty)
                          _ruleChip(
                            context,
                            'Grupo tributario ${rule.taxGroupId!.trim()}',
                          ),
                        _ruleChip(
                          context,
                          _displayStType(rule.stCalculationType),
                        ),
                        _ruleChip(context, rule.isActive ? 'Ativa' : 'Inativa'),
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
                          onPressed: canEditSettings && !_working && index > 0
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
                              ? () => _openRuleDialog(
                                  existing: rule,
                                  reformaEnabled: reformaTributariaEnabled,
                                )
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
    );
  }

  Future<void> _setReformaTributariaEnabled(bool value) async {
    setState(() {
      _updatingReforma = true;
    });
    try {
      await _workspaceService.setReformaTributariaEnabled(
        tenantId: widget.activeTenant.tenantId,
        workspaceType: widget.activeTenant.workspaceType,
        representedCompanyId: _selectedRepresentedCompanyId,
        enabled: value,
      );
      _showMessage(
        value
            ? 'Reforma Tributária ativada: campos de IBS/CBS/IS aparecem na Matriz tributária.'
            : 'Reforma Tributária desativada: campos de IBS/CBS/IS ficam ocultos na Matriz tributária.',
      );
    } catch (error) {
      _showMessage(
        'Falha ao atualizar Reforma Tributária: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingReforma = false;
        });
      }
    }
  }

  Widget _buildReformaStatusBanner(
    BuildContext context, {
    required bool enabled,
    required bool canEdit,
    required bool updating,
    required ValueChanged<bool> onChanged,
  }) {
    final phase = TaxReformCalendar.currentPhase();
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: enabled
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : colors.surfaceContainerHighest.withValues(alpha: 0.25),
        border: Border.all(
          color: enabled
              ? colors.primary.withValues(alpha: 0.3)
              : colors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.auto_graph_outlined : Icons.lock_clock_outlined,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              enabled
                  ? 'Reforma Tributária (IBS/CBS/IS) ativada para este contexto. Fase atual: ${TaxReformCalendar.phaseLabel(phase)}.'
                  : 'Reforma Tributária (IBS/CBS/IS) desativada para este contexto. Ative aqui para liberar os campos na regra fiscal e na planilha. Fase atual: ${TaxReformCalendar.phaseLabel(phase)}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          if (updating)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(value: enabled, onChanged: canEdit ? onChanged : null),
        ],
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

    final taxGroupId = (rule.taxGroupId ?? '').trim();
    if (taxGroupId.isNotEmpty) {
      parts.add('Grupo tributario: $taxGroupId');
    }

    final hasReformaFields =
        rule.reformaAliquotaIbsEstadual != null ||
        rule.reformaAliquotaIbsMunicipal != null ||
        rule.reformaAliquotaReferenciaCbs != null ||
        rule.reformaAliquotaReferenciaIs != null;
    if (hasReformaFields) {
      parts.add(
        'Reforma (IBS UF ${_formatPercent(rule.reformaAliquotaIbsEstadual)} '
        '+ Mun ${_formatPercent(rule.reformaAliquotaIbsMunicipal)} '
        '(redução ${_formatPercent(rule.reformaPercentualReducaoIbs)}) / '
        'CBS ${_formatPercent(rule.reformaAliquotaReferenciaCbs)} '
        '(redução ${_formatPercent(rule.reformaPercentualReducaoCbs)}) / '
        'IS ${_formatPercent(rule.reformaAliquotaReferenciaIs)})',
      );
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
    return withFallback(value, fallback);
  }

  Future<void> _downloadTaxTemplate() async {
    setState(() {
      _working = true;
    });

    try {
      final existingRules = await _repository.fetchAll(
        tenantId: widget.activeTenant.tenantId,
      );

      final bytes = TaxRuleImportExportService.buildTemplateBytes(
        existingRules,
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
    TaxRuleImportValidation? validation;
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

              final report = TaxRuleImportExportService.validateImportFile(
                file,
              );
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

              final report =
                  validation ??
                  TaxRuleImportExportService.validateImportFile(file);
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
                final importResult =
                    await TaxRuleImportExportService.importRows(
                      rows: report.rows,
                      repository: _repository,
                      tenantId: widget.activeTenant.tenantId,
                      representedCompanyId: _selectedRepresentedCompanyId,
                    );
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

  Future<void> _openRuleDialog({
    TaxRule? existing,
    required bool reformaEnabled,
  }) async {
    final draft = await showTaxRuleFormDialog(
      context,
      existing: existing,
      reformaEnabled: reformaEnabled,
    );
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
        taxGroupId: _nullable(draft.taxGroupId),
        operationProfileKey: null,
        ufOrigem: _nullable(existing?.ufOrigem)?.toUpperCase() ?? 'ANY',
        ufDestino: _normalizeUfForStorage(draft.ufDestino),
        salePurpose: null,
        cstCsosn: _nullable(draft.cstCsosn),
        aliquotaIcms: _nullableDouble(draft.aliquotaCredito),
        mvaIva: _nullableDouble(draft.mvaIva),
        aliquotaSt: _nullableDouble(draft.aliquotaDestino),
        aliquotaDifal: _nullableDouble(draft.aliquotaDifal),
        aliquotaFcp: _nullableDouble(draft.aliquotaFcp),
        aliquotaFcpSt: _nullableDouble(draft.aliquotaFcpSt),
        aliquotaFcpDifal: _nullableDouble(draft.aliquotaFcpDifal),
        applicableBuyerTaxRegime: draft.applicableBuyerTaxRegime,
        stReductionAppliesToIcmsProprio: draft.stReductionAppliesToIcmsProprio,
        reformaAliquotaIbsEstadual: _nullableDouble(
          draft.reformaAliquotaIbsEstadual,
        ),
        reformaAliquotaIbsMunicipal: _nullableDouble(
          draft.reformaAliquotaIbsMunicipal,
        ),
        reformaPercentualReducaoIbs: _nullableDouble(
          draft.reformaPercentualReducaoIbs,
        ),
        reformaAliquotaReferenciaCbs: _nullableDouble(
          draft.reformaAliquotaReferenciaCbs,
        ),
        reformaPercentualReducaoCbs: _nullableDouble(
          draft.reformaPercentualReducaoCbs,
        ),
        reformaAliquotaReferenciaIs: _nullableDouble(
          draft.reformaAliquotaReferenciaIs,
        ),
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
      stReductionAppliesToIcmsProprio: source.stReductionAppliesToIcmsProprio,
      aliquotaDestino: source.aliquotaDestino,
      aliquotaCredito: source.aliquotaCredito,
      grupoFiscalId: source.grupoFiscalId,
      taxGroupId: source.taxGroupId,
      produtoId: source.produtoId,
      operationProfileKey: source.operationProfileKey,
      salePurpose: source.salePurpose,
      ufOrigem: source.ufOrigem,
      ufDestino: source.ufDestino,
      cstCsosn: source.cstCsosn,
      aliquotaIcms: source.aliquotaIcms,
      mvaIva: source.mvaIva,
      aliquotaSt: source.aliquotaSt,
      aliquotaDifal: source.aliquotaDifal,
      aliquotaFcp: source.aliquotaFcp,
      aliquotaFcpSt: source.aliquotaFcpSt,
      aliquotaFcpDifal: source.aliquotaFcpDifal,
      reformaAliquotaIbsEstadual: source.reformaAliquotaIbsEstadual,
      reformaAliquotaIbsMunicipal: source.reformaAliquotaIbsMunicipal,
      reformaPercentualReducaoIbs: source.reformaPercentualReducaoIbs,
      reformaAliquotaReferenciaCbs: source.reformaAliquotaReferenciaCbs,
      reformaPercentualReducaoCbs: source.reformaPercentualReducaoCbs,
      reformaAliquotaReferenciaIs: source.reformaAliquotaReferenciaIs,
      applicableBuyerTaxRegime: source.applicableBuyerTaxRegime,
      priority: priority,
      validFrom: source.validFrom,
      validUntil: source.validUntil,
      syncVersion: source.syncVersion,
      deletedAt: source.deletedAt,
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

  bool _isPermissionDeniedError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('permission-denied') ||
        text.contains('insufficient permissions');
  }

  String _normalizeUfForStorage(String? value) {
    return normalizeUfForStorage(value);
  }

  String _displayUf(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    if (normalized.isEmpty || normalized == 'ANY') {
      return 'Qualquer';
    }
    return normalized;
  }

  DateTime? _toUtcStartOfDay(DateTime? value) {
    return toUtcStartOfDay(value);
  }

  DateTime? _toUtcEndOfDay(DateTime? value) {
    return toUtcEndOfDay(value);
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
    return nullableTrimmed(value);
  }

  double? _nullableDouble(String? value) {
    return nullableDouble(value);
  }

  String _normalizeNcmDigits(String? value) {
    return normalizeNcmDigits(value);
  }

  String _normalizeCestDigits(String? value) {
    return normalizeCestDigits(value);
  }

  String _formatNcmMasked(String? value) {
    return formatNcmMasked(value);
  }

  String _formatCestMasked(String? value) {
    return formatCestMasked(value);
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
