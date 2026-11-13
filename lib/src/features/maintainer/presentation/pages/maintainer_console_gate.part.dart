part of 'maintainer_console_page.dart';

extension _MaintainerConsoleGatePart on _MaintainerConsolePageState {
  Widget _buildAccessGatedBody({required TextTheme textTheme}) {
    return FutureBuilder<MaintainerAccessDecision>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final decision = snapshot.data;
        if (decision == null || !decision.granted) {
          return _buildAccessDenied(
            context,
            reason:
                decision?.reason ??
                'Nao foi possivel validar acesso ao painel.',
          );
        }

        final canViewHome = decision.can(MaintainerPermission.viewHome);
        final canViewOverview = decision.can(MaintainerPermission.viewOverview);
        final canViewUsers = decision.can(MaintainerPermission.viewUsers);
        final canViewAudit = canViewUsers;
        final canManageImpersonation = decision.can(
          MaintainerPermission.manageImpersonation,
        );
        final canAccessStripeTab = _canAccessStripeTab(decision);

        final activeTab = _resolveActiveTabForPermissions(
          canViewUsers: canViewUsers,
          canViewAudit: canViewAudit,
          canManageImpersonation: canManageImpersonation,
          canAccessStripeTab: canAccessStripeTab,
        );

        if (!_hasAnyVisibleModule(
          canViewHome: canViewHome,
          canViewUsers: canViewUsers,
          canManageImpersonation: canManageImpersonation,
          canAccessStripeTab: canAccessStripeTab,
        )) {
          return _buildAccessDenied(
            context,
            reason:
                'Conta autenticada sem permissoes efetivas para exibir modulos do painel de mantenedor.',
          );
        }

        _overviewFuture ??= _overviewService.loadSnapshot();

        return _buildConsoleLayout(
          context: context,
          textTheme: textTheme,
          decision: decision,
          canViewOverview: canViewOverview,
          canViewUsers: canViewUsers,
          canViewAudit: canViewAudit,
          canManageImpersonation: canManageImpersonation,
          canAccessStripeTab: canAccessStripeTab,
          activeTab: activeTab,
        );
      },
    );
  }
}
