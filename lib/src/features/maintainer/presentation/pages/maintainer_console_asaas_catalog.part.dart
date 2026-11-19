part of 'maintainer_console_page.dart';

extension _MaintainerConsoleAsaasCatalogPart on _MaintainerConsolePageState {
  DataCell _buildAsaasPlanTextCell(
    String rawValue, {
    double? width,
    bool ellipsis = true,
  }) {
    final value = rawValue.trim().isEmpty ? '--' : rawValue.trim();
    final cellText = Tooltip(
      message: value,
      child: Text(
        value,
        maxLines: 1,
        softWrap: false,
        overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.visible,
      ),
    );

    if (width == null) {
      return DataCell(cellText);
    }

    return DataCell(SizedBox(width: width, child: cellText));
  }

  Widget _buildAsaasInternalCatalogSection(
    BuildContext context, {
    required bool canManage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Catalogo interno Asaas',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        const Text(
          'Crie e mantenha planos comerciais internos para o fluxo Asaas. O backend usa este catalogo para mapear billingPlanKey sem depender do Stripe.',
        ),
        if (!canManage) ...[
          const SizedBox(height: 10),
          const Text('Perfil somente leitura para catalogo interno Asaas.'),
        ],
        const SizedBox(height: 12),
        StreamBuilder<List<MaintainerAsaasInternalPlan>>(
          stream: _billingIntegrationService.watchAsaasInternalPlans(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator(minHeight: 2);
            }
            if (snapshot.hasError) {
              return Text(
                'Falha ao carregar catalogo interno Asaas: ${snapshot.error}',
              );
            }

            final plans =
                snapshot.data ?? const <MaintainerAsaasInternalPlan>[];
            final grouped =
                <_StripePlanSection, List<MaintainerAsaasInternalPlan>>{};
            for (final plan in plans) {
              final section = _stripePlanSectionFromPlanKey(
                plan.billingPlanKey,
              );
              grouped
                  .putIfAbsent(section, () => <MaintainerAsaasInternalPlan>[])
                  .add(plan);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAsaasPlanSection(
                  context,
                  section: _StripePlanSection.individual,
                  plans:
                      grouped[_StripePlanSection.individual] ??
                      const <MaintainerAsaasInternalPlan>[],
                  availablePlans: plans,
                  canManage: canManage,
                ),
                const SizedBox(height: 12),
                _buildAsaasPlanSection(
                  context,
                  section: _StripePlanSection.representacoes,
                  plans:
                      grouped[_StripePlanSection.representacoes] ??
                      const <MaintainerAsaasInternalPlan>[],
                  availablePlans: plans,
                  canManage: canManage,
                ),
                const SizedBox(height: 12),
                _buildAsaasPlanSection(
                  context,
                  section: _StripePlanSection.enterprise,
                  plans:
                      grouped[_StripePlanSection.enterprise] ??
                      const <MaintainerAsaasInternalPlan>[],
                  availablePlans: plans,
                  canManage: canManage,
                ),
                if ((grouped[_StripePlanSection.outros] ??
                        const <MaintainerAsaasInternalPlan>[])
                    .isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildAsaasPlanSection(
                    context,
                    section: _StripePlanSection.outros,
                    plans:
                        grouped[_StripePlanSection.outros] ??
                        const <MaintainerAsaasInternalPlan>[],
                    availablePlans: plans,
                    canManage: canManage,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildAsaasPlanSection(
    BuildContext context, {
    required _StripePlanSection section,
    required List<MaintainerAsaasInternalPlan> plans,
    required List<MaintainerAsaasInternalPlan> availablePlans,
    required bool canManage,
  }) {
    final title = _stripePlanSectionLabel(section);
    final description = _stripePlanSectionDescription(section);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8DEE7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  OutlinedButton.icon(
                    onPressed: () => _openAsaasInternalPlanDialog(
                      initialSection: section,
                      availablePlans: availablePlans,
                    ),
                    icon: const Icon(Icons.add_link_outlined),
                    label: const Text('Cadastrar plano'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (plans.isEmpty)
              const Text('Nenhum plano cadastrado nesta seção.')
            else
              _HorizontalPlanTableScroller(
                child: DataTable(
                  horizontalMargin: 12,
                  columnSpacing: 20,
                  headingRowHeight: 44,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 56,
                  columns: const [
                    DataColumn(label: Text('Nome do plano')),
                    DataColumn(label: Text('Valor')),
                    DataColumn(label: Text('Acoes')),
                    DataColumn(label: Text('Plan key')),
                    DataColumn(label: Text('Tipo')),
                    DataColumn(label: Text('Seats base')),
                    DataColumn(label: Text('Addon seats')),
                    DataColumn(label: Text('Metrica excedente')),
                    DataColumn(label: Text('Plano base vinculado')),
                    DataColumn(label: Text('Currency')),
                    DataColumn(label: Text('Intervalo')),
                    DataColumn(label: Text('Ativo')),
                    DataColumn(label: Text('Atualizado')),
                  ],
                  rows: plans
                      .map(
                        (plan) => DataRow(
                          cells: [
                            _buildAsaasPlanTextCell(
                              plan.planDisplayName.isEmpty
                                  ? plan.billingPlanKey
                                  : plan.planDisplayName,
                              width: 220,
                            ),
                            _buildAsaasPlanTextCell(
                              plan.planDisplayAmount,
                              width: 200,
                            ),
                            DataCell(
                              SizedBox(
                                width: 142,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      message: 'Editar plano',
                                      child: IconButton(
                                        visualDensity: VisualDensity.compact,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 34,
                                              height: 34,
                                            ),
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 20,
                                        ),
                                        onPressed: canManage
                                            ? () =>
                                                  _openAsaasInternalPlanDialog(
                                                    existing: plan,
                                                    availablePlans:
                                                        availablePlans,
                                                  )
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: plan.active
                                          ? 'Ocultar para novas contratações'
                                          : 'Reativar para novas contratações',
                                      child: IconButton(
                                        visualDensity: VisualDensity.compact,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 34,
                                              height: 34,
                                            ),
                                        padding: EdgeInsets.zero,
                                        icon: Icon(
                                          plan.active
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          size: 20,
                                        ),
                                        onPressed: canManage
                                            ? () =>
                                                  _toggleAsaasInternalPlanActive(
                                                    plan,
                                                  )
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: 'Excluir plano',
                                      child: IconButton(
                                        visualDensity: VisualDensity.compact,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 34,
                                              height: 34,
                                            ),
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Color(0xFFB3261E),
                                          size: 20,
                                        ),
                                        onPressed: canManage
                                            ? () =>
                                                  _confirmDeleteAsaasInternalPlan(
                                                    plan,
                                                  )
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _buildAsaasPlanTextCell(
                              plan.billingPlanKey,
                              ellipsis: false,
                            ),
                            _buildAsaasPlanTextCell(
                              plan.mappingType,
                              width: 90,
                              ellipsis: false,
                            ),
                            _buildAsaasPlanTextCell(
                              '${plan.includedSeats}',
                              width: 96,
                              ellipsis: false,
                            ),
                            _buildAsaasPlanTextCell(
                              plan.seatAddonPlanKey,
                              ellipsis: false,
                            ),
                            _buildAsaasPlanTextCell(
                              plan.overageMetric,
                              width: 160,
                            ),
                            _buildAsaasPlanTextCell(
                              plan.linkedBasePlanKey,
                              ellipsis: false,
                            ),
                            _buildAsaasPlanTextCell(
                              plan.currency,
                              width: 90,
                              ellipsis: false,
                            ),
                            _buildAsaasPlanTextCell(
                              '${plan.interval} x${plan.intervalCount}',
                              width: 120,
                            ),
                            _buildAsaasPlanTextCell(
                              plan.active ? 'sim' : 'nao',
                              width: 70,
                              ellipsis: false,
                            ),
                            _buildAsaasPlanTextCell(
                              _formatDateTime(plan.updatedAt),
                              width: 120,
                            ),
                          ],
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAsaasInternalPlanDialog({
    MaintainerAsaasInternalPlan? existing,
    _StripePlanSection initialSection = _StripePlanSection.individual,
    List<MaintainerAsaasInternalPlan> availablePlans =
        const <MaintainerAsaasInternalPlan>[],
  }) async {
    final rawPlanSlugController = TextEditingController(
      text: existing?.billingPlanKey ?? '',
    );
    final planDisplayNameController = TextEditingController(
      text: existing?.planDisplayName ?? '',
    );
    final planDisplayAmountController = TextEditingController(
      text: existing?.planDisplayAmount ?? '',
    );
    final amountCentsController = TextEditingController(
      text: existing != null ? existing.amountCents.toString() : '',
    );
    final includedSeatsController = TextEditingController(
      text: existing != null ? existing.includedSeats.toString() : '0',
    );
    final currencyController = TextEditingController(
      text: existing?.currency ?? 'brl',
    );
    final linkedBasePlanKeyController = TextEditingController(
      text: existing?.linkedBasePlanKey ?? '',
    );

    var interval = existing?.interval ?? 'month';
    var intervalCount = existing?.intervalCount ?? 1;
    var mappingType = existing?.mappingType == 'overage' ? 'overage' : 'base';
    var overageMetric = existing?.overageMetric.isNotEmpty == true
        ? existing!.overageMetric
        : 'extra_usuario';
    var active = existing?.active ?? true;
    String? errorText;
    var saving = false;
    final creating = existing == null;
    final normalizedExistingPlanKey =
        existing?.billingPlanKey.trim().toLowerCase() ?? '';

    final basePlanOptionsByKey = <String, String>{};
    for (final plan in availablePlans) {
      final planKey = plan.billingPlanKey.trim().toLowerCase();
      if (planKey.isEmpty || planKey == normalizedExistingPlanKey) {
        continue;
      }
      if (plan.mappingType.trim().toLowerCase() != 'base') {
        continue;
      }

      final displayName = plan.planDisplayName.trim();
      basePlanOptionsByKey[planKey] = displayName.isEmpty
          ? planKey
          : '$displayName ($planKey)';
    }

    var selectedLinkedBasePlanKey = linkedBasePlanKeyController.text
        .trim()
        .toLowerCase();

    if (selectedLinkedBasePlanKey.isNotEmpty &&
        !basePlanOptionsByKey.containsKey(selectedLinkedBasePlanKey)) {
      basePlanOptionsByKey[selectedLinkedBasePlanKey] =
          selectedLinkedBasePlanKey;
    }

    final basePlanDropdownOptions = basePlanOptionsByKey.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (mappingType == 'overage') {
      if (selectedLinkedBasePlanKey.isEmpty &&
          basePlanDropdownOptions.isNotEmpty) {
        selectedLinkedBasePlanKey = basePlanDropdownOptions.first.key;
      }
      linkedBasePlanKeyController.text = selectedLinkedBasePlanKey;
    } else {
      selectedLinkedBasePlanKey = '';
      linkedBasePlanKeyController.clear();
    }

    final sectionForCreate = initialSection == _StripePlanSection.outros
        ? _StripePlanSection.outros
        : initialSection;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(
                existing == null
                    ? 'Novo plano interno Asaas'
                    : 'Editar plano interno Asaas',
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (creating) ...[
                        TextField(
                          controller: rawPlanSlugController,
                          onChanged: (_) => setLocalState(() {}),
                          decoration: InputDecoration(
                            labelText:
                                sectionForCreate == _StripePlanSection.outros
                                ? 'billingPlanKey (livre)'
                                : 'Slug do plano',
                            hintText:
                                sectionForCreate == _StripePlanSection.outros
                                ? 'Ex.: custom_special_plan'
                                : 'Ex.: base_mensal',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        if (sectionForCreate != _StripePlanSection.outros)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'billingPlanKey final: ${_buildBillingPlanKey(sectionForCreate, rawPlanSlugController.text)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ] else
                        TextField(
                          controller: rawPlanSlugController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'billingPlanKey',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: planDisplayNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nome do plano',
                          hintText: 'Ex.: Core Business Mensal',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: planDisplayAmountController,
                        decoration: const InputDecoration(
                          labelText: 'Valor para exibir (opcional)',
                          hintText: 'Ex.: R\$ 149,90 / mes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        value: mappingType == 'overage',
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Este plano e aditivo?'),
                        subtitle: Text(
                          mappingType == 'overage'
                              ? 'Aditivo: exige plano base vinculado e metrica de excedente.'
                              : 'Plano base: informe apenas os seats inclusos.',
                        ),
                        onChanged: saving
                            ? null
                            : (value) {
                                setLocalState(() {
                                  mappingType = value ? 'overage' : 'base';
                                  if (mappingType == 'overage') {
                                    overageMetric = 'extra_usuario';
                                    if (selectedLinkedBasePlanKey.isEmpty &&
                                        basePlanDropdownOptions.isNotEmpty) {
                                      selectedLinkedBasePlanKey =
                                          basePlanDropdownOptions.first.key;
                                    }
                                    linkedBasePlanKeyController.text =
                                        selectedLinkedBasePlanKey;
                                  } else {
                                    selectedLinkedBasePlanKey = '';
                                    linkedBasePlanKeyController.clear();
                                  }
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountCentsController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Valor em centavos',
                          hintText: 'Ex.: 14990',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: currencyController,
                        decoration: const InputDecoration(
                          labelText: 'Moeda',
                          hintText: 'brl',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (mappingType == 'base') ...[
                        TextField(
                          controller: includedSeatsController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Seats incluidos no plano',
                            hintText: 'Ex.: 1, 2, 3',
                            helperText: 'Usado como capacidade base da assinatura do tenant.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else ...[
                        DropdownButtonFormField<String>(
                          initialValue: overageMetric,
                          decoration: const InputDecoration(
                            labelText: 'Metrica de overage',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'extra_usuario',
                              child: Text('extra_usuario'),
                            ),
                          ],
                          onChanged: saving
                              ? null
                              : (value) {
                                  setLocalState(() {
                                    overageMetric = (value ?? 'extra_usuario')
                                        .trim()
                                        .toLowerCase();
                                  });
                                },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedLinkedBasePlanKey.isEmpty
                              ? null
                              : selectedLinkedBasePlanKey,
                          decoration: const InputDecoration(
                            labelText: 'Plano base vinculado',
                            border: OutlineInputBorder(),
                          ),
                          items: basePlanDropdownOptions
                              .map(
                                (option) => DropdownMenuItem<String>(
                                  value: option.key,
                                  child: Text(option.value),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: saving || basePlanDropdownOptions.isEmpty
                              ? null
                              : (value) {
                                  setLocalState(() {
                                    selectedLinkedBasePlanKey = (value ?? '')
                                        .trim()
                                        .toLowerCase();
                                    linkedBasePlanKeyController.text =
                                        selectedLinkedBasePlanKey;
                                  });
                                },
                        ),
                        if (basePlanDropdownOptions.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Cadastre ao menos um plano base para vincular este aditivo.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                      DropdownButtonFormField<String>(
                        initialValue: interval,
                        decoration: const InputDecoration(
                          labelText: 'Intervalo',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'month',
                            child: Text('month'),
                          ),
                          DropdownMenuItem(value: 'year', child: Text('year')),
                          DropdownMenuItem(value: 'week', child: Text('week')),
                          DropdownMenuItem(value: 'day', child: Text('day')),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                setLocalState(() {
                                  interval = (value ?? 'month')
                                      .trim()
                                      .toLowerCase();
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: intervalCount,
                        decoration: const InputDecoration(
                          labelText: 'Quantidade do intervalo',
                          border: OutlineInputBorder(),
                        ),
                        items: List<DropdownMenuItem<int>>.generate(12, (
                          index,
                        ) {
                          final value = index + 1;
                          return DropdownMenuItem<int>(
                            value: value,
                            child: Text(value.toString()),
                          );
                        }),
                        onChanged: saving
                            ? null
                            : (value) {
                                setLocalState(() {
                                  intervalCount = value ?? 1;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: active,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Plano ativo'),
                        onChanged: saving
                            ? null
                            : (value) {
                                setLocalState(() {
                                  active = value;
                                });
                              },
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setLocalState(() {
                            saving = true;
                            errorText = null;
                          });

                          try {
                            final planKey = existing != null
                                ? existing.billingPlanKey
                                : sectionForCreate == _StripePlanSection.outros
                                ? rawPlanSlugController.text.trim()
                                : _buildBillingPlanKey(
                                    sectionForCreate,
                                    rawPlanSlugController.text,
                                  );
                            if (planKey.isEmpty) {
                              throw StateError('billingPlanKey e obrigatorio.');
                            }
                            final amountCents =
                                int.tryParse(
                                  amountCentsController.text.trim(),
                                ) ??
                                0;
                            final includedSeats =
                                int.tryParse(
                                  includedSeatsController.text.trim(),
                                ) ??
                                0;

                            await _billingIntegrationService
                                .upsertAsaasInternalPlan(
                                  billingPlanKey: planKey,
                                  planDisplayName:
                                      planDisplayNameController.text,
                                  planDisplayAmount:
                                      planDisplayAmountController.text,
                                  amountCents: amountCents,
                                  currency: currencyController.text,
                                  interval: interval,
                                  intervalCount: intervalCount,
                                  mappingType: mappingType,
                                  overageMetric: mappingType == 'overage'
                                      ? overageMetric
                                      : '',
                                  includedSeats: mappingType == 'base'
                                      ? includedSeats
                                      : 0,
                                  seatAddonPlanKey: mappingType == 'base'
                                      ? (existing?.seatAddonPlanKey ?? '')
                                      : '',
                                  linkedBasePlanKey: mappingType == 'overage'
                                      ? linkedBasePlanKeyController.text
                                      : '',
                                  active: active,
                                  actorUid: _currentActorUid(),
                                );

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            setLocalState(() {
                              errorText =
                                  'Falha ao salvar plano interno Asaas: $error';
                              saving = false;
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    _disposeTextEditingControllersSafely([
      rawPlanSlugController,
      planDisplayNameController,
      planDisplayAmountController,
      amountCentsController,
      includedSeatsController,
      currencyController,
      linkedBasePlanKeyController,
    ]);

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Plano interno Asaas criado.'
                : 'Plano interno Asaas atualizado.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleAsaasInternalPlanActive(
    MaintainerAsaasInternalPlan plan,
  ) async {
    try {
      await _billingIntegrationService.setAsaasInternalPlanActive(
        planId: plan.planId,
        active: !plan.active,
        actorUid: _currentActorUid(),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !plan.active ? 'Plano Asaas ativado.' : 'Plano Asaas desativado.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar status do plano: $error')),
      );
    }
  }

  Future<void> _confirmDeleteAsaasInternalPlan(
    MaintainerAsaasInternalPlan plan,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir plano interno Asaas'),
          content: Text(
            'Confirma excluir o plano ${plan.billingPlanKey}? Essa acao nao pode ser desfeita.',
          ),
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

    try {
      await _billingIntegrationService.deleteAsaasInternalPlan(
        planId: plan.planId,
        actorUid: _currentActorUid(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plano interno Asaas excluido.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao excluir plano interno Asaas: $error')),
      );
    }
  }
}
