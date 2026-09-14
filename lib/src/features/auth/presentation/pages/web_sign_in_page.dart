import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_error_info.dart';

class WebSignInPage extends StatefulWidget {
  const WebSignInPage({super.key});

  @override
  State<WebSignInPage> createState() => _WebSignInPageState();
}

class _WebSignInPageState extends State<WebSignInPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  AuthErrorInfo? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final provider = GoogleAuthProvider();
      await FirebaseAuth.instance.signInWithPopup(provider);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = AuthErrorInfo.fromFirebaseException(
          e,
          provider: 'google',
        );
      });
    } catch (_) {
      setState(() {
        _error = AuthErrorInfo.unexpected;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _signInWithEmailPassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = const AuthErrorInfo(
          code: 'validation',
          message: 'Informe e-mail e senha para entrar.',
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = AuthErrorInfo.fromFirebaseException(
          e,
          provider: 'password',
        );
      });
    } catch (_) {
      setState(() {
        _error = AuthErrorInfo.unexpected;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isWide = MediaQuery.sizeOf(context).width >= 980;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: isWide
                  ? Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: _HeroPanel(
                            textTheme: textTheme,
                            colorScheme: theme.colorScheme,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 4,
                          child: _LoginPanel(
                            loading: _loading,
                            error: _error,
                            emailController: _emailController,
                            passwordController: _passwordController,
                            onGoogle: _signInWithGoogle,
                            onEmailPassword: _signInWithEmailPassword,
                            textTheme: textTheme,
                            colorScheme: theme.colorScheme,
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          _HeroPanel(
                            textTheme: textTheme,
                            colorScheme: theme.colorScheme,
                          ),
                          const SizedBox(height: 16),
                          _LoginPanel(
                            loading: _loading,
                            error: _error,
                            emailController: _emailController,
                            passwordController: _passwordController,
                            onGoogle: _signInWithGoogle,
                            onEmailPassword: _signInWithEmailPassword,
                            textTheme: textTheme,
                            colorScheme: theme.colorScheme,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.textTheme, required this.colorScheme});

  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.storefront_outlined, size: 42, color: colorScheme.primary),
            const SizedBox(height: 20),
            Text('Smart SFA', style: textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Portal web administrativo e login oficial no mesmo dominio do produto.',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            const Text(
              'Use o web para configuracoes densas, politicas de preco, ERP e governanca. O app mobile fica para operacao e campo.',
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: const [
                _FeatureChip(label: 'Portal web'),
                _FeatureChip(label: 'Pricing engine'),
                _FeatureChip(label: 'ERP parametrizavel'),
                _FeatureChip(label: 'Governanca multi-tenant'),
              ],
            ),
            const SizedBox(height: 28),
            const _FeatureCard(
              title: 'Acesso responsivo',
              subtitle: 'Login adaptado para navegador, com foco em leitura, configuracao e navegação de portal.',
            ),
            const SizedBox(height: 12),
            const _FeatureCard(
              title: 'Mesmo login Firebase',
              subtitle: 'Um unico domínio e autenticacao compartilhada para mobile e web.',
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.loading,
    required this.error,
    required this.emailController,
    required this.passwordController,
    required this.onGoogle,
    required this.onEmailPassword,
    required this.textTheme,
    required this.colorScheme,
  });

  final bool loading;
  final AuthErrorInfo? error;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final VoidCallback onGoogle;
  final VoidCallback onEmailPassword;
  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Entrar', style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Acesso corporativo com liberacao interna.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            if (error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Codigo: ${error!.code}',
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      error!.message,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: loading ? null : onGoogle,
              icon: const Icon(Icons.login),
              label: Text(
                loading ? 'Entrando...' : 'Continuar com Google',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Se a empresa ainda nao liberou o acesso, use o fluxo de onboarding após autenticar.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'E-mail',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Senha',
              ),
              onSubmitted: (_) => onEmailPassword(),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: loading ? null : onEmailPassword,
              icon: const Icon(Icons.alternate_email),
              label: const Text('Entrar com e-mail/senha'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.check_circle_outline),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
