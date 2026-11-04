part of 'web_portal_page.dart';

class _PortalLandingSection extends StatelessWidget {
  const _PortalLandingSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isWide = MediaQuery.sizeOf(context).width >= 1100;

    final modules = [
      _PortalModule(
        title: 'Tabelas de preço',
        subtitle: 'Regras por marca, segmento, cliente, produto e tags.',
        icon: Icons.price_change_outlined,
      ),
      _PortalModule(
        title: 'Políticas comerciais',
        subtitle: 'Limites, excecoes, descontos, acrescimos e travas.',
        icon: Icons.policy_outlined,
      ),
      _PortalModule(
        title: 'ERP e integrações',
        subtitle: 'Parâmetros de conector, mapeamento e status.',
        icon: Icons.integration_instructions_outlined,
      ),
      _PortalModule(
        title: 'Convites e memberships',
        subtitle: 'Onboarding, aprovações e auditoria de acesso.',
        icon: Icons.badge_outlined,
      ),
      _PortalModule(
        title: 'Auditoria',
        subtitle: 'Eventos críticos, trilha de mudanças e suporte.',
        icon: Icons.fact_check_outlined,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Visão geral da conta', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'A conta SaaS controla a visão global; cada tenant navega isoladamente em seu próprio contexto.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _SummaryCard(
              title: 'Workspace em uso',
              value: activeTenant.tenantName,
            ),
            _SummaryCard(
              title: 'Seu acesso atual',
              value: _roleLabel(
                activeTenant.role,
                activeTenant.workspaceType,
                activeTenant.tenantName,
              ),
            ),
            _SummaryCard(
              title: 'Workspace atual',
              value: _workspaceTypeLabel(activeTenant.workspaceType),
            ),
            const _SummaryCard(title: 'Canal de acesso', value: 'Portal web'),
          ],
        ),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: isWide ? 3 : 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: isWide ? 1.8 : 2.6,
          children: modules
              .map((module) => _PortalModuleCard(module: module))
              .toList(),
        ),
      ],
    );
  }
}

