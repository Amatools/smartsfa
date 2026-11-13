part of 'maintainer_console_page.dart';

extension _MaintainerConsoleImpersonationPart on _MaintainerConsolePageState {
  Widget _buildImpersonationMembershipsStream(BuildContext context) {
    return StreamBuilder<List<MaintainerUserTenantMembership>>(
      stream: _userAdminService.watchTenantMemberships(limit: 3000),
      builder: (context, membershipsSnapshot) {
        if (membershipsSnapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }

        if (membershipsSnapshot.hasError) {
          return Text(
            'Falha ao carregar memberships para acesso assistido: ${membershipsSnapshot.error}',
          );
        }

        final memberships =
            membershipsSnapshot.data ??
            const <MaintainerUserTenantMembership>[];
        final membershipsByUid = _buildActiveMembershipsByUid(memberships);
        return _buildImpersonationTenantNamesStream(
          context,
          membershipsByUid: membershipsByUid,
        );
      },
    );
  }

  Map<String, List<MaintainerUserTenantMembership>>
  _buildActiveMembershipsByUid(
    List<MaintainerUserTenantMembership> memberships,
  ) {
    final membershipsByUid = <String, List<MaintainerUserTenantMembership>>{};
    for (final membership in memberships) {
      if (!membership.isActiveMembership) {
        continue;
      }
      membershipsByUid
          .putIfAbsent(membership.uid, () => <MaintainerUserTenantMembership>[])
          .add(membership);
    }
    return membershipsByUid;
  }

  Widget _buildImpersonationTenantNamesStream(
    BuildContext context, {
    required Map<String, List<MaintainerUserTenantMembership>> membershipsByUid,
  }) {
    return StreamBuilder<Map<String, String>>(
      stream: _userAdminService.watchTenantNamesById(limit: 3000),
      builder: (context, tenantNamesSnapshot) {
        if (tenantNamesSnapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }

        if (tenantNamesSnapshot.hasError) {
          return Text(
            'Falha ao carregar nomes de tenants: ${tenantNamesSnapshot.error}',
          );
        }

        final tenantNamesById =
            tenantNamesSnapshot.data ?? const <String, String>{};
        return _buildImpersonationUsersStream(
          context,
          membershipsByUid: membershipsByUid,
          tenantNamesById: tenantNamesById,
        );
      },
    );
  }

  Widget _buildImpersonationUsersStream(
    BuildContext context, {
    required Map<String, List<MaintainerUserTenantMembership>> membershipsByUid,
    required Map<String, String> tenantNamesById,
  }) {
    return StreamBuilder<List<MaintainerUserAccount>>(
      stream: _userAdminService.watchUsers(limit: 500),
      builder: (context, usersSnapshot) {
        if (usersSnapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }

        if (usersSnapshot.hasError) {
          return Text(
            'Falha ao carregar usuarios para acesso assistido: ${usersSnapshot.error}',
          );
        }

        final users = usersSnapshot.data ?? const <MaintainerUserAccount>[];
        final filteredUsers = _buildFilteredImpersonationUsers(
          users: users,
          membershipsByUid: membershipsByUid,
        );

        if (filteredUsers.isEmpty) {
          return _buildImpersonationEmptyState(context);
        }

        final resolvedSelection = _resolveImpersonationSelection(
          filteredUsers: filteredUsers,
          membershipsByUid: membershipsByUid,
          tenantNamesById: tenantNamesById,
        );
        _syncImpersonationSelection(
          selectedUid: resolvedSelection.selectedUid,
          selectedMembershipId: resolvedSelection.selectedMembershipId,
        );

        return _buildImpersonationForm(
          context,
          filteredUsers: filteredUsers,
          tenantNamesById: tenantNamesById,
          resolvedSelection: resolvedSelection,
        );
      },
    );
  }

  List<MaintainerUserAccount> _buildFilteredImpersonationUsers({
    required List<MaintainerUserAccount> users,
    required Map<String, List<MaintainerUserTenantMembership>> membershipsByUid,
  }) {
    final targetUsers =
        users
            .where(
              (user) =>
                  !_isMaintainerAccount(user) &&
                  user.activeGlobal &&
                  (membershipsByUid[user.uid]?.isNotEmpty ?? false),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final nameOrder = _impersonationUserLabel(a)
                .compareTo(_impersonationUserLabel(b));
            if (nameOrder != 0) {
              return nameOrder;
            }
            return a.uid.compareTo(b.uid);
          });

