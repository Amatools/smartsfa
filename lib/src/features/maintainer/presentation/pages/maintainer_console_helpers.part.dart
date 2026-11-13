part of 'maintainer_console_page.dart';

extension _MaintainerConsoleHelpersPart on _MaintainerConsolePageState {
  bool _isMaintainerAccount(MaintainerUserAccount user) {
    final normalizedMaintainerRole = user.maintainerRole
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_');
    final normalizedPlatformRole = user.platformRole.trim().toLowerCase();
    return normalizedPlatformRole == 'platform_admin' ||
        (normalizedMaintainerRole.isNotEmpty &&
            normalizedMaintainerRole != 'none') ||
        user.maintainerPermissions.isNotEmpty ||
        user.maintainerDeniedPermissions.isNotEmpty;
  }

  String _permissionLabel(String permission) {
    switch (permission) {
      case MaintainerPermission.viewHome:
        return 'Visualizar painel inicial';
      case MaintainerPermission.viewOverview:
        return 'Visualizar visao geral';
      case MaintainerPermission.viewUsers:
        return 'Visualizar gestao de usuarios';
      case MaintainerPermission.viewBillingIntegrations:
        return 'Visualizar integracoes de billing';
      case MaintainerPermission.manageUserStatus:
        return 'Ativar/Desativar contas';
      case MaintainerPermission.manageUserBilling:
        return 'Ajustar billing';
      case MaintainerPermission.manageUserCrud:
        return 'CRUD de usuarios';
      case MaintainerPermission.manageUserPermissions:
        return 'Editar matriz de permissoes';
      case MaintainerPermission.manageImpersonation:
        return 'Executar acesso assistido (impersonation)';
      case MaintainerPermission.manageBillingIntegrations:
        return 'Gerenciar configuracao de integracoes Stripe';
      default:
        return permission;
    }
  }

  List<MaintainerUserAccount> _filterUsers(
    List<MaintainerUserAccount> users,
    Map<String, Set<String>> tenantIdsByUid, {
    required String? selectedTenantId,
  }) {
    final query = _userSearchController.text.trim().toLowerCase();
    return users
        .where((user) {
          final userTenantIds = tenantIdsByUid[user.uid] ?? const <String>{};
          if (selectedTenantId != null &&
              !userTenantIds.contains(selectedTenantId)) {
            return false;
          }

          final email = user.email.toLowerCase();
          final name = user.displayName.toLowerCase();
          final uid = user.uid.toLowerCase();
          if (query.isEmpty) {
            return true;
          }
          return email.contains(query) ||
              name.contains(query) ||
              uid.contains(query);
        })
        .toList(growable: false);
  }

  String _formatTenantSummary(
    Set<String> tenantIds,
    Map<String, String> tenantNamesById,
  ) {
    if (tenantIds.isEmpty) {
      return '--';
    }

    final sorted = tenantIds.toList(growable: false)..sort();
    final labels = sorted
        .map((tenantId) => _tenantFilterLabel(tenantId, tenantNamesById))
        .toList(growable: false);
    if (labels.length <= 2) {
      return labels.join(', ');
    }
    final remaining = labels.length - 2;
    return '${labels[0]}, ${labels[1]} +$remaining';
  }

  String _tenantFilterLabel(
    String tenantId,
    Map<String, String> tenantNamesById,
  ) {
    final normalizedId = tenantId.trim();
    final name = (tenantNamesById[normalizedId] ?? normalizedId).trim();
    return '$name ($normalizedId)';
  }

  String _formatPermissions(Set<String> permissions) {
    if (permissions.isEmpty) {
      return 'nenhuma';
    }

    final labels = permissions.map(_permissionLabel).toList(growable: false)
      ..sort();

    return labels.join(' | ');
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '--';
    }
    final local = value.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  String _currentActorUid() {
    return (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
  }

  String _currentActorEmail() {
    return (FirebaseAuth.instance.currentUser?.email ?? '').trim();
  }

  String _currentActorLabel() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = (user?.displayName ?? '').trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }

    final email = (user?.email ?? '').trim();
    if (email.isNotEmpty) {
      return email;
    }

    return _currentActorUid();
  }

  void _disposeTextEditingControllersSafely(
    List<TextEditingController> controllers,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
  }
}
