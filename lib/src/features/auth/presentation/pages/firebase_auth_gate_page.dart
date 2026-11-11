import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/tenant_entry_decision.dart';
import '../../../../shared/utils/browser_url.dart';
import '../../../../shared/utils/window_open.dart';
import '../../../maintainer/domain/maintainer_access_decision.dart';
import '../../../maintainer/presentation/pages/maintainer_console_page.dart';
import '../../../maintainer/services/maintainer_access_service.dart';
import '../../../maintainer/services/maintainer_impersonation_service.dart';
import '../../../../navigation/app_shell.dart';
import '../../models/tenant_access.dart';
import '../../services/tenant_membership_service.dart';
import '../../services/tenant_entry_resolver.dart';
import 'loading_page.dart';
import 'pending_access_page.dart';
import 'sign_in_page.dart';
import 'web_admin_sign_in_page.dart';
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

bool _isMaintainerConsoleEntryRequested() {
  if (!kIsWeb) {
    return false;
  }

  final host = Uri.base.host.trim().toLowerCase();
  final pathSegments = Uri.base.pathSegments
      .map((segment) => segment.trim().toLowerCase())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);

  final rawEntry =
      (Uri.base.queryParameters['entry'] ??
              Uri.base.queryParameters['panel'] ??
              Uri.base.queryParameters['console'] ??
              '')
          .trim()
          .toLowerCase()
          .replaceAll(' ', '_');
  if (rawEntry == 'maintainer') {
    return true;
  }

  if (host.startsWith('maintainer.')) {
    return true;
  }

  final fragment = Uri.base.fragment.trim().toLowerCase().replaceAll(' ', '_');
  if (fragment.isNotEmpty) {
    if (fragment.contains('entry=maintainer') ||
        fragment.contains('panel=maintainer') ||
        fragment.contains('console=maintainer')) {
      return true;
    }

    final fragmentPath = fragment.split('?').first;
    final fragmentSegments = fragmentPath
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (fragmentSegments.contains('maintainer')) {
      return true;
    }
  }

  return pathSegments.contains('maintainer');
}

Map<String, String> _fragmentQueryParameters() {
  final fragment = Uri.base.fragment;
  final queryIndex = fragment.indexOf('?');
  if (queryIndex < 0 || queryIndex + 1 >= fragment.length) {
    return const <String, String>{};
  }

  final rawQuery = fragment.substring(queryIndex + 1).trim();
  if (rawQuery.isEmpty) {
    return const <String, String>{};
  }

  try {
    return Uri.splitQueryString(rawQuery);
  } catch (_) {
    return const <String, String>{};
  }
}

String _resolveUrlParameter(String key) {
  final direct = (Uri.base.queryParameters[key] ?? '').trim();
  if (direct.isNotEmpty) {
    return direct;
  }

  final fragmentValue = (_fragmentQueryParameters()[key] ?? '').trim();
  return fragmentValue;
}

String _impersonationSessionIdFromUrl() {
  return _resolveUrlParameter('impersonationSession');
}

String _impersonationSessionKeyFromUrl() {
  return _resolveUrlParameter('impersonationKey');
}

String _impersonationMembershipIdFromUrl() {
  return _resolveUrlParameter('impersonationMembershipId');
}

bool _isImpersonationBootstrapRequested() {
  return _impersonationSessionIdFromUrl().isNotEmpty &&
      _impersonationSessionKeyFromUrl().isNotEmpty;
}

class FirebaseAuthGatePage extends StatelessWidget {
  const FirebaseAuthGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final webUiMode = _resolveWebUiMode();
        final maintainerEntryRequested = _isMaintainerConsoleEntryRequested();
        final impersonationSessionId = _impersonationSessionIdFromUrl();
        final impersonationSessionKey = _impersonationSessionKeyFromUrl();
        final impersonationMembershipId = _impersonationMembershipIdFromUrl();
        final impersonationRequested = _isImpersonationBootstrapRequested();

        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage(label: 'Validando autenticacao...');
        }

        if (kIsWeb && impersonationRequested) {
          return _ImpersonationBootstrapPage(
            sessionId: impersonationSessionId,
            sessionKey: impersonationSessionKey,
          );
        }

        final user = authSnapshot.data;
        final restoreToken =
            kIsWeb && maintainerEntryRequested
            ? MaintainerImpersonationService
                  .takePendingAdminRestoreTokenIfNeeded(currentUid: user?.uid)
            : '';
        if (restoreToken.isNotEmpty) {
          return _MaintainerSessionRestorePage(customToken: restoreToken);
        }

        if (user == null) {
          if (!kIsWeb) {
            return const SignInPage();
          }

          if (maintainerEntryRequested) {
            return const WebAdminSignInPage();
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
          maintainerEntryRequested: maintainerEntryRequested,
          preferredMembershipId: impersonationMembershipId,
        );
      },
    );
  }
}

