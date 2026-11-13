part of 'maintainer_console_page.dart';

extension _MaintainerConsoleBillingPart on _MaintainerConsolePageState {
  Widget _buildBillingManagementCard(
    BuildContext context,
    MaintainerAccessDecision decision,
  ) {
    final canViewUsers = decision.can(MaintainerPermission.viewUsers);
    final canManageUserBilling = decision.can(
      MaintainerPermission.manageUserBilling,
    );

    if (!canViewUsers) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Gestao de Billing indisponivel para esta conta.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Solicite permissao maintainer.view.users no cadastro de seguranca.',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestao de Billing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Visao consolidada por workspace, exibindo owner pagador e estado de billing do tenant.',
                ),
                const SizedBox(height: 6),
                Text(
                  canManageUserBilling
                      ? 'Acoes operacionais de billing por workspace com reflexo no tenant e integracao Stripe.'
                      : 'Perfil com acesso de leitura: sem permissao para ajustes de billing.',
                ),
                const SizedBox(height: 12),
                _buildBillingWorkspaceStreamSection(
                  canManageUserBilling: canManageUserBilling,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBillingWorkspaceStreamSection({
    required bool canManageUserBilling,
  }) {
    return StreamBuilder<List<MaintainerTenantBillingWorkspace>>(
      stream: _userAdminService.watchTenantBillingWorkspaces(),
      builder: (context, workspacesSnapshot) {
        if (workspacesSnapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }

        if (workspacesSnapshot.hasError) {
          return Text(
            'Falha ao carregar workspaces de billing: ${workspacesSnapshot.error}',
          );
        }

        final workspaces =
            workspacesSnapshot.data ??
            const <MaintainerTenantBillingWorkspace>[];
        if (workspaces.isEmpty) {
          return const Text('Nenhum workspace encontrado.');
        }

        return StreamBuilder<List<MaintainerUserTenantMembership>>(
          stream: _userAdminService.watchTenantMemberships(),
          builder: (context, membershipsSnapshot) {
            if (membershipsSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const LinearProgressIndicator(minHeight: 2);
            }

            if (membershipsSnapshot.hasError) {
              return Text(
                'Falha ao carregar memberships de billing: ${membershipsSnapshot.error}',
              );
            }

            final memberships =
                membershipsSnapshot.data ??
                const <MaintainerUserTenantMembership>[];

            return StreamBuilder<List<MaintainerUserAccount>>(
              stream: _userAdminService.watchUsers(limit: 1500),
              builder: (context, usersSnapshot) {
                if (usersSnapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator(minHeight: 2);
                }

                if (usersSnapshot.hasError) {
                  return Text(
                    'Falha ao carregar usuarios pagadores: ${usersSnapshot.error}',
                  );
                }

                final users =
                    usersSnapshot.data ?? const <MaintainerUserAccount>[];
                final rows = _buildBillingWorkspaceRows(
                  workspaces: workspaces,
                  memberships: memberships,
                  users: users,
                );
                final filteredRows = _filterBillingRows(rows);
                final statusOptions = _billingStatusOptions(rows);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBillingFiltersRow(statusOptions),
                    const SizedBox(height: 10),
                    Text(
                      'Workspaces: ${filteredRows.length} de ${rows.length} | Owners vinculados: ${rows.where((row) => row.ownerAccount != null).length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    if (filteredRows.isEmpty)
                      const Text('Nenhum workspace para os filtros atuais.')
                    else
                      _buildBillingTable(
                        filteredRows,
                        canManageUserBilling: canManageUserBilling,
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  List<_MaintainerBillingWorkspaceRow> _buildBillingWorkspaceRows({
    required List<MaintainerTenantBillingWorkspace> workspaces,
    required List<MaintainerUserTenantMembership> memberships,
    required List<MaintainerUserAccount> users,
  }) {
    final ownerMembershipByTenant = <String, MaintainerUserTenantMembership>{};
    for (final membership in memberships) {
      if (!membership.isActiveMembership) {
        continue;
      }
      if (membership.tenantId.isEmpty || membership.uid.isEmpty) {
        continue;
      }

      final normalizedRole = membership.role.trim().toLowerCase();
      if (normalizedRole != 'owner') {
        continue;
      }

      ownerMembershipByTenant.putIfAbsent(
        membership.tenantId,
        () => membership,
      );
    }

    final usersByUid = <String, MaintainerUserAccount>{
      for (final user in users) user.uid: user,
    };

    final rows = workspaces
        .map((workspace) {
          final ownerMembership = ownerMembershipByTenant[workspace.tenantId];
          final ownerAccount = ownerMembership == null
              ? null
              : usersByUid[ownerMembership.uid];
          return _MaintainerBillingWorkspaceRow(
            workspace: workspace,
            ownerMembership: ownerMembership,
            ownerAccount: ownerAccount,
          );
        })
        .toList(growable: false);

    rows.sort((a, b) {
      final nameOrder = a.workspace.tenantName.toLowerCase().compareTo(
        b.workspace.tenantName.toLowerCase(),
      );
      if (nameOrder != 0) {
        return nameOrder;
      }
      return a.workspace.tenantId.compareTo(b.workspace.tenantId);
    });

    return rows;
  }

  List<_MaintainerBillingWorkspaceRow> _filterBillingRows(
    List<_MaintainerBillingWorkspaceRow> rows,
  ) {
    final query = _billingSearchController.text.trim().toLowerCase();
    final selectedStatus = _billingStatusFilter.trim().toLowerCase();

    return rows
        .where((row) {
          if (selectedStatus.isNotEmpty &&
              row.workspace.normalizedBillingStatus != selectedStatus) {
            return false;
          }

          if (query.isEmpty) {
            return true;
          }

          final owner = row.ownerAccount;
          final ownerMembership = row.ownerMembership;
          final ownerName = (owner?.displayName ?? '').toLowerCase();
          final ownerEmail = (owner?.email ?? '').toLowerCase();
          final ownerUid = (owner?.uid ?? ownerMembership?.uid ?? '')
              .toLowerCase()
              .trim();
          final tenantName = row.workspace.tenantName.toLowerCase();
          final tenantId = row.workspace.tenantId.toLowerCase();
          final plan = row.workspace.billingPlanKey.toLowerCase();
          final status = row.workspace.billingStatus.toLowerCase();

          return ownerName.contains(query) ||
              ownerEmail.contains(query) ||
              ownerUid.contains(query) ||
              tenantName.contains(query) ||
              tenantId.contains(query) ||
              plan.contains(query) ||
              status.contains(query);
        })
        .toList(growable: false);
  }

  List<String> _billingStatusOptions(
    List<_MaintainerBillingWorkspaceRow> rows,
  ) {
    final statuses =
        rows
            .map((row) => row.workspace.normalizedBillingStatus)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    return statuses;
  }

  Widget _buildBillingFiltersRow(List<String> statusOptions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 860;
        final searchWidth = stacked
            ? constraints.maxWidth
            : math.min(420.0, constraints.maxWidth * 0.46);
        final statusWidth = stacked
            ? constraints.maxWidth
            : math.max(280.0, constraints.maxWidth - searchWidth - 12);
        final normalizedStatusFilter = _billingStatusFilter
            .trim()
            .toLowerCase();
        final selectedStatus = statusOptions.contains(normalizedStatusFilter)
            ? normalizedStatusFilter
            : '';

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: searchWidth,
              child: TextField(
                controller: _billingSearchController,
                onChanged: (_) => _resetBillingPageIndex(),
                decoration: const InputDecoration(
                  labelText: 'Buscar por workspace, owner, uid ou plano',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: statusWidth,
              child: DropdownButtonFormField<String>(
                initialValue: selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por status de billing',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Todos os status'),
                  ),
                  ...statusOptions.map(
                    (status) => DropdownMenuItem<String>(
                      value: status,
                      child: Text(_workspaceBillingStatusLabel(status)),
                    ),
                  ),
                ],
                onChanged: (value) => _applyBillingStatusFilter(value ?? ''),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBillingTable(
    List<_MaintainerBillingWorkspaceRow> rows, {
    required bool canManageUserBilling,
  }) {
    final pageModel = _buildBillingTablePageModel(rows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBillingTableTopControls(pageModel),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 1220),
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 64,
              columnSpacing: 14,
              horizontalMargin: 10,
              columns: const [
                DataColumn(label: Text('Workspace')),
                DataColumn(label: Text('Tipo')),
                DataColumn(label: Text('Owner pagador')),
                DataColumn(label: Text('Billing')),
                DataColumn(label: Text('Plano')),
                DataColumn(label: Text('Ciclo')),
                DataColumn(label: Text('Stripe')),
                DataColumn(label: Text('Atualizado')),
                DataColumn(label: Text('Acoes')),
              ],
              rows: pageModel.pageRows
                  .map(
                    (row) => _buildBillingDataRow(
                      row,
                      canManageUserBilling: canManageUserBilling,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }

  _MaintainerBillingTablePageModel _buildBillingTablePageModel(
    List<_MaintainerBillingWorkspaceRow> rows,
  ) {
    final totalRows = rows.length;
    final maxPageIndex = totalRows == 0
        ? 0
        : (totalRows - 1) ~/ _billingRowsPerPage;

    if (_billingPageIndex > maxPageIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _updateBillingTableState(() {
          _billingPageIndex = maxPageIndex;
        });
      });
    }

    final effectivePageIndex = _billingPageIndex > maxPageIndex
        ? maxPageIndex
        : _billingPageIndex;
    final firstRowIndex = effectivePageIndex * _billingRowsPerPage;
    final pageRows = rows
        .skip(firstRowIndex)
        .take(_billingRowsPerPage)
        .toList(growable: false);
    final pageStart = totalRows == 0 ? 0 : firstRowIndex + 1;
    final pageEnd = firstRowIndex + pageRows.length;

    return _MaintainerBillingTablePageModel(
      totalRows: totalRows,
      maxPageIndex: maxPageIndex,
      effectivePageIndex: effectivePageIndex,
      firstRowIndex: firstRowIndex,
      pageRows: pageRows,
      pageStart: pageStart,
      pageEnd: pageEnd,
      canGoPrevious: effectivePageIndex > 0,
      canGoNext: pageEnd < totalRows,
    );
  }

  Widget _buildBillingTableTopControls(
    _MaintainerBillingTablePageModel pageModel,
  ) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Linhas por pagina:'),
        DropdownButton<int>(
          value: _billingRowsPerPage,
          items: const [
            DropdownMenuItem(value: 10, child: Text('10')),
            DropdownMenuItem(value: 20, child: Text('20')),
            DropdownMenuItem(value: 50, child: Text('50')),
            DropdownMenuItem(value: 100, child: Text('100')),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            _updateBillingTableState(() {
              _billingRowsPerPage = value;
              _billingPageIndex = 0;
            });
          },
        ),
        Text(
          '${pageModel.pageStart}-${pageModel.pageEnd} de ${pageModel.totalRows}',
        ),
        IconButton.outlined(
          tooltip: 'Pagina anterior',
          onPressed: pageModel.canGoPrevious
              ? () {
                  _updateBillingTableState(() {
                    _billingPageIndex = math.max(
                      0,
                      pageModel.effectivePageIndex - 1,
                    );
                  });
                }
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton.outlined(
          tooltip: 'Proxima pagina',
          onPressed: pageModel.canGoNext
              ? () {
                  _updateBillingTableState(() {
                    _billingPageIndex = pageModel.effectivePageIndex + 1;
                  });
                }
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  DataRow _buildBillingDataRow(
    _MaintainerBillingWorkspaceRow row, {
    required bool canManageUserBilling,
  }) {
    final owner = row.ownerAccount;
    final ownerMembership = row.ownerMembership;
    final ownerName = (owner?.displayName ?? '').trim();
    final ownerEmail = (owner?.email ?? '').trim();
    final ownerUid = (owner?.uid ?? ownerMembership?.uid ?? '').trim();
    final ownerLabel = ownerEmail.isNotEmpty
        ? ownerEmail
        : ownerUid.isNotEmpty
        ? ownerUid
        : 'Owner nao encontrado';
    final ownerSubLabel = ownerName.isNotEmpty ? ownerName : '--';

    final stripeLabel = row.workspace.stripeCustomerId.isEmpty
        ? 'Nao vinculado'
        : 'Vinculado';
    final planLabel = row.workspace.billingPlanKey.isEmpty
        ? '--'
        : row.workspace.billingPlanKey;
    final cycleLabel = row.workspace.billingCycle.isEmpty
        ? '--'
        : row.workspace.billingCycle;

    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: row.workspace.tenantName,
                waitDuration: const Duration(milliseconds: 350),
                child: Text(
                  row.workspace.tenantName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                row.workspace.tenantId,
                style: const TextStyle(fontSize: 12, color: Color(0xFF576074)),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        DataCell(
          Text(_maintainerWorkspaceTypeLabel(row.workspace.workspaceType)),
        ),
        DataCell(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: ownerLabel,
                waitDuration: const Duration(milliseconds: 350),
                child: Text(ownerLabel, overflow: TextOverflow.ellipsis),
              ),
              Text(
                ownerSubLabel,
                style: const TextStyle(fontSize: 12, color: Color(0xFF576074)),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        DataCell(
          Text(_workspaceBillingStatusLabel(row.workspace.billingStatus)),
        ),
        DataCell(Text(planLabel)),
        DataCell(Text(cycleLabel)),
        DataCell(Text(stripeLabel)),
        DataCell(Text(_formatDateTime(row.workspace.billingUpdatedAt))),
        _buildBillingActionsDataCell(
          row,
          canManageUserBilling: canManageUserBilling,
        ),
      ],
    );
  }

  DataCell _buildBillingActionsDataCell(
    _MaintainerBillingWorkspaceRow row, {
    required bool canManageUserBilling,
  }) {
    if (!canManageUserBilling) {
      return const DataCell(Text('Somente leitura'));
    }

    final tenantId = row.workspace.tenantId.trim();
    if (tenantId.isEmpty) {
      return const DataCell(Text('Workspace invalido'));
    }

    if (row.ownerMembership == null) {
      return const DataCell(Text('Owner nao encontrado'));
    }

    final processing = _processingBillingTenantIds.contains(tenantId);
    if (processing) {
      return const DataCell(
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return DataCell(
      PopupMenuButton<_MaintainerBillingAction>(
        tooltip: 'Acoes de billing do workspace',
        onSelected: (action) => _onBillingWorkspaceActionSelected(row, action),
        itemBuilder: (_) => const [
          PopupMenuItem<_MaintainerBillingAction>(
            value: _MaintainerBillingAction.grant7days,
            child: Text('Liberar +7 dias'),
          ),
          PopupMenuItem<_MaintainerBillingAction>(
            value: _MaintainerBillingAction.grant30days,
            child: Text('Liberar +30 dias'),
          ),
          PopupMenuItem<_MaintainerBillingAction>(
            value: _MaintainerBillingAction.normalizeBilling,
            child: Text('Normalizar billing'),
          ),
          PopupMenuItem<_MaintainerBillingAction>(
            value: _MaintainerBillingAction.suspendBilling,
            child: Text('Suspender billing'),
          ),
          PopupMenuDivider(),
          PopupMenuItem<_MaintainerBillingAction>(
            value: _MaintainerBillingAction.requestCloseWorkspace,
            child: Text('Solicitar encerramento do workspace'),
          ),
          PopupMenuItem<_MaintainerBillingAction>(
            value: _MaintainerBillingAction.requestDeleteWorkspace,
            child: Text('Solicitar exclusao definitiva do workspace'),
          ),
        ],
        child: const Icon(Icons.more_horiz),
      ),
    );
  }

  Future<void> _onBillingWorkspaceActionSelected(
    _MaintainerBillingWorkspaceRow row,
    _MaintainerBillingAction action,
  ) async {
    final tenantId = row.workspace.tenantId.trim();
    if (tenantId.isEmpty) {
      return;
    }

    final actionName = switch (action) {
      _MaintainerBillingAction.grant7days => 'grant_7_days',
      _MaintainerBillingAction.grant30days => 'grant_30_days',
      _MaintainerBillingAction.normalizeBilling => 'normalize_billing',
      _MaintainerBillingAction.suspendBilling => 'suspend_billing',
      _MaintainerBillingAction.requestCloseWorkspace => 'close_workspace',
      _MaintainerBillingAction.requestDeleteWorkspace => 'delete_workspace',
    };

    final successPrefix = switch (action) {
      _MaintainerBillingAction.grant7days => 'Billing liberado por 7 dias',
      _MaintainerBillingAction.grant30days => 'Billing liberado por 30 dias',
      _MaintainerBillingAction.normalizeBilling => 'Billing normalizado',
      _MaintainerBillingAction.suspendBilling => 'Billing suspenso',
      _MaintainerBillingAction.requestCloseWorkspace =>
        'Solicitacao de encerramento registrada',
      _MaintainerBillingAction.requestDeleteWorkspace =>
        'Solicitacao de exclusao definitiva registrada',
    };

    if (action == _MaintainerBillingAction.requestCloseWorkspace ||
        action == _MaintainerBillingAction.requestDeleteWorkspace) {
      final expectedPhrase =
          action == _MaintainerBillingAction.requestDeleteWorkspace
          ? 'DELETAR WORKSPACE ${row.workspace.tenantId}'
          : 'ENCERRAR WORKSPACE ${row.workspace.tenantId}';
      final reason = await _openWorkspaceLifecycleReasonDialog(
        context,
        title: action == _MaintainerBillingAction.requestDeleteWorkspace
            ? 'Solicitar exclusao definitiva'
            : 'Solicitar encerramento',
        expectedPhrase: expectedPhrase,
        helperText: 'Digite exatamente a frase de confirmacao para registrar a solicitacao.',
      );
      if (reason == null) {
        return;
      }

      _markBillingTenantProcessing(tenantId);
      try {
        final ownerUid = row.ownerMembership?.uid.trim() ?? '';
        await _userAdminService.requestWorkspaceLifecycleAction(
          tenantId: tenantId,
          targetUid: ownerUid,
          actionType: actionName,
          reason: reason,
          actorUid: _currentActorUid(),
          actorEmail: _currentActorEmail(),
          actorLabel: _currentActorLabel(),
        );
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$successPrefix para ${row.workspace.tenantName}.'),
          ),
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao registrar solicitacao: $error')),
        );
      } finally {
        _unmarkBillingTenantProcessing(tenantId);
      }
      return;
    }

    _markBillingTenantProcessing(tenantId);
    try {
      final payload = await _billingIntegrationService.manageTenantBillingState(
        tenantId: tenantId,
        action: actionName,
        reason: 'maintainer_console',
      );
      if (!mounted) {
        return;
      }

      final currentBillingStatus =
          (payload['currentBillingStatus'] ?? payload['billingStatus'] ?? '')
              .toString()
              .trim();
      final statusLabel = _workspaceBillingStatusLabel(currentBillingStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$successPrefix em ${row.workspace.tenantName}. Status atual: $statusLabel.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao atualizar billing do workspace: $error'),
        ),
      );
    } finally {
      _unmarkBillingTenantProcessing(tenantId);
    }
  }

  Future<String?> _openWorkspaceLifecycleReasonDialog(
    BuildContext context, {
    required String title,
    required String expectedPhrase,
    required String helperText,
  }) async {
    final phraseController = TextEditingController();
    final reasonController = TextEditingController();

    try {
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(helperText),
                  const SizedBox(height: 8),
                  SelectableText(
                    expectedPhrase,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phraseController,
                    decoration: const InputDecoration(
                      labelText: 'Frase de confirmacao',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Motivo (obrigatorio)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final typedPhrase = phraseController.text.trim();
                  final reason = reasonController.text.trim();
                  if (typedPhrase != expectedPhrase) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Frase de confirmacao invalida.'),
                      ),
                    );
                    return;
                  }
                  if (reason.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Informe o motivo da solicitacao.'),
                      ),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(reason);
                },
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      );

      final normalized = (result ?? '').trim();
      return normalized.isEmpty ? null : normalized;
    } finally {
      phraseController.dispose();
      reasonController.dispose();
    }
  }

  String _maintainerWorkspaceTypeLabel(String rawType) {
    final normalized = rawType.trim().toLowerCase();
    switch (normalized) {
      case 'seller_solo_workspace':
        return 'Individual';
      case 'rep_workspace':
        return 'Representacoes';
      case 'brand_owner_workspace':
        return 'Enterprise';
      default:
        return normalized.isEmpty ? '--' : normalized;
    }
  }

  String _workspaceBillingStatusLabel(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    switch (normalized) {
      case 'active':
        return 'Ativo';
      case 'grace':
        return 'Em graca';
      case 'suspended':
        return 'Suspenso';
      case 'canceled':
        return 'Cancelado';
      case 'no_plan':
        return 'Sem plano';
      default:
        return normalized.isEmpty ? '--' : normalized;
    }
  }
}
