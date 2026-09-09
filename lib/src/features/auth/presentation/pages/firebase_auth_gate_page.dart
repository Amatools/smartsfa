import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/tenant_entry_decision.dart';
import '../../../../navigation/app_shell.dart';
import '../../models/tenant_access.dart';
import '../../services/tenant_entry_resolver.dart';
import 'loading_page.dart';
import 'pending_access_page.dart';
import 'sign_in_page.dart';

class FirebaseAuthGatePage extends StatelessWidget {
  const FirebaseAuthGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage(label: 'Validando autenticacao...');
        }

        final user = authSnapshot.data;
        if (user == null) {
          return const SignInPage();
        }

        return _UserAccessResolver(user: user);
      },
    );
  }
}

class _UserAccessResolver extends StatefulWidget {
  const _UserAccessResolver({required this.user});

  final User user;

  @override
  State<_UserAccessResolver> createState() => _UserAccessResolverState();
}

class _UserAccessResolverState extends State<_UserAccessResolver> {
  int _refreshNonce = 0;

  void _refreshAccess() {
    setState(() {
      _refreshNonce++;
    });
  }

  Widget _buildPersonalWorkspace() {
    return AppShellPage(
      identity: AppIdentity(
        tenantId: 'personal_${widget.user.uid}',
        tenantName: 'Workspace pessoal',
        userLabel: widget.user.email ?? widget.user.uid,
        role: 'vendedor',
        isMock: false,
        membershipId: null,
        isPersonalWorkspace: true,
      ),
      onAccessUpdated: _refreshAccess,
      onSignOut: () => FirebaseAuth.instance.signOut(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TenantEntryDecision?>(
      key: ValueKey(_refreshNonce),
      future: TenantEntryResolver(FirebaseFirestore.instance)
          .resolve(widget.user),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage(label: 'Resolving tenant access...');
        }

        final decision = snapshot.data;
        if (decision == null) {
          return PendingAccessPage(
            user: widget.user,
            onAccessUpdated: _refreshAccess,
          );
        }

        switch (decision.path) {
          case TenantEntryPath.requestAccess:
            if (decision.personalWorkspaceEnabled) {
              return _buildPersonalWorkspace();
            }

            return PendingAccessPage(
              user: widget.user,
              onAccessUpdated: _refreshAccess,
            );
          case TenantEntryPath.directTenant:
          case TenantEntryPath.selector:
            return _TenantAccessResolver(
              user: widget.user,
              decision: decision,
              onAccessUpdated: _refreshAccess,
            );
          case TenantEntryPath.invitation:
            return PendingAccessPage(
              user: widget.user,
              onAccessUpdated: _refreshAccess,
            );
          case TenantEntryPath.personalWorkspace:
            return _buildPersonalWorkspace();
        }
      },
    );
  }
}

class _TenantAccessResolver extends StatefulWidget {
  const _TenantAccessResolver({
    required this.user,
    required this.decision,
    required this.onAccessUpdated,
  });

  final User user;
  final TenantEntryDecision decision;
  final VoidCallback onAccessUpdated;

  @override
  State<_TenantAccessResolver> createState() => _TenantAccessResolverState();
}

class _TenantAccessResolverState extends State<_TenantAccessResolver> {
  static const List<String> _devRoles = [
    'platform_admin',
    'owner',
    'gerente',
    'representante',
    'vendedor',
  ];

  late String _selectedMembershipId;
  String? _devRoleOverride;

  @override
  void initState() {
    super.initState();
    _selectedMembershipId = widget.decision.options
        .firstWhere(
          (item) => item.defaultTenant,
          orElse: () => widget.decision.options.first,
        )
        .membershipId;
  }

  @override
  void didUpdateWidget(covariant _TenantAccessResolver oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stillExists = widget.decision.options.any(
      (item) => item.membershipId == _selectedMembershipId,
    );
    if (!stillExists && widget.decision.options.isNotEmpty) {
      _selectedMembershipId = widget.decision.options
          .firstWhere(
            (item) => item.defaultTenant,
            orElse: () => widget.decision.options.first,
          )
          .membershipId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedSeed = widget.decision.options.firstWhere(
      (item) => item.membershipId == _selectedMembershipId,
      orElse: () => widget.decision.options.first,
    );

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('tenants')
          .doc(selectedSeed.tenantId)
          .snapshots(),
      builder: (context, tenantSnapshot) {
        if (tenantSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage(label: 'Carregando tenant...');
        }

        final tenantDoc = tenantSnapshot.data;
        if (tenantDoc == null || !tenantDoc.exists) {
          return const AccessDeniedScaffold(
            title: 'Tenant indisponivel',
            message:
                'A conta possui membership, mas o tenant nao foi encontrado.',
          );
        }

        final tenantData = tenantDoc.data() ?? <String, dynamic>{};
        if (tenantData['ativo'] != true) {
          return const AccessDeniedScaffold(
            title: 'Tenant inativo',
            message: 'O tenant selecionado nao esta ativo no momento.',
          );
        }

        final access = TenantAccess(
          membershipId: selectedSeed.membershipId,
          tenantId: selectedSeed.tenantId,
          tenantName: selectedSeed.tenantName,
          role: selectedSeed.role,
          defaultTenant: selectedSeed.defaultTenant,
        );

        final effectiveRole = _devRoleOverride ?? access.role;
        final hasRoleOverride = _devRoleOverride != null;

        return AppShellPage(
          identity: AppIdentity(
            tenantId: access.tenantId,
            tenantName: access.tenantName,
            userLabel: widget.user.email ?? widget.user.uid,
            role: effectiveRole,
            isMock: false,
            membershipId: access.membershipId,
            isPersonalWorkspace: false,
          ),
          onAccessUpdated: widget.onAccessUpdated,
          onSignOut: () => FirebaseAuth.instance.signOut(),
          onSwitchProfile: () {
            _showAccessPicker(
              context,
              realRole: access.role,
              hasRoleOverride: hasRoleOverride,
            );
          },
        );
      },
    );
  }

  void _showAccessPicker(
    BuildContext context, {
    required String realRole,
    required bool hasRoleOverride,
  }) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final canSwitchMembership = widget.decision.options.length > 1;

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Trocar acesso'),
                subtitle: Text('Selecione tenant/perfil para esta sessao.'),
              ),
              if (canSwitchMembership)
                ...widget.decision.options.map(
                  (item) => ListTile(
                    title: Text(item.tenantName),
                    subtitle: Text('Role real: ${item.role}'),
                    trailing: item.membershipId == _selectedMembershipId
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedMembershipId = item.membershipId;
                        _devRoleOverride = null;
                      });
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              if (kDebugMode) ...[
                const Divider(height: 1),
                ListTile(
                  title: const Text('Perfil de interface (dev)'),
                  subtitle: Text(
                    hasRoleOverride
                        ? 'Override ativo: $_devRoleOverride (real: $realRole)'
                        : 'Role real atual: $realRole',
                  ),
                ),
                ..._devRoles.map(
                  (role) => ListTile(
                    title: Text(role),
                    trailing: _devRoleOverride == role
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () {
                      setState(() {
                        _devRoleOverride = role;
                      });
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Usar role real do Firebase'),
                  subtitle: const Text('Remove override de interface.'),
                  trailing: !hasRoleOverride ? const Icon(Icons.check) : null,
                  onTap: () {
                    setState(() {
                      _devRoleOverride = null;
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class AccessDeniedScaffold extends StatelessWidget {
  const AccessDeniedScaffold({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