class _BillingSection extends StatelessWidget {
  const _BillingSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return _SimpleCardSection(
      title: 'Billing',
      subtitle: 'Conta SaaS e faturamento do tenant ativo.',
      items: [
        'Plano atual do tenant: ${activeTenant.tenantName}',
        'Histórico de upgrade e downgrade',
        'Limites por plano e uso',
        'Cobrança por tenant, não por login',
      ],
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.activeTenant,
    required this.accountContractLock,
    required this.upgradingWorkspace,
    required this.onUpgradeToRep,
  });

  final TenantEntryOption activeTenant;
  final AccountContractLock accountContractLock;
  final bool upgradingWorkspace;
  final VoidCallback onUpgradeToRep;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canEditWorkspaceProfile = _canEditWorkspaceProfile(
      role: activeTenant.role,
      workspaceType: activeTenant.workspaceType,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Conta', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Configurações globais da sua conta e gestão de empresas no mesmo lugar.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: StreamBuilder<Map<String, dynamic>?>(
              stream: WorkspaceProfileService(FirebaseFirestore.instance)
                  .watchWorkspace(activeTenant.tenantId),
              builder: (context, snapshot) {
                final workspaceData =
                    snapshot.data ?? const <String, dynamic>{};

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
                                    'Dados do workspace',
                                    style: textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Informações base da conta e do workspace em uso.',
                                    style: textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (canEditWorkspaceProfile)
                              Tooltip(
                                message: 'Editar dados do workspace',
                                child: IconButton.outlined(
                                  onPressed: () => _openWorkspaceProfileEditor(
                                    context,
                                    activeTenant,
                                    workspaceData,
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _WorkspaceInfoGrid(
                          items: _buildWorkspaceInfoItems(
                            activeTenant: activeTenant,
                            accountContractLock: accountContractLock,
                            workspaceData: workspaceData,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gestão de workspaces', style: textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (accountContractLock ==
                        AccountContractLock.enterpriseOnly) ...[
                      const Text(
                        '• Esta Conta BrandOp controla apenas a propria empresa contratante.',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '• Não é permitido criar outras empresas ou operações paralelas neste login.',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '• Mudanças de plano/tipo devem ocorrer por migração controlada, sem criar novo workspace.',
                      ),
                    ] else ...[
                      const Text(
                        '• Esta conta está vinculada ao tipo de workspace atual para fins de billing e governança.',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '• O contexto Individual não adiciona usuários e não abre cadeia de representações.',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '• Para mudar de Individual para Representações (ou outro plano), o caminho e upgrade de plano.',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '• Não criamos workspace paralelo por esta tela para evitar divergência de billing.',
                      ),
                      if (activeTenant.workspaceType ==
                          'seller_solo_workspace') ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: upgradingWorkspace ? null : onUpgradeToRep,
                          icon: const Icon(Icons.upgrade_outlined),
                          label: Text(
                            upgradingWorkspace
                                ? 'Aplicando upgrade...'
                                : 'Upgrade para Representações',
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RepresentedCompaniesSection extends StatelessWidget {
  const _RepresentedCompaniesSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final supportsRepresentedCompanies =
        activeTenant.workspaceType == 'seller_solo_workspace' ||
        activeTenant.workspaceType == 'rep_workspace';
    final canManageRepresentedCompanies = _canManageRepresentedCompanies(
      role: activeTenant.role,
      workspaceType: activeTenant.workspaceType,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Representadas', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Cadastro e gestao das empresas representadas no workspace atual.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: StreamBuilder<Map<String, dynamic>?>(
                stream: WorkspaceProfileService(FirebaseFirestore.instance)
                    .watchWorkspace(activeTenant.tenantId),
                builder: (context, workspaceSnapshot) {
                  const headerColor = Color(0xFFF5F6F8);
                  const bodyColor = Colors.white;
                  const rowDividerColor = Color(0xFFE6E9EE);

                  final workspaceData =
                      workspaceSnapshot.data ?? const <String, dynamic>{};
                  final favoriteRepresentedCompanyId =
                      (workspaceData['favoriteRepresentedCompanyId'] ?? '')
                          .toString()
                          .trim();

                  return StreamBuilder<List<Map<String, Object?>>>(
                    stream: WorkspaceProfileService(FirebaseFirestore.instance)
                        .watchRepresentedCompanies(activeTenant.tenantId),
                    builder: (context, snapshot) {
                      final representedCompanies =
                          _representedCompaniesFromStorage(
                            snapshot.data ?? const <Map<String, Object?>>[],
                          );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            color: headerColor,
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Empresas representadas',
                                    style: textTheme.titleMedium,
                                  ),
                                ),
                                if (supportsRepresentedCompanies &&
                                    canManageRepresentedCompanies)
                                  FilledButton.icon(
                                    onPressed: () => _createRepresentedCompany(
                                      context,
                                      activeTenant,
                                      allCompanies: representedCompanies,
                                    ),
                                    icon: const Icon(
                                      Icons.add_business_outlined,
                                    ),
                                    label: const Text('Adicionar'),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            color: bodyColor,
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!supportsRepresentedCompanies) ...[
                                  const Text(
                                    'Disponivel apenas para workspaces Individual e Representações.',
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'No contexto Empresa (BrandOp), esta conta administra apenas a empresa contratante.',
                                  ),
                                ] else if (representedCompanies.isEmpty) ...[
                                  const Text(
                                    'Nenhuma representada cadastrada ainda.',
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Use esta lista para manter as empresas que você representa neste workspace.',
                                  ),
                                ] else ...[
                                  for (
                                    var index = 0;
                                    index < representedCompanies.length;
                                    index++
                                  ) ...[
                                    if (index > 0) ...[
                                      const SizedBox(height: 12),
                                      const Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: rowDividerColor,
                                      ),
                                      const SizedBox(height: 14),
                                    ],
                                    Builder(
                                      builder: (context) {
                                        final company =
                                            representedCompanies[index];
                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    company.nomeFantasia.isEmpty
                                                        ? 'Sem nome fantasia'
                                                        : company.nomeFantasia,
                                                    style: textTheme.titleSmall,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'CNPJ: ${company.cnpj.isEmpty ? 'Não informado' : company.cnpj}',
                                                  ),
                                                  if (company
                                                          .logradouro
                                                          .isNotEmpty ||
                                                      company.numero.isNotEmpty)
                                                    Text(
                                                      'Endereço: ${company.logradouro.isEmpty ? 'Não informado' : company.logradouro}${company.numero.isEmpty ? '' : ', ${company.numero}'}',
                                                    ),
                                                  Text(
                                                    'CEP: ${company.cep.isEmpty ? 'Não informado' : company.cep}',
                                                  ),
                                                  Text(
                                                    'Cidade/UF: ${company.cidade.isEmpty ? 'Não informado' : company.cidade}${company.uf.isEmpty ? '' : '/${company.uf}'}',
                                                  ),
                                                  Text(
                                                    _companyRelationshipSummary(
                                                      company: company,
                                                      allCompanies:
                                                          representedCompanies,
                                                    ),
                                                  ),
                                                  if (company
                                                      .segmento
                                                      .isNotEmpty)
                                                    Text(
                                                      'Segmento: ${company.segmento}',
                                                    ),
                                                  Text(
                                                    'Regime tributário: ${_taxRegimeLabel(company.taxRegime)}',
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (supportsRepresentedCompanies &&
                                                canManageRepresentedCompanies) ...[
                                              Tooltip(
                                                message:
                                                    company.id ==
                                                        favoriteRepresentedCompanyId
                                                    ? 'Representada favorita'
                                                    : 'Definir como favorita',
                                                child: IconButton.outlined(
                                                  onPressed:
                                                      company.id ==
                                                          favoriteRepresentedCompanyId
                                                      ? null
                                                      : () =>
                                                            _setFavoriteRepresentedCompany(
                                                              context,
                                                              activeTenant,
                                                              company,
                                                            ),
                                                  icon: Icon(
                                                    company.id ==
                                                            favoriteRepresentedCompanyId
                                                        ? Icons.star
                                                        : Icons.star_outline,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Tooltip(
                                                message: 'Editar',
                                                child: IconButton.outlined(
                                                  onPressed: () =>
                                                      _editRepresentedCompany(
                                                        context,
                                                        activeTenant,
                                                        company,
                                                        allCompanies:
                                                            representedCompanies,
                                                      ),
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Tooltip(
                                                message: 'Excluir',
                                                child: IconButton.outlined(
                                                  onPressed: () =>
                                                      _deleteRepresentedCompany(
                                                        context,
                                                        activeTenant,
                                                        company,
                                                      ),
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant, {
    required List<_RepresentedCompany> allCompanies,
  }) async {
    final payload = await _openRepresentedCompanyEditor(
      context,
      allCompanies: allCompanies,
    );
    if (payload == null || !context.mounted) {
      return;
    }

    try {
      await WorkspaceProfileService(FirebaseFirestore.instance)
          .upsertRepresentedCompany(
            tenantId: activeTenant.tenantId,
            values: payload,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Representada cadastrada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao cadastrar representada: $error')),
      );
    }
  }

  Future<void> _editRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant,
    _RepresentedCompany company, {
    required List<_RepresentedCompany> allCompanies,
  }) async {
    final payload = await _openRepresentedCompanyEditor(
      context,
      initial: company,
      allCompanies: allCompanies,
    );
    if (payload == null || !context.mounted) {
      return;
    }

    try {
      await WorkspaceProfileService(FirebaseFirestore.instance)
          .upsertRepresentedCompany(
            tenantId: activeTenant.tenantId,
            companyId: company.id,
            values: payload,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Representada atualizada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar representada: $error')),
      );
    }
  }

  Future<void> _deleteRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant,
    _RepresentedCompany company,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir representada'),
        content: Text(
          'Deseja excluir ${company.nomeFantasia.isEmpty ? 'esta representada' : company.nomeFantasia}?',
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
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await WorkspaceProfileService(FirebaseFirestore.instance)
          .deleteRepresentedCompany(
            tenantId: activeTenant.tenantId,
            companyId: company.id,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Representada excluida com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao excluir representada: $error')),
      );
    }
  }

  Future<void> _setFavoriteRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant,
    _RepresentedCompany company,
  ) async {
    try {
      await WorkspaceProfileService(FirebaseFirestore.instance)
          .setFavoriteRepresentedCompany(
            tenantId: activeTenant.tenantId,
            companyId: company.id,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Representada favorita: ${company.nomeFantasia.isEmpty ? company.id : company.nomeFantasia}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar favorita: $error')),
      );
    }
  }
}

class _PartnersSection extends StatelessWidget {
  const _PartnersSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final userLabel = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final identity = AppIdentity(
      tenantId: activeTenant.tenantId,
      userLabel: (userLabel == null || userLabel.isEmpty)
          ? 'Portal'
          : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace:
          activeTenant.workspaceType == 'seller_solo_workspace',
    );

    return ClientesPage(
      identity: identity,
      repository: FirestoreClienteRepository(FirebaseFirestore.instance),
      preCadastroRepository: FirestoreClientePreCadastroRepository(
        FirebaseFirestore.instance,
      ),
    );
  }
}

class _CustomersSection extends StatelessWidget {
  const _CustomersSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final userLabel = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final identity = AppIdentity(
      tenantId: activeTenant.tenantId,
      userLabel: (userLabel == null || userLabel.isEmpty)
          ? 'Portal'
          : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace:
          activeTenant.workspaceType == 'seller_solo_workspace',
    );

    return ClientesPage(
      identity: identity,
      repository: FirestoreClienteRepository(FirebaseFirestore.instance),
      preCadastroRepository: FirestoreClientePreCadastroRepository(
        FirebaseFirestore.instance,
      ),
    );
  }
}

class _TasksSection extends StatelessWidget {
  const _TasksSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return _SimpleCardSection(
      title: 'Tarefas',
      subtitle: 'Planejamento de visitas, follow-ups e rotas de campo por prioridade.',
      items: const [
        'Agenda semanal por vendedor',
        'Alertas de tarefas vencidas',
        'Roteiro de visitas e checkpoints',
      ],
    );
  }
}

class _TenantWorkspaceHubSection extends StatelessWidget {
  const _TenantWorkspaceHubSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return _SimpleCardSection(
      title: 'Menu da representada',
      subtitle: 'Use os menus horizontais para acessar detalhes, produtos, promoções, destaques, políticas e configurações da empresa ativa.',
      items: const [
        'Detalhes',
        'Produtos',
        'Promoções',
        'Destaques',
        'Políticas comerciais',
        'Configurações',
      ],
    );
  }
}

class _RepresentedDetailsSection extends StatelessWidget {
  const _RepresentedDetailsSection({
    required this.activeTenant,
    required this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: activeTenant.role,
      workspaceType: activeTenant.workspaceType,
    );
    final selectedId = (selectedRepresentedCompanyId ?? '').trim();
    if (selectedId.isEmpty) {
      return _SimpleCardSection(
        title: 'Informações de cadastro',
        subtitle: 'Selecione uma representada no topo para editar os detalhes.',
        items: const [
          'Razão social e nome fantasia',
          'CNPJ, contato e endereço',
          'Segmento e status',
        ],
      );
    }

    return StreamBuilder<List<Map<String, Object?>>>(
      stream: WorkspaceProfileService(FirebaseFirestore.instance)
          .watchRepresentedCompanies(activeTenant.tenantId),
      builder: (context, snapshot) {
        final representedCompanies = _representedCompaniesFromStorage(
          snapshot.data ?? const <Map<String, Object?>>[],
        );

        _RepresentedCompany? selected;
        for (final company in representedCompanies) {
          if (company.id == selectedId) {
            selected = company;
            break;
          }
        }

        if (selected == null) {
          return _SimpleCardSection(
            title: 'Informações de cadastro',
            subtitle:
                'A representada selecionada não foi encontrada na base atual.',
            items: const [
              'Valide a representada ativa no topo',
              'Atualize a lista de representadas',
            ],
          );
        }

        final selectedCompany = selected;
        final displayName = selectedCompany.nomeFantasia.isEmpty
            ? (activeRepresentedCompanyName ?? selectedCompany.id)
            : selectedCompany.nomeFantasia;
        final cityUf = selectedCompany.cidade.isEmpty
            ? 'Não informado'
            : '${selectedCompany.cidade}${selectedCompany.uf.isEmpty ? '' : '/${selectedCompany.uf}'}';

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    _RepresentedCompanyAvatar(
                      company: selectedCompany,
                      size: 56,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            selectedCompany.cnpj.trim().isEmpty
                                ? 'CNPJ não cadastrado'
                                : selectedCompany.cnpj,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: canEditSettings
                          ? () => _editRepresentedCompany(
                              context,
                              selectedCompany,
                              allCompanies: representedCompanies,
                            )
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(
                        canEditSettings ? 'Alterar' : 'Somente leitura',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (!canEditSettings) ...[
                      _ownerOnlyReadOnlyNotice(
                        context,
                        message: 'Apenas o owner pode alterar os dados da representada. Este perfil pode apenas consultar.',
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _profileBlock(
                            context,
                            title: 'Contato',
                            rows: [
                              _profileRow(
                                Icons.call_outlined,
                                selectedCompany.telefone,
                                'Telefone não cadastrado',
                              ),
                              _profileRow(
                                Icons.mail_outline,
                                selectedCompany.email,
                                'E-mail não cadastrado',
                              ),
                              _profileRow(
                                Icons.badge_outlined,
                                selectedCompany.contato,
                                'Contato não cadastrado',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _profileBlock(
                            context,
                            title: 'Cadastro',
                            rows: [
                              _profileLabelValue(
                                'Razão social',
                                selectedCompany.razaoSocial,
                              ),
                              _profileLabelValue(
                                'Nome fantasia',
                                selectedCompany.nomeFantasia,
                              ),
                              _profileLabelValue('CNPJ', selectedCompany.cnpj),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(color: Theme.of(context).dividerColor),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _profileBlock(
                            context,
                            title: 'Endereço',
                            rows: [
                              _profileLabelValue('CEP', selectedCompany.cep),
                              _profileLabelValue(
                                'Logradouro',
                                selectedCompany.logradouro,
                              ),
                              _profileLabelValue(
                                'Número',
                                selectedCompany.numero,
                              ),
                              _profileLabelValue('Cidade/UF', cityUf),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _profileBlock(
                            context,
                            title: 'Comercial',
                            rows: [
                              _profileLabelValue(
                                'Segmento',
                                selectedCompany.segmento,
                              ),
                              _profileLabelValue(
                                'Regime tributário',
                                _taxRegimeLabel(selectedCompany.taxRegime),
                              ),
                              _profileLabelValue(
                                'Relação empresarial',
                                _companyRelationshipSummary(
                                  company: selectedCompany,
                                  allCompanies: representedCompanies,
                                ),
                              ),
                              _profileLabelValue(
                                'Status',
                                selectedCompany.ativo ? 'Ativa' : 'Inativa',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _profileBlock(
    BuildContext context, {
    required String title,
    required List<Widget> rows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  Widget _profileRow(IconData icon, String value, String fallback) {
    final output = value.trim().isEmpty ? fallback : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(output)),
        ],
      ),
    );
  }

  Widget _profileLabelValue(String label, String value) {
    final output = value.trim().isEmpty ? 'Não cadastrado' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(output),
        ],
      ),
    );
  }

  Future<void> _editRepresentedCompany(
    BuildContext context,
    _RepresentedCompany company, {
    required List<_RepresentedCompany> allCompanies,
  }) async {
    final payload = await _openRepresentedCompanyEditor(
      context,
      initial: company,
      allCompanies: allCompanies,
    );
    if (payload == null || !context.mounted) {
      return;
    }

    try {
      await WorkspaceProfileService(FirebaseFirestore.instance)
          .upsertRepresentedCompany(
            tenantId: activeTenant.tenantId,
            companyId: company.id,
            values: payload,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Representada atualizada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar representada: $error')),
      );
    }
  }
}

String _companyRelationshipSummary({
  required _RepresentedCompany company,
  required List<_RepresentedCompany> allCompanies,
}) {
  final parentId = company.parentCompanyId.trim();
  if (parentId.isNotEmpty) {
    final parentName = _representedCompanyNameById(
      companyId: parentId,
      allCompanies: allCompanies,
    );
    return 'Filial vinculada à matriz: $parentName';
  }

  var branchCount = 0;
  for (final candidate in allCompanies) {
    if (candidate.parentCompanyId.trim() == company.id) {
      branchCount++;
    }
  }

  if (branchCount > 0) {
    return 'Matriz com $branchCount filial(is) vinculada(s)';
  }

  return 'Empresa sem vínculo de matriz/filial';
}

String _representedCompanyNameById({
  required String companyId,
  required List<_RepresentedCompany> allCompanies,
}) {
  for (final company in allCompanies) {
    if (company.id != companyId) {
      continue;
    }
    final display = company.nomeFantasia.trim();
    return display.isEmpty ? company.id : display;
  }
  return companyId;
}

class _RepresentedCompany {
  const _RepresentedCompany({
    required this.id,
    required this.nomeFantasia,
    required this.razaoSocial,
    required this.cnpj,
    required this.cep,
    required this.logradouro,
    required this.numero,
    required this.logoUrl,
    required this.contato,
    required this.telefone,
    required this.email,
    required this.cidade,
    required this.uf,
    required this.segmento,
    required this.taxRegime,
    required this.ativo,
    required this.parentCompanyId,
  });

  final String id;
  final String nomeFantasia;
  final String razaoSocial;
  final String cnpj;
  final String cep;
  final String logradouro;
  final String numero;
  final String logoUrl;
  final String contato;
  final String telefone;
  final String email;
  final String cidade;
  final String uf;
  final String segmento;
  final String taxRegime;
  final bool ativo;
  final String parentCompanyId;
}

List<_RepresentedCompany> _representedCompaniesFromStorage(
  List<Map<String, Object?>> storedCompanies,
) {
  final result = <_RepresentedCompany>[];

  for (final rawCompany in storedCompanies) {
    final company = _representedCompanyFromMap(rawCompany);
    if (company != null) {
      result.add(company);
    }
  }

  result.sort(
    (a, b) =>
        a.nomeFantasia.toLowerCase().compareTo(b.nomeFantasia.toLowerCase()),
  );
  return result;
}

_RepresentedCompany? _representedCompanyFromMap(Map<String, Object?> map) {
  final id = (map['companyId'] ?? map['id'] ?? '').toString().trim();
  if (id.isEmpty) {
    return null;
  }

  final nomeFantasia = (map['nomeFantasia'] ?? '').toString();
  final cidade = (map['cidade'] ?? '').toString();
  final uf = (map['uf'] ?? '').toString().toUpperCase();

  return _RepresentedCompany(
    id: id,
    nomeFantasia: nomeFantasia,
    razaoSocial: (map['razaoSocial'] ?? '').toString(),
    cnpj: (map['cnpj'] ?? '').toString(),
    cep: (map['cep'] ?? '').toString(),
    logradouro: (map['logradouro'] ?? '').toString(),
    numero: (map['numero'] ?? '').toString(),
    logoUrl: (map['logoUrl'] ?? '').toString(),
    contato: (map['contato'] ?? '').toString(),
    telefone: (map['telefone'] ?? '').toString(),
    email: (map['email'] ?? '').toString(),
    cidade: cidade,
    uf: uf,
    segmento: (map['segmento'] ?? '').toString(),
    taxRegime: _normalizeTaxRegimeValue(map['taxRegime']),
    ativo: map['ativo'] == true,
    parentCompanyId: (map['parentCompanyId'] ?? '').toString().trim(),
  );
}

class _RepresentedCompanyAvatar extends StatelessWidget {
  const _RepresentedCompanyAvatar({required this.company, this.size = 24});

  final _RepresentedCompany company;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logoUrl = company.logoUrl.trim();
    final trimmedName = company.nomeFantasia.trim();
    final initial = trimmedName.isEmpty
        ? 'R'
        : trimmedName.substring(0, 1).toUpperCase();
    final dataBytes = _decodeDataUrlImageBytes(logoUrl);
    ImageProvider<Object>? imageProvider;

    if (dataBytes != null) {
      imageProvider = MemoryImage(dataBytes);
    } else if (logoUrl.isNotEmpty) {
      imageProvider = NetworkImage(logoUrl);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        image: imageProvider == null
            ? null
            : DecorationImage(image: imageProvider, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: imageProvider == null
          ? Text(initial, style: TextStyle(fontSize: size * 0.42))
          : null,
    );
  }
}

Uint8List? _decodeDataUrlImageBytes(String value) {
  final normalized = value.trim();
  if (!normalized.startsWith('data:image/')) {
    return null;
  }

  final marker = ';base64,';
  final index = normalized.indexOf(marker);
  if (index == -1) {
    return null;
  }

  final encoded = normalized.substring(index + marker.length);
  try {
    return base64Decode(encoded);
  } catch (_) {
    return null;
  }
}