class _MaintainerSessionRestorePage extends StatefulWidget {
  const _MaintainerSessionRestorePage({required this.customToken});

  final String customToken;

  @override
  State<_MaintainerSessionRestorePage> createState() =>
      _MaintainerSessionRestorePageState();
}

class _MaintainerSessionRestorePageState
    extends State<_MaintainerSessionRestorePage> {
  bool _restoring = true;
  String _error = '';
  bool _showAdminLogin = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      await FirebaseAuth.instance.signInWithCustomToken(widget.customToken);
      if (!mounted) {
        return;
      }
      setState(() {
        _restoring = false;
        _error = '';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _restoring = false;
        _error = error.toString().trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showAdminLogin) {
      return const WebAdminSignInPage();
    }

    if (_restoring) {
      return const LoadingPage(label: 'Restaurando sessao admin...');
    }

    if (_error.isEmpty) {
      return const LoadingPage(label: 'Sessao admin restaurada.');
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Falha ao restaurar sessao admin',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(_error),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _restoring = true;
                                _error = '';
                              });
                              _restore();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tentar restaurar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _showAdminLogin = true;
                              });
                            },
                            icon: const Icon(Icons.login),
                            label: const Text('Ir para login admin'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImpersonationBootstrapPage extends StatefulWidget {
  const _ImpersonationBootstrapPage({
    required this.sessionId,
    required this.sessionKey,
  });

  final String sessionId;
  final String sessionKey;

  @override
  State<_ImpersonationBootstrapPage> createState() =>
      _ImpersonationBootstrapPageState();
}

class _ImpersonationBootstrapPageState extends State<_ImpersonationBootstrapPage> {
  late final MaintainerImpersonationService _impersonationService;
  bool _running = true;
  String _status = 'Preparando acesso assistido...';
  String _error = '';
  String _cachedCustomToken = '';

  @override
  void initState() {
    super.initState();
    _impersonationService = MaintainerImpersonationService();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      if (_cachedCustomToken.isEmpty) {
        final consumed = await _impersonationService.consumeSession(
          sessionId: widget.sessionId,
          sessionKey: widget.sessionKey,
        );
        _cachedCustomToken = consumed.customToken;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Aplicando sessao assistida...';
      });

      try {
        await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
      } catch (_) {
        // Best effort only.
      }

      await FirebaseAuth.instance.signInWithCustomToken(_cachedCustomToken);

      removeQueryParametersFromCurrentUrl({
        'impersonationSession',
        'impersonationKey',
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _running = false;
        _status = 'Sessao assistida ativa.';
        _error = '';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _running = false;
        _error = _normalizeImpersonationBootstrapError(error);
      });
    }
  }

  String _normalizeImpersonationBootstrapError(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) {
      return 'Falha ao iniciar acesso assistido. Tente novamente.';
    }

    final normalized = raw.toLowerCase();
    if (normalized.contains('session_already_consumed') ||
        normalized.contains('ja consumida')) {
      return 'Este link de acesso assistido ja foi utilizado. Gere uma nova sessao no painel admin.';
    }

    if (normalized.contains('custom_token_generation_failed')) {
      return 'Falha temporaria ao preparar autenticacao da sessao assistida. Tente novamente em instantes.';
    }

    return raw;
  }

  void _exitBootstrapWindow() {
    removeQueryParametersFromCurrentUrl({
      'impersonationSession',
      'impersonationKey',
      'impersonationTenantId',
      'impersonationMembershipId',
    });
    closeCurrentBrowserWindow();
  }

  @override
  Widget build(BuildContext context) {
    if (_running) {
      return LoadingPage(label: _status);
    }

    if (_error.isEmpty) {
      return LoadingPage(label: _status);
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Falha ao iniciar acesso assistido',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(_error),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _running = true;
                                _status = 'Tentando novamente...';
                                _error = '';
                              });
                              _bootstrap();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tentar novamente'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _exitBootstrapWindow,
                            icon: const Icon(Icons.logout),
                            label: const Text('Sair'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserAccessResolver extends StatefulWidget {
  const _UserAccessResolver({
    required this.user,
    required this.forceMobilePreviewOnWeb,
    required this.maintainerEntryRequested,
    required this.preferredMembershipId,
  });

  final User user;
  final bool forceMobilePreviewOnWeb;
  final bool maintainerEntryRequested;
  final String preferredMembershipId;

  @override
  State<_UserAccessResolver> createState() => _UserAccessResolverState();
}

class _UserAccessResolverState extends State<_UserAccessResolver> {
  int _refreshNonce = 0;

  @override
  void initState() {
    super.initState();
    _seedUserProfileFromAuth();
  }

  Future<void> _seedUserProfileFromAuth() async {
    final user = widget.user;
    final normalizedEmail = (user.email ?? '').trim();
    final normalizedDisplayName = (user.displayName ?? '').trim();
    final fallbackName = normalizedDisplayName.isNotEmpty
        ? normalizedDisplayName
        : (normalizedEmail.isNotEmpty
              ? normalizedEmail.split('@').first
              : user.uid);

    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set(
        {
          'uid': user.uid,
          if (normalizedEmail.isNotEmpty) 'email': normalizedEmail,
          if (fallbackName.isNotEmpty) 'displayName': fallbackName,
          if (fallbackName.isNotEmpty) 'name': fallbackName,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Best effort only: access resolution must not fail because of profile sync.
    }
  }

  void _refreshAccess() {
    setState(() {
      _refreshNonce++;
    });
  }

  String _describeAccessResolutionError(Object? error) {
    if (error is TenantEntryResolverException) {
      return error.message;
    }

    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Sem permissao para validar acesso ao workspace no momento. Tente novamente.';
      }

      final firebaseMessage = (error.message ?? '').trim();
      if (firebaseMessage.isNotEmpty) {
        return 'Falha ao validar acesso: $firebaseMessage';
      }
    }

    return 'Falha temporaria ao validar acesso ao workspace. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.maintainerEntryRequested) {
      return _MaintainerConsoleGate(
        user: widget.user,
        onSignOut: () => FirebaseAuth.instance.signOut(),
      );
    }

    return FutureBuilder<TenantEntryDecision?>(
      key: ValueKey(_refreshNonce),
      future: TenantEntryResolver(FirebaseFirestore.instance)
          .resolve(widget.user),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage(label: 'Resolving tenant access...');
        }

        if (snapshot.hasError) {
          return _AccessResolutionErrorScaffold(
            message: _describeAccessResolutionError(snapshot.error),
            onRetry: _refreshAccess,
            onSignOut: () => FirebaseAuth.instance.signOut(),
          );
        }

        final decision = snapshot.data;
        if (decision == null) {
          return _MaintainerOrPendingAccessGate(
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
              preferredMembershipId: widget.preferredMembershipId,
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

class _MaintainerOrPendingAccessGate extends StatefulWidget {
  const _MaintainerOrPendingAccessGate({
    required this.user,
    required this.onAccessUpdated,
  });

  final User user;
  final VoidCallback onAccessUpdated;

  @override
  State<_MaintainerOrPendingAccessGate> createState() =>
      _MaintainerOrPendingAccessGateState();
}

class _MaintainerOrPendingAccessGateState
    extends State<_MaintainerOrPendingAccessGate> {
  late final MaintainerAccessService _accessService;
  late Future<MaintainerAccessDecision> _decisionFuture;

  @override
  void initState() {
    super.initState();
    _accessService = MaintainerAccessService(FirebaseFirestore.instance);
    _decisionFuture = _accessService.evaluateAccess(uid: widget.user.uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MaintainerAccessDecision>(
      future: _decisionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage(label: 'Validando acesso da plataforma...');
        }

        final decision = snapshot.data;
        if (decision != null && decision.granted) {
          return _MaintainerConsoleGate(
            user: widget.user,
            onSignOut: () => FirebaseAuth.instance.signOut(),
          );
        }

        return PendingAccessPage(
          user: widget.user,
          onAccessUpdated: widget.onAccessUpdated,
        );
      },
    );
  }
}

class _MaintainerConsoleGate extends StatefulWidget {
  const _MaintainerConsoleGate({required this.user, required this.onSignOut});

  final User user;
  final VoidCallback onSignOut;

  @override
  State<_MaintainerConsoleGate> createState() => _MaintainerConsoleGateState();
}

class _MaintainerConsoleGateState extends State<_MaintainerConsoleGate> {
  late final MaintainerAccessService _accessService;
  late Future<MaintainerAccessDecision> _decisionFuture;
  bool _autoRecheckScheduled = false;

  @override
  void initState() {
    super.initState();
    _accessService = MaintainerAccessService(FirebaseFirestore.instance);
    _refresh();
  }

  void _refresh() {
    setState(() {
      _decisionFuture = _accessService.evaluateAccess(uid: widget.user.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MaintainerAccessDecision>(
      future: _decisionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage(label: 'Validando acesso do mantenedor...');
        }

        if (snapshot.hasError) {
          if (!_autoRecheckScheduled) {
            _scheduleAutomaticRecheck();
            return const LoadingPage(
              label: 'Revalidando acesso do mantenedor...',
            );
          }

          return _AccessResolutionErrorScaffold(
            message: 'Falha ao validar acesso ao painel de mantenedor. Tente novamente.',
            onRetry: _refresh,
            onSignOut: widget.onSignOut,
          );
        }

        final decision = snapshot.data;
        if (decision == null || !decision.granted) {
          if (!_autoRecheckScheduled) {
            _scheduleAutomaticRecheck();
            return const LoadingPage(
              label: 'Revalidando acesso do mantenedor...',
            );
          }

          return Scaffold(
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Acesso negado ao painel de mantenedor',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              decision?.reason ??
                                  'Sem permissao para abrir este painel.',
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: _refresh,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Tentar novamente'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: widget.onSignOut,
                                  icon: const Icon(Icons.logout),
                                  label: const Text('Sair'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('SmartSFA - Mantenedor'),
            actions: [
              IconButton(
                onPressed: widget.onSignOut,
                icon: const Icon(Icons.logout),
                tooltip: 'Sair',
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: MaintainerConsolePage(
                  membershipRoleOverride: decision.effectiveRole,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _scheduleAutomaticRecheck() {
    _autoRecheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _refresh();
    });
  }
}

class _TenantAccessResolver extends StatefulWidget {
  const _TenantAccessResolver({
    required this.user,
    required this.decision,
    required this.onAccessUpdated,
    required this.forceMobilePreviewOnWeb,
    required this.preferredMembershipId,
  });

  final User user;
  final TenantEntryDecision decision;
  final VoidCallback onAccessUpdated;
  final bool forceMobilePreviewOnWeb;
  final String preferredMembershipId;

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
    _selectedMembershipId = _resolveInitialMembershipId(widget.decision.options);
  }

  @override
  void didUpdateWidget(covariant _TenantAccessResolver oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stillExists = widget.decision.options.any(
      (item) => item.membershipId == _selectedMembershipId,
    );
    if (!stillExists && widget.decision.options.isNotEmpty) {
      _selectedMembershipId = _resolveInitialMembershipId(widget.decision.options);
    }
  }

  String _resolveInitialMembershipId(List<TenantEntryOption> options) {
    final preferredMembershipId = widget.preferredMembershipId.trim();
    if (preferredMembershipId.isNotEmpty) {
      for (final option in options) {
        if (option.membershipId == preferredMembershipId) {
          return preferredMembershipId;
        }
      }
    }

    return options
        .firstWhere(
          (item) => item.defaultTenant,
          orElse: () => options.first,
        )
        .membershipId;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TenantEntryOption>>(
      stream: TenantMembershipService(FirebaseFirestore.instance)
          .watchTenantChoicesForUser(widget.user.uid),
      builder: (context, accessSnapshot) {
        if (accessSnapshot.hasError) {
          return _AccessResolutionErrorScaffold(
            message: 'Nao foi possivel carregar seus workspaces agora. Tente novamente.',
            onRetry: widget.onAccessUpdated,
            onSignOut: () => FirebaseAuth.instance.signOut(),
          );
        }

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

        final preferredMembershipId = widget.preferredMembershipId.trim();
        if (preferredMembershipId.isNotEmpty &&
            options.any((item) => item.membershipId == preferredMembershipId) &&
            _selectedMembershipId != preferredMembershipId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _selectedMembershipId = preferredMembershipId;
            });
          });
        }

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

            if (tenantSnapshot.hasError) {
              return _AccessResolutionErrorScaffold(
                message: 'Falha ao carregar os dados do tenant selecionado. Tente novamente.',
                onRetry: widget.onAccessUpdated,
                onSignOut: () => FirebaseAuth.instance.signOut(),
              );
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

class _AccessResolutionErrorScaffold extends StatelessWidget {
  const _AccessResolutionErrorScaffold({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Falha ao validar acesso',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(message),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tentar novamente'),
                          ),
                          OutlinedButton.icon(
                            onPressed: onSignOut,
                            icon: const Icon(Icons.logout),
                            label: const Text('Sair e entrar de novo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
