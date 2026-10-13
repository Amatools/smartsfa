import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/tenant_entry_decision.dart';
import '../../../../navigation/app_shell.dart';
import '../../models/tenant_access.dart';
import '../../services/tenant_membership_service.dart';
import '../../services/tenant_entry_resolver.dart';
import 'loading_page.dart';
import 'pending_access_page.dart';
import 'sign_in_page.dart';
import 'web_sign_in_page.dart';

enum _WebUiMode { auto, web, mobile }

_WebUiMode _resolveWebUiMode() {
  if (!kIsWeb) {
    return _WebUiMode.auto;
  }

  final rawMode =
      (Uri.base.queryParameters['mode'] ??
              Uri.base.queryParameters['view'] ??
              '')
          .trim()
          .toLowerCase();
  if (rawMode == 'mobile' || rawMode == 'app') {
    return _WebUiMode.mobile;
  }
  if (rawMode == 'web' || rawMode == 'portal') {
    return _WebUiMode.web;
  }
  return _WebUiMode.auto;
}

class FirebaseAuthGatePage extends StatelessWidget {
  const FirebaseAuthGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final webUiMode = _resolveWebUiMode();

        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage(label: 'Validando autenticacao...');
        }

        final user = authSnapshot.data;
        if (user == null) {
          if (!kIsWeb) {
            return const SignInPage();
          }

          if (webUiMode == _WebUiMode.mobile) {
            return const SignInPage();
          }
          if (webUiMode == _WebUiMode.web) {
            return const WebSignInPage();
          }

          final screenWidth = MediaQuery.sizeOf(context).width;
          return screenWidth < 840 ? const SignInPage() : const WebSignInPage();
        }

        return _UserAccessResolver(
          user: user,
          forceMobilePreviewOnWeb: kIsWeb && webUiMode == _WebUiMode.mobile,
        );
      },
    );
  }
}

class _UserAccessResolver extends StatefulWidget {
  const _UserAccessResolver({
    required this.user,
    required this.forceMobilePreviewOnWeb,
  });

  final User user;
  final bool forceMobilePreviewOnWeb;

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
              forceMobilePreviewOnWeb: widget.forceMobilePreviewOnWeb,
            );
          case TenantEntryPath.invitation:
            return PendingAccessPage(
              user: widget.user,
              onAccessUpdated: _refreshAccess,
            );
          case TenantEntryPath.personalWorkspace:
            return PendingAccessPage(
              user: widget.user,
              onAccessUpdated: _refreshAccess,
            );
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
    required this.forceMobilePreviewOnWeb,
  });

  final User user;
  final TenantEntryDecision decision;
  final VoidCallback onAccessUpdated;
  final bool forceMobilePreviewOnWeb;

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
    return StreamBuilder<List<TenantEntryOption>>(
      stream: TenantMembershipService(FirebaseFirestore.instance)
          .watchTenantChoicesForUser(widget.user.uid),
      builder: (context, accessSnapshot) {
        final liveOptions = accessSnapshot.data ?? const <TenantEntryOption>[];
        final options = liveOptions.isNotEmpty
            ? liveOptions
            : widget.decision.options;

        if (options.isEmpty) {
          return PendingAccessPage(
            user: widget.user,
            onAccessUpdated: widget.onAccessUpdated,
          );
        }

        final selectedSeed = options.firstWhere(
          (item) => item.membershipId == _selectedMembershipId,
          orElse: () => options.first,
        );

        if (selectedSeed.membershipId != _selectedMembershipId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _selectedMembershipId = selectedSeed.membershipId;
            });
          });
        }

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
                message: 'A conta possui membership, mas o tenant nao foi encontrado.',
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
              forceMobilePreviewOnWeb: widget.forceMobilePreviewOnWeb,
              onSignOut: () => FirebaseAuth.instance.signOut(),
              onSwitchProfile: () {
                _showAccessPicker(
                  context,
                  options: options,
                  realRole: access.role,
                  hasRoleOverride: hasRoleOverride,
                );
              },
            );
          },
        );
      },
    );
  }

  void _showAccessPicker(
    BuildContext context, {
    required List<TenantEntryOption> options,
    required String realRole,
    required bool hasRoleOverride,
  }) {
    final parentContext = context;

    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final canSwitchMembership = options.length > 1;

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Trocar workspace'),
                subtitle: Text('Selecione o workspace ativo desta sessao.'),
              ),
              ...options.map(
                (item) => ListTile(
                  title: Text(item.tenantName),
                  subtitle: Text('Perfil no workspace: ${item.role}'),
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
              if (!canSwitchMembership) ...[
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Apenas um workspace disponível'),
                  subtitle: Text(
                    'Sua conta possui somente um workspace ativo no momento.',
                  ),
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_business_outlined),
                title: const Text('Adicionar workspace'),
                subtitle: const Text(
                  'Crie Individual/Representacoes ou entre com convite.',
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await Navigator.of(parentContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PendingAccessPage(
                        user: widget.user,
                        onAccessUpdated: widget.onAccessUpdated,
                      ),
                    ),
                  );
                },
              ),
              if (kDebugMode) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Troca rapida de hierarquia (dev)'),
                  subtitle: Text(
                    hasRoleOverride
                        ? 'Override ativo: $_devRoleOverride (real: $realRole)'
                        : 'Hierarquia real atual: $realRole',
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
                  title: const Text('Usar hierarquia real do workspace'),
                  subtitle: const Text('Remove o override de teste.'),
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
