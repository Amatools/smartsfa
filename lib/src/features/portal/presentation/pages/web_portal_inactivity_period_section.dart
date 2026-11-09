part of 'web_portal_page.dart';

class _InactivityPeriodSection extends StatefulWidget {
  const _InactivityPeriodSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  State<_InactivityPeriodSection> createState() =>
      _InactivityPeriodSectionState();
}

class _InactivityPeriodSectionState extends State<_InactivityPeriodSection> {
  final TenantMembershipService _membershipService = TenantMembershipService(
    FirebaseFirestore.instance,
  );

  String? _workingMembershipId;

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
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Período de inatividade', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Defina janelas temporárias por membro para bloquear acesso ao workspace ativo durante o período informado. Escopo: $scopeLabel.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE3E6EA), width: 1),
            color: Colors.white,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                color: const Color(0xFFF5F6F8),
                child: Row(
                  children: [
                    const Icon(Icons.shield_moon_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Política de acesso por período',
                      style: textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.info_outline, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Owner pode configurar períodos para gerente, representante e vendedor. Membership em período ativo não aparece na seleção de workspace para o tenant.',
                        style: textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!canEditSettings) ...[
          const SizedBox(height: 10),
          _ownerOnlyReadOnlyNotice(
            context,
            message: 'Período de inatividade está em modo somente leitura para este perfil. Apenas o owner pode alterar.',
          ),
        ],
        const SizedBox(height: 14),
        StreamBuilder<List<TenantMembership>>(
          stream: _membershipService.watchMembershipsForTenant(
            widget.activeTenant.tenantId,
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'Falha ao carregar memberships: ${_extractErrorMessage(snapshot.error!)}',
              );
            }

            final allMemberships = snapshot.data ?? const <TenantMembership>[];
            final memberships = allMemberships
                .where((item) => item.role.trim().toLowerCase() != 'owner')
                .toList(growable: false);

            if (snapshot.connectionState == ConnectionState.waiting &&
                memberships.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (memberships.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE3E6EA), width: 1),
                  color: Colors.white,
                ),
                child: const Text(
                  'Nenhum membership elegível para inatividade.',
                ),
              );
            }

            final activeNowCount = memberships
                .where((item) => item.isInInactivityPeriod())
                .length;
            final scheduledCount = memberships
                .where(
                  (item) =>
                      !item.isInInactivityPeriod() &&
                      item.inactivityStartAt != null &&
                      item.inactivityEndAt != null,
                )
                .length;
            final availableCount =
                memberships.length - activeNowCount - scheduledCount;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildSummaryChip(
                      context,
                      label: 'Membros em inatividade',
                      value: '$activeNowCount',
                      color: colors.errorContainer,
                    ),
                    _buildSummaryChip(
                      context,
                      label: 'Períodos agendados',
                      value: '$scheduledCount',
                      color: colors.tertiaryContainer,
                    ),
                    _buildSummaryChip(
                      context,
                      label: 'Acesso liberado',
                      value: '$availableCount',
                      color: colors.surfaceContainerHighest,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFE3E6EA),
                      width: 1,
                    ),
                    color: Colors.white,
                  ),
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < memberships.length;
                        index++
                      ) ...[
                        _buildMembershipTile(
                          context,
                          membership: memberships[index],
                          canEditSettings: canEditSettings,
                        ),
                        if (index != memberships.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSummaryChip(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }

  Widget _buildMembershipTile(
    BuildContext context, {
    required TenantMembership membership,
    required bool canEditSettings,
  }) {
    final colors = Theme.of(context).colorScheme;
    final roleLabel = _roleLabel(membership.role);
    final memberLabel = _memberLabel(membership);
    final hasWindow =
        membership.inactivityStartAt != null &&
        membership.inactivityEndAt != null;
    final activeNow = membership.isInInactivityPeriod();
    final periodText = hasWindow
        ? '${_formatDate(membership.inactivityStartAt!)} até ${_formatDate(membership.inactivityEndAt!)}'
        : 'Sem período configurado';
    final reasonText = (membership.inactivityReason ?? '').trim();
    final isWorking = _workingMembershipId == membership.membershipId;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E6EA), width: 1),
        color: Colors.white,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memberLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildMetaChip(context, 'Perfil: $roleLabel'),
                          _buildMetaChip(context, periodText),
                        ],
                      ),
                      if (reasonText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Motivo: $reasonText',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: activeNow
                        ? colors.errorContainer
                        : hasWindow
                        ? colors.tertiaryContainer
                        : colors.surfaceContainerHighest,
                  ),
                  child: Text(
                    activeNow
                        ? 'Inativo agora'
                        : hasWindow
                        ? 'Agendado'
                        : 'Ativo',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
          if (canEditSettings)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F8),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: isWorking
                        ? null
                        : () => _configureInactivity(membership),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      hasWindow ? 'Editar período' : 'Definir período',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: isWorking || !hasWindow
                        ? null
                        : () => _clearInactivity(membership),
                    icon: const Icon(Icons.restore_outlined),
                    label: const Text('Remover período'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetaChip(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }

  Future<void> _configureInactivity(TenantMembership membership) async {
    final actorUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (actorUid.isEmpty) {
      _showMessage('Sessão inválida para salvar o período de inatividade.');
      return;
    }

    final draft = await _promptInactivityDraft(membership);
    if (draft == null) {
      return;
    }

    setState(() {
      _workingMembershipId = membership.membershipId;
    });

    try {
      await _membershipService.setMembershipInactivityPeriodByOwner(
        tenantId: widget.activeTenant.tenantId,
        membershipId: membership.membershipId,
        actorUid: actorUid,
        startAt: draft.startAt,
        endAt: draft.endAt,
        reason: draft.reason,
      );
      _showMessage('Período de inatividade salvo com sucesso.');
    } catch (error) {
      _showMessage(
        'Falha ao salvar período de inatividade: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _workingMembershipId = null;
        });
      }
    }
  }

  Future<void> _clearInactivity(TenantMembership membership) async {
    final actorUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (actorUid.isEmpty) {
      _showMessage('Sessão inválida para remover o período de inatividade.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 18,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE3E6EA), width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    color: const Color(0xFFF5F6F8),
                    child: Text(
                      'Remover período de inatividade',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Text(
                      'Deseja remover o período de inatividade de ${_memberLabel(membership)}?',
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFF5F6F8),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('Remover'),
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

    if (confirmed != true) {
      return;
    }

    setState(() {
      _workingMembershipId = membership.membershipId;
    });

    try {
      await _membershipService.clearMembershipInactivityPeriodByOwner(
        tenantId: widget.activeTenant.tenantId,
        membershipId: membership.membershipId,
        actorUid: actorUid,
      );
      _showMessage('Período de inatividade removido.');
    } catch (error) {
      _showMessage(
        'Falha ao remover período de inatividade: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _workingMembershipId = null;
        });
      }
    }
  }

  Future<_InactivityDraft?> _promptInactivityDraft(
    TenantMembership membership,
  ) async {
    final now = DateTime.now();
    var startAt = membership.inactivityStartAt ?? now;
    var endAt = membership.inactivityEndAt ?? now;
    final reasonController = TextEditingController(
      text: (membership.inactivityReason ?? '').trim(),
    );
    String? validationError;

    final result = await showDialog<_InactivityDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> selectStartDate() async {
              final selected = await showDatePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: startAt,
              );
              if (selected == null) {
                return;
              }
              setDialogState(() {
                startAt = selected;
                if (endAt.isBefore(startAt)) {
                  endAt = startAt;
                }
                validationError = null;
              });
            }

            Future<void> selectEndDate() async {
              final selected = await showDatePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: endAt,
              );
              if (selected == null) {
                return;
              }
              setDialogState(() {
                endAt = selected;
                validationError = null;
              });
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 18,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 680,
                  maxHeight: MediaQuery.of(context).size.height - 36,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFE3E6EA),
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        color: const Color(0xFFF5F6F8),
                        child: Text(
                          'Definir período de inatividade',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _memberLabel(membership),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: selectStartDate,
                                      icon: const Icon(Icons.event_outlined),
                                      label: Text(
                                        'Início: ${_formatDate(startAt)}',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: selectEndDate,
                                      icon: const Icon(
                                        Icons.event_available_outlined,
                                      ),
                                      label: Text('Fim: ${_formatDate(endAt)}'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: reasonController,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'Motivo (opcional)',
                                  border: OutlineInputBorder(),
                                  hintText:
                                      'Ex.: férias, desligamento temporário',
                                ),
                              ),
                              if (validationError != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  validationError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        color: const Color(0xFFF5F6F8),
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
                                if (endAt.isBefore(startAt)) {
                                  setDialogState(() {
                                    validationError = 'A data final deve ser igual ou posterior à inicial.';
                                  });
                                  return;
                                }

                                Navigator.of(dialogContext).pop(
                                  _InactivityDraft(
                                    startAt: startAt,
                                    endAt: endAt,
                                    reason: reasonController.text.trim(),
                                  ),
                                );
                              },
                              child: const Text('Salvar período'),
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

    reasonController.dispose();
    return result;
  }

  String _roleLabel(String role) {
    switch (role.trim().toLowerCase()) {
      case 'gerente':
        return 'Gerente';
      case 'representante':
        return 'Representante';
      case 'vendedor':
        return 'Vendedor';
      default:
        return role;
    }
  }

  String _memberLabel(TenantMembership membership) {
    final name = (membership.userName ?? '').trim();
    if (name.isNotEmpty) {
      return name;
    }
    final email = (membership.userEmail ?? '').trim();
    if (email.isNotEmpty) {
      return email;
    }
    return membership.uid;
  }

  String _formatDate(DateTime value) {
    final normalized = value.toLocal();
    final day = normalized.day.toString().padLeft(2, '0');
    final month = normalized.month.toString().padLeft(2, '0');
    final year = normalized.year.toString().padLeft(4, '0');
    return '$day/$month/$year';
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

class _InactivityDraft {
  const _InactivityDraft({
    required this.startAt,
    required this.endAt,
    required this.reason,
  });

  final DateTime startAt;
  final DateTime endAt;
  final String reason;
}
