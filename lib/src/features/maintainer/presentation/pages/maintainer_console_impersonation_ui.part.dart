part of 'maintainer_console_page.dart';

extension _MaintainerConsoleImpersonationUiPart on _MaintainerConsolePageState {
  Widget _buildImpersonationCard(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _buildImpersonationMembershipsStream(context),
          ),
        ),
      ),
    );
  }

  Widget _buildImpersonationEmptyState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acesso assistido (impersonation segura)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Nenhum usuario cliente elegivel encontrado para o filtro atual.',
        ),
      ],
    );
  }

  Widget _buildImpersonationForm(
    BuildContext context, {
    required List<MaintainerUserAccount> filteredUsers,
    required Map<String, String> tenantNamesById,
    required _ImpersonationResolvedSelection resolvedSelection,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImpersonationFormHeader(context),
        const SizedBox(height: 12),
        _buildImpersonationSearchField(),
        const SizedBox(height: 12),
        _buildImpersonationUserDropdown(
          filteredUsers: filteredUsers,
          selectedUid: resolvedSelection.selectedUid,
        ),
        const SizedBox(height: 12),
        _buildImpersonationMembershipDropdown(
          memberships: resolvedSelection.normalizedMemberships,
          tenantNamesById: tenantNamesById,
          selectedMembershipId: resolvedSelection.selectedMembershipId,
        ),
        const SizedBox(height: 12),
        _buildImpersonationDurationDropdown(),
        const SizedBox(height: 12),
        _buildImpersonationReasonField(),
        const SizedBox(height: 12),
        _buildImpersonationLaunchRow(context, resolvedSelection),
        const SizedBox(height: 8),
        const Text(
          'Regras: sessao temporaria, motivo obrigatorio, auditoria completa e bloqueio de reuse apos consumo.',
        ),
      ],
    );
  }

  Widget _buildImpersonationFormHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acesso assistido (impersonation segura)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Crie uma sessao temporaria para reproduzir o contexto do cliente em uma nova janela, com motivo obrigatorio e trilha de auditoria.',
        ),
      ],
    );
  }

  Widget _buildImpersonationSearchField() {
    return TextField(
      controller: _impersonationTargetSearchController,
      onChanged: (_) => _updateImpersonationState(() {}),
      decoration: const InputDecoration(
        labelText: 'Buscar usuario cliente (nome, e-mail ou UID)',
        prefixIcon: Icon(Icons.search),
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _buildImpersonationUserDropdown({
    required List<MaintainerUserAccount> filteredUsers,
    required String selectedUid,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: selectedUid,
      decoration: const InputDecoration(
        labelText: 'Usuario cliente',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: filteredUsers
          .map(
            (user) => DropdownMenuItem<String>(
              value: user.uid,
              child: Text(
                _impersonationUserLabel(user),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: _impersonationLaunching
          ? null
          : (value) {
              if (value == null) {
                return;
              }
              _updateImpersonationState(() {
                _impersonationSelectedUid = value;
                _impersonationSelectedMembershipId = null;
              });
            },
    );
  }

  Widget _buildImpersonationMembershipDropdown({
    required List<MaintainerUserTenantMembership> memberships,
    required Map<String, String> tenantNamesById,
    required String? selectedMembershipId,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: selectedMembershipId,
      decoration: const InputDecoration(
        labelText: 'Workspace/Tenant alvo',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: memberships
          .map(
            (membership) => DropdownMenuItem<String>(
              value: membership.membershipId,
              child: Text(
                _tenantFilterLabel(membership.tenantId, tenantNamesById),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: _impersonationLaunching
          ? null
          : (value) {
              _updateImpersonationState(() {
                _impersonationSelectedMembershipId = value;
              });
            },
    );
  }

  Widget _buildImpersonationDurationDropdown() {
    return DropdownButtonFormField<int>(
      initialValue: _impersonationDurationMinutes,
      decoration: const InputDecoration(
        labelText: 'Duracao da sessao',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: const [10, 15, 30]
          .map(
            (minutes) => DropdownMenuItem<int>(
              value: minutes,
              child: Text('$minutes minutos'),
            ),
          )
          .toList(growable: false),
      onChanged: _impersonationLaunching
          ? null
          : (value) {
              if (value == null) {
                return;
              }
              _updateImpersonationState(() {
                _impersonationDurationMinutes = value;
              });
            },
    );
  }

  Widget _buildImpersonationReasonField() {
    return TextField(
      controller: _impersonationReasonController,
      minLines: 2,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: 'Motivo (obrigatorio)',
        hintText:
            'Descreva o incidente/suporte que justifica o acesso assistido.',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildImpersonationLaunchRow(
    BuildContext context,
    _ImpersonationResolvedSelection resolvedSelection,
  ) {
    return Row(
      children: [
        FilledButton.icon(
          onPressed:
              _impersonationLaunching ||
                  resolvedSelection.selectedMembership == null
              ? null
              : () => _startImpersonationSession(
                  selectedUser: resolvedSelection.selectedUser,
                  selectedMembership: resolvedSelection.selectedMembership!,
                ),
          icon: const Icon(Icons.open_in_new_outlined),
          label: Text(
            _impersonationLaunching ? 'Abrindo...' : 'Iniciar sessao assistida',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _impersonationLaunchStatus,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: const Color(0xFF576074)),
          ),
        ),
      ],
    );
  }

  String _impersonationUserLabel(MaintainerUserAccount user) {
    final name = user.displayName.trim();
    final email = user.email.trim();
    final uid = user.uid.trim();
    if (name.isNotEmpty && email.isNotEmpty) {
      return '$name <$email> [$uid]';
    }
    if (email.isNotEmpty) {
      return '$email [$uid]';
    }
    if (name.isNotEmpty) {
      return '$name [$uid]';
    }
    return uid;
  }
}
