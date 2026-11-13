part of 'maintainer_console_page.dart';

extension _MaintainerConsoleHomePart on _MaintainerConsolePageState {
  Widget _buildMainTabs({
    required bool canViewUsers,
    required bool canManageImpersonation,
    required bool canAccessStripeTab,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Tela inicial'),
          selected: _activeTab == _MaintainerConsoleTab.home,
          onSelected: (_) => _setActiveTab(_MaintainerConsoleTab.home),
        ),
        if (canViewUsers)
          ChoiceChip(
            label: const Text('Gestao de Billing'),
            selected: _activeTab == _MaintainerConsoleTab.billing,
            onSelected: (_) => _setActiveTab(_MaintainerConsoleTab.billing),
          ),
        if (canViewUsers)
          ChoiceChip(
            label: const Text('Gestao de cliente'),
            selected: _activeTab == _MaintainerConsoleTab.clients,
            onSelected: (_) => _setActiveTab(_MaintainerConsoleTab.clients),
          ),
        if (canViewUsers)
          ChoiceChip(
            label: const Text('Gestao de usuarios'),
            selected: _activeTab == _MaintainerConsoleTab.users,
            onSelected: (_) => _setActiveTab(_MaintainerConsoleTab.users),
          ),
        if (canViewUsers)
          ChoiceChip(
            label: const Text('Auditoria'),
            selected: _activeTab == _MaintainerConsoleTab.audit,
            onSelected: (_) => _setActiveTab(_MaintainerConsoleTab.audit),
          ),
        if (canManageImpersonation)
          ChoiceChip(
            label: const Text('Acesso assistido'),
            selected: _activeTab == _MaintainerConsoleTab.impersonation,
            onSelected: (_) =>
                _setActiveTab(_MaintainerConsoleTab.impersonation),
          ),
        if (canAccessStripeTab)
          ChoiceChip(
            label: const Text('Integracao Stripe'),
            selected: _activeTab == _MaintainerConsoleTab.stripe,
            onSelected: (_) => _setActiveTab(_MaintainerConsoleTab.stripe),
          ),
      ],
    );
  }

  Widget _buildAccessDenied(BuildContext context, {required String reason}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Acesso negado ao painel de mantenedor',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(reason),
                const SizedBox(height: 12),
                const Text(
                  'Solicite a um platform_admin a concessao do papel adequado e habilitacao explicita do console.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityCard(
    BuildContext context,
    MaintainerAccessDecision decision,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Controle de acesso',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text('Papel efetivo: ${decision.effectiveRole}'),
                const SizedBox(height: 6),
                Text('Validacao: ${decision.reason}'),
                const SizedBox(height: 10),
                const Text('Guard rails ativos:'),
                const SizedBox(height: 6),
                const Text('- Papel de plataforma (observer/operator/admin).'),
                const Text('- Conta ativa em usuarios/{uid}.'),
                const Text('- Chave de habilitacao maintainerConsoleEnabled.'),
                const Text(
                  '- Isolamento de modulo em lib/src/features/maintainer.',
                ),
                const SizedBox(height: 10),
                Text(
                  'Permissoes efetivas: ${_formatPermissions(decision.grantedPermissions)}',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Visao geral da plataforma',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: 'Atualizar metricas',
                      onPressed: _reloadOverview,
                      icon: const Icon(Icons.refresh_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<MaintainerOverviewSnapshot>(
                  future: _overviewFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }

                    final data = snapshot.data;
                    if (data == null) {
                      return const Text(
                        'Nao foi possivel carregar as metricas agora.',
                      );
                    }

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _metricTile('Tenants', data.totalTenants),
                        _metricTile('Tenants ativos', data.activeTenants),
                        _metricTile('Memberships', data.totalMemberships),
                        _metricTile(
                          'Memberships ativos',
                          data.activeMemberships,
                        ),
                        _metricTile('Convites pendentes', data.pendingInvites),
                        _metricTile(
                          'Solicitacoes pendentes',
                          data.pendingAccessRequests,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricTile(String label, int? value) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD8DEE7)),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 6),
          Text(
            value?.toString() ?? '--',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildRoadmapCard(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backlog inicial do console',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                const Text('• Diagnostico por tenant e por conta.'),
                const Text('• Auditoria de acoes criticas com filtros.'),
                const Text('• Acoes administrativas seguras com motivo.'),
                const Text(
                  '• Integracao de eventos de billing e lock de conta.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
