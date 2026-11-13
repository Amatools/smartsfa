part of 'maintainer_console_page.dart';

extension _MaintainerConsoleBuildPart on _MaintainerConsolePageState {
  Widget _buildConsoleLayout({
    required BuildContext context,
    required TextTheme textTheme,
    required MaintainerAccessDecision decision,
    required bool canViewOverview,
    required bool canViewUsers,
    required bool canViewAudit,
    required bool canManageImpersonation,
    required bool canAccessStripeTab,
    required _MaintainerConsoleTab activeTab,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Painel de mantenedor', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Acesso de plataforma validado por papel e cadastro de seguranca.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        _buildMainTabs(
          canViewUsers: canViewUsers,
          canManageImpersonation: canManageImpersonation,
          canAccessStripeTab: canAccessStripeTab,
        ),
        const SizedBox(height: 16),
        ..._buildActiveTabContent(
          context: context,
          decision: decision,
          canViewOverview: canViewOverview,
          canViewAudit: canViewAudit,
          canManageImpersonation: canManageImpersonation,
          canAccessStripeTab: canAccessStripeTab,
          activeTab: activeTab,
        ),
      ],
    );
  }

  List<Widget> _buildActiveTabContent({
    required BuildContext context,
    required MaintainerAccessDecision decision,
    required bool canViewOverview,
    required bool canViewAudit,
    required bool canManageImpersonation,
    required bool canAccessStripeTab,
    required _MaintainerConsoleTab activeTab,
  }) {
    if (activeTab == _MaintainerConsoleTab.home) {
      return [
        _buildSecurityCard(context, decision),
        if (canViewOverview) ...[
          const SizedBox(height: 16),
          _buildOverviewCard(context),
        ],
        const SizedBox(height: 16),
        _buildRoadmapCard(context),
      ];
    }

    if (activeTab == _MaintainerConsoleTab.billing) {
      return [_buildBillingManagementCard(context, decision)];
    }

    if (activeTab == _MaintainerConsoleTab.clients) {
      return [
        _buildUserAdminCard(
          context,
          decision,
          scope: _MaintainerUserScope.clients,
        ),
      ];
    }

    if (activeTab == _MaintainerConsoleTab.users) {
      return [
        _buildUserAdminCard(
          context,
          decision,
          scope: _MaintainerUserScope.platformUsers,
        ),
      ];
    }

    if (activeTab == _MaintainerConsoleTab.audit && canViewAudit) {
      return [_buildAuditCard(context)];
    }

    if (activeTab == _MaintainerConsoleTab.impersonation &&
        canManageImpersonation) {
      return [_buildImpersonationCard(context)];
    }

    if (activeTab == _MaintainerConsoleTab.stripe && canAccessStripeTab) {
      return [_buildStripeIntegrationCard(context)];
    }

    return const <Widget>[];
  }
}
