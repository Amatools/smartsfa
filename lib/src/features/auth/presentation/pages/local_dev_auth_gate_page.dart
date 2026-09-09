import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../navigation/app_shell.dart';

class LocalDevAuthGatePage extends StatefulWidget {
  const LocalDevAuthGatePage({super.key});

  @override
  State<LocalDevAuthGatePage> createState() => _LocalDevAuthGatePageState();
}

class _LocalDevAuthGatePageState extends State<LocalDevAuthGatePage> {
  LocalDevSession? _session;

  void _signIn(LocalDevSession session) {
    setState(() {
      _session = session;
    });
  }

  void _signOut() async {
    await FirebaseAuth.instance.signOut();
    setState(() {
      _session = null;
    });
  }

  Future<void> _switchProfile() async {
    final current = _session;
    if (current == null) {
      return;
    }

    final account = await showModalBottomSheet<LocalDevAccount>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Trocar perfil local'),
                subtitle: Text('Muda permissao em tempo real no app.'),
              ),
              ...LocalDevAuthService.accounts.map(
                (item) => ListTile(
                  title: Text(item.email),
                  subtitle: Text('${item.role} · ${item.tenantName}'),
                  trailing: item.email == current.email
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop(item);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (account == null) {
      return;
    }

    var nextIsMock = current.isMock;
    if (!current.isMock) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null || uid.isEmpty) {
          throw StateError('Sessao Firebase indisponivel.');
        }

        await provisionDevAccessForAccount(
          firestore: FirebaseFirestore.instance,
          uid: uid,
          account: account,
        );
      } catch (_) {
        nextIsMock = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Nao foi possivel atualizar perfil no Firebase agora. Mantendo modo local mock.',
              ),
            ),
          );
        }
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _session = LocalDevSession(
        email: account.email,
        role: account.role,
        tenantId: account.tenantId,
        tenantName: account.tenantName,
        isMock: nextIsMock,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return LocalDevSignInPage(onSignIn: _signIn);
    }

    return AppShellPage(
      identity: AppIdentity(
        tenantId: _session!.tenantId,
        userLabel: _session!.email,
        role: _session!.role,
        tenantName: _session!.tenantName,
        isMock: _session!.isMock,
      ),
      onSignOut: _signOut,
      onSwitchProfile: _switchProfile,
    );
  }
}

class LocalDevSignInPage extends StatefulWidget {
  const LocalDevSignInPage({super.key, required this.onSignIn});

  final ValueChanged<LocalDevSession> onSignIn;

  @override
  State<LocalDevSignInPage> createState() => _LocalDevSignInPageState();
}

