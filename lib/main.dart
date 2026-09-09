import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'src/core/models/app_identity.dart';
import 'src/features/auth/presentation/pages/firebase_auth_gate_page.dart';
import 'src/navigation/app_shell.dart';

const bool kUseMockAuth = bool.fromEnvironment(
  'USE_MOCK_AUTH',
  defaultValue: true,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const SmartSfaApp());
}

class SmartSfaApp extends StatelessWidget {
  const SmartSfaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartSFA',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B5D4B)),
        useMaterial3: true,
      ),
      home: const SplashFlowPage(),
    );
  }
}

class SplashFlowPage extends StatefulWidget {
  const SplashFlowPage({super.key});

  @override
  State<SplashFlowPage> createState() => _SplashFlowPageState();
}

class _SplashFlowPageState extends State<SplashFlowPage> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return kUseMockAuth
          ? const DevAuthGatePage()
          : const FirebaseAuthGatePage();
    }

    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.android,
                      size: 88,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Smart SFA',
                      style: textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Forca de Vendas Smart',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      kUseMockAuth
                          ? 'Modo desenvolvimento com acesso simulado'
                          : 'Inicializando autenticacao segura',
                      style: textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: CircularProgressIndicator(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DevAuthGatePage extends StatefulWidget {
  const DevAuthGatePage({super.key});

  @override
  State<DevAuthGatePage> createState() => _DevAuthGatePageState();
}

class _DevAuthGatePageState extends State<DevAuthGatePage> {
  DevAccessSession? _session;

  void _signIn(DevAccessSession session) {
    setState(() {
      _session = session;
    });
  }

  void _signOut() {
    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return DevSignInPage(onSignIn: _signIn);
    }

    return AppShellPage(
      identity: AppIdentity(
        tenantId: _session!.tenant.id,
        userLabel: _session!.userEmail,
        role: _session!.role.label,
        tenantName: _session!.tenant.name,
        isMock: true,
      ),
      onSignOut: _signOut,
      onSwitchProfile: _signOut,
    );
  }
}

class DevSignInPage extends StatefulWidget {
  const DevSignInPage({super.key, required this.onSignIn});

  final ValueChanged<DevAccessSession> onSignIn;

  @override
  State<DevSignInPage> createState() => _DevSignInPageState();
}

class _DevSignInPageState extends State<DevSignInPage> {
  final List<DevTenant> _tenants = const [
    DevTenant(id: 'amatools', name: 'Amatools'),
    DevTenant(id: 'demo', name: 'Tenant Demo'),
  ];

  DevTenant? _selectedTenant;
  DevRole _selectedRole = DevRole.owner;

  @override
  void initState() {
    super.initState();
    _selectedTenant = _tenants.first;
  }

  void _enter() {
    final tenant = _selectedTenant;
    if (tenant == null) {
      return;
    }

    widget.onSignIn(
      DevAccessSession(
        tenant: tenant,
        role: _selectedRole,
        userEmail: '${_selectedRole.name}@${tenant.id}.local',
      ),
    );
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
                  'Modo de desenvolvimento para validar a plataforma sem login real.',
                  style: textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selecionar tenant',
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<DevTenant>(
                          initialValue: _selectedTenant,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Tenant',
                          ),
                          items: _tenants
                              .map(
                                (tenant) => DropdownMenuItem<DevTenant>(
                                  value: tenant,
                                  child: Text(tenant.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedTenant = value;
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Selecionar perfil',
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<DevRole>(
                          initialValue: _selectedRole,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Perfil',
                          ),
                          items: DevRole.values
                              .map(
                                (role) => DropdownMenuItem<DevRole>(
                                  value: role,
                                  child: Text(role.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedRole = value;
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _enter,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Entrar no modo dev'),
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
                          'Observacoes',
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Este modo ignora Google Sign-In e Firestore para liberar o desenvolvimento das telas, navegacao, fluxo comercial e permissoes visuais.',
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