    final searchQuery = _impersonationTargetSearchController.text
        .trim()
        .toLowerCase();
    return targetUsers
        .where((user) {
          if (searchQuery.isEmpty) {
            return true;
          }
          return user.uid.toLowerCase().contains(searchQuery) ||
              user.email.toLowerCase().contains(searchQuery) ||
              user.displayName.toLowerCase().contains(searchQuery);
        })
        .toList(growable: false);
  }

  _ImpersonationResolvedSelection _resolveImpersonationSelection({
    required List<MaintainerUserAccount> filteredUsers,
    required Map<String, List<MaintainerUserTenantMembership>> membershipsByUid,
    required Map<String, String> tenantNamesById,
  }) {
    final selectedUid =
        filteredUsers.any((user) => user.uid == _impersonationSelectedUid)
        ? _impersonationSelectedUid!
        : filteredUsers.first.uid;
    final selectedUser = filteredUsers.firstWhere(
      (user) => user.uid == selectedUid,
    );

    final selectedMemberships =
        membershipsByUid[selectedUser.uid] ??
        const <MaintainerUserTenantMembership>[];
    final normalizedMemberships =
        List<MaintainerUserTenantMembership>.from(selectedMemberships)
          ..sort((a, b) {
            final aLabel = _tenantFilterLabel(a.tenantId, tenantNamesById);
            final bLabel = _tenantFilterLabel(b.tenantId, tenantNamesById);
            final labelOrder = aLabel.compareTo(bLabel);
            if (labelOrder != 0) {
              return labelOrder;
            }
            return a.membershipId.compareTo(b.membershipId);
          });

    final selectedMembershipId =
        normalizedMemberships.any(
          (item) => item.membershipId == _impersonationSelectedMembershipId,
        )
        ? _impersonationSelectedMembershipId
        : (normalizedMemberships.isNotEmpty
              ? normalizedMemberships.first.membershipId
              : null);

    final selectedMembership = selectedMembershipId == null
        ? null
        : normalizedMemberships.firstWhere(
            (item) => item.membershipId == selectedMembershipId,
          );

    return _ImpersonationResolvedSelection(
      selectedUid: selectedUid,
      selectedUser: selectedUser,
      normalizedMemberships: normalizedMemberships,
      selectedMembershipId: selectedMembershipId,
      selectedMembership: selectedMembership,
    );
  }

  void _syncImpersonationSelection({
    required String selectedUid,
    required String? selectedMembershipId,
  }) {
    if ((_impersonationSelectedUid == selectedUid &&
            _impersonationSelectedMembershipId == selectedMembershipId) ||
        !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _updateImpersonationState(() {
        _impersonationSelectedUid = selectedUid;
        _impersonationSelectedMembershipId = selectedMembershipId;
      });
    });
  }

  Future<void> _startImpersonationSession({
    required MaintainerUserAccount selectedUser,
    required MaintainerUserTenantMembership selectedMembership,
  }) async {
    final reason = _impersonationReasonController.text.trim();
    if (reason.length < 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informe um motivo com pelo menos 8 caracteres.'),
          ),
        );
      }
      return;
    }

    _updateImpersonationState(() {
      _impersonationLaunching = true;
      _impersonationLaunchStatus = 'Criando sessao assistida...';
    });

    try {
      final actorUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      final session = await _impersonationService.createSession(
        targetUid: selectedUser.uid,
        targetTenantId: selectedMembership.tenantId,
        targetMembershipId: selectedMembership.membershipId,
        reason: reason,
        durationMinutes: _impersonationDurationMinutes,
        launchOrigin: kIsWeb ? Uri.base.origin : '',
      );

      if (actorUid.isNotEmpty && session.adminRestoreCustomToken.isNotEmpty) {
        MaintainerImpersonationService.cacheAdminRestoreSession(
          uid: actorUid,
          customToken: session.adminRestoreCustomToken,
        );
      }

      final opened = openUrlInNewTab(session.launchUrl);
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: session.launchUrl));
      }

      if (!mounted) {
        return;
      }

      final expiresAtLabel = _formatDateTime(session.expiresAt);
      _updateImpersonationState(() {
        _impersonationLaunchStatus = opened
            ? 'Sessao aberta em nova janela. Expira em $expiresAtLabel.'
            : 'Link copiado para a area de transferencia. Expira em $expiresAtLabel.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Sessao assistida iniciada com sucesso.'
                : 'Sessao criada. Link copiado para abrir manualmente.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _updateImpersonationState(() {
        _impersonationLaunchStatus = 'Falha ao iniciar sessao assistida.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao iniciar sessao assistida: $error')),
      );
    } finally {
      if (mounted) {
        _updateImpersonationState(() {
          _impersonationLaunching = false;
        });
      }
    }
  }
}