class _LocalDevSignInPageState extends State<LocalDevSignInPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final LocalDevAuthService _authService = const LocalDevAuthService();
  final _firebaseAuth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _loading = false;
  String? _error;
  String? _hint;
  String? _lastAnonymousUid;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
      _hint = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 250));
    final account = _authService.findAccount(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) {
      return;
    }

    if (account == null) {
      setState(() {
        _loading = false;
        _error = 'Credenciais invalidas para o modo local.';
      });
      return;
    }

    var isMockFallback = false;
    String? anonymousUid;
    try {
      final credential = await _firebaseAuth.signInAnonymously();
      anonymousUid = credential.user?.uid;
      if (anonymousUid == null || anonymousUid.isEmpty) {
        throw StateError(
          'Nao foi possivel obter UID anonimo no Firebase Auth.',
        );
      }
      _lastAnonymousUid = anonymousUid;

      await provisionDevAccessForAccount(
        firestore: _firestore,
        uid: anonymousUid,
        account: account,
      );
      _hint = 'Sessao local conectada ao Firebase (Auth anonimo + Firestore).';
    } catch (error) {
      if (anonymousUid != null &&
          await _hasManualProvisionedAccess(
            uid: anonymousUid,
            tenantId: account.tenantId,
          )) {
        _hint = 'Auth anonimo ativo e acesso encontrado no Firestore para este UID. Sessao conectada ao Firebase.';
      } else {
        isMockFallback = true;
        _hint = 'Firebase indisponivel para este login local agora. O app entrou em modo mock para nao travar o desenvolvimento.';
        _error = _buildManualProvisionMessage(
          uid: anonymousUid,
          tenantId: account.tenantId,
          role: account.role,
          error: error,
        );
      }
    }

    final session = LocalDevSession(
      email: account.email,
      role: account.role,
      tenantId: account.tenantId,
      tenantName: account.tenantName,
      isMock: isMockFallback,
    );

    setState(() {
      _loading = false;
    });
    widget.onSignIn(session);
  }

  Future<bool> _hasManualProvisionedAccess({
    required String uid,
    required String tenantId,
  }) async {
    final userDoc = await _firestore.collection('usuarios').doc(uid).get();
    if (!userDoc.exists) {
      return false;
    }

    final userData = userDoc.data() ?? <String, dynamic>{};
    if (userData['ativoGlobal'] != true) {
      return false;
    }

    final membershipDoc = await _firestore
        .collection('tenant_memberships')
        .doc('${tenantId}_$uid')
        .get();

    if (!membershipDoc.exists) {
      return false;
    }

    final membershipData = membershipDoc.data() ?? <String, dynamic>{};
    return membershipData['tenantId'] == tenantId &&
        membershipData['uid'] == uid &&
        membershipData['ativo'] == true;
  }

  String _buildManualProvisionMessage({
    required String? uid,
    required String tenantId,
    required String role,
    required Object error,
  }) {
    final resolvedUid = (uid == null || uid.isEmpty)
        ? '<uid-nao-disponivel>'
        : uid;

    return 'Provisionamento automatico bloqueado. Para usar Firebase sem mock, crie manualmente no Firestore: '
        'usuarios/$resolvedUid (ativoGlobal=true) e tenant_memberships/${tenantId}_$resolvedUid '
        '(tenantId=$tenantId, uid=$resolvedUid, role=$role, ativo=true). '
        'Erro: $error';
  }

  void _fillExample(LocalDevAccount account) {
    setState(() {
      _error = null;
      _hint = null;
      _emailController.text = account.email;
      _passwordController.text = account.password;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Smart SFA', style: textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Login local de desenvolvimento (sem Google Cloud).',
                  style: textTheme.bodyLarge,
                ),
                if (_lastAnonymousUid != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'UID anonimo atual: $_lastAnonymousUid',
                    style: textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'E-mail',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Senha',
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        if (_hint != null) ...[
                          const SizedBox(height: 12),
                          Text(_hint!, style: textTheme.bodyMedium),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loading ? null : _submit,
                          icon: const Icon(Icons.login),
                          label: Text(_loading ? 'Entrando...' : 'Entrar'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contas locais de exemplo',
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ...LocalDevAuthService.accounts.map(
                          (account) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(account.email),
                            subtitle: Text(
                              '${account.role} · tenant ${account.tenantName} · senha ${account.password}',
                            ),
                            trailing: TextButton(
                              onPressed: () => _fillExample(account),
                              child: const Text('Usar'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LocalDevAuthService {
  const LocalDevAuthService();

  static const List<LocalDevAccount> accounts = [
    LocalDevAccount(
      email: 'owner@amatools.local',
      password: '123456',
      role: 'owner',
      tenantId: 'amatools',
      tenantName: 'Amatools',
    ),
    LocalDevAccount(
      email: 'gerente@amatools.local',
      password: '123456',
      role: 'gerente',
      tenantId: 'amatools',
      tenantName: 'Amatools',
    ),
    LocalDevAccount(
      email: 'representante@amatools.local',
      password: '123456',
      role: 'representante',
      tenantId: 'amatools',
      tenantName: 'Amatools',
    ),
    LocalDevAccount(
      email: 'vendedor@amatools.local',
      password: '123456',
      role: 'vendedor',
      tenantId: 'amatools',
      tenantName: 'Amatools',
    ),
    LocalDevAccount(
      email: 'platform@smartsfa.local',
      password: '123456',
      role: 'platform_admin',
      tenantId: 'amatools',
      tenantName: 'Amatools',
    ),
  ];

  LocalDevAccount? findAccount({
    required String email,
    required String password,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPassword = password.trim();

    for (final item in accounts) {
      if (item.email == normalizedEmail &&
          item.password == normalizedPassword) {
        return item;
      }
    }

    return null;
  }
}

class LocalDevAccount {
  const LocalDevAccount({
    required this.email,
    required this.password,
    required this.role,
    required this.tenantId,
    required this.tenantName,
  });

  final String email;
  final String password;
  final String role;
  final String tenantId;
  final String tenantName;
}

class LocalDevSession {
  const LocalDevSession({
    required this.email,
    required this.role,
    required this.tenantId,
    required this.tenantName,
    required this.isMock,
  });

  final String email;
  final String role;
  final String tenantId;
  final String tenantName;
  final bool isMock;
}

Future<void> provisionDevAccessForAccount({
  required FirebaseFirestore firestore,
  required String uid,
  required LocalDevAccount account,
}) async {
  final now = DateTime.now().toIso8601String();
  final membershipId = '${account.tenantId}_$uid';
  final role = account.role;

  await firestore.collection('tenants').doc(account.tenantId).set({
    'tenantId': account.tenantId,
    'slug': account.tenantId,
    'nomeFantasia': account.tenantName,
    'razaoSocial': account.tenantName,
    'ativo': true,
    'operationMode': 'manual',
    'erpProvider': 'none',
    'createdAt': now,
    'updatedAt': now,
  }, SetOptions(merge: true));

  await firestore.collection('usuarios').doc(uid).set({
    'uid': uid,
    'email': account.email,
    'displayName': account.email,
    'platformRole': role == 'platform_admin' ? 'platform_admin' : 'none',
    'ativoGlobal': true,
    'defaultTenantId': account.tenantId,
    'lastSelectedTenantId': account.tenantId,
    'updatedAt': now,
  }, SetOptions(merge: true));

  await firestore.collection('tenant_memberships').doc(membershipId).set({
    'membershipId': membershipId,
    'tenantId': account.tenantId,
    'uid': uid,
    'role': role,
    'ativo': true,
    'defaultTenant': true,
    'ownerId': uid,
    'gerenteId': role == 'owner' ? '' : uid,
    'representanteId': role == 'vendedor' || role == 'representante' ? uid : '',
    'vendedorId': role == 'vendedor' ? uid : '',
    'state': 'active',
    'updatedAt': now,
  }, SetOptions(merge: true));
}
