import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/utils/window_open.dart';
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
        _error = AuthErrorInfo.fromFirebaseException(e, provider: 'google');
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
        _error = AuthErrorInfo.fromFirebaseException(e, provider: 'password');
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

  void _openPublicPage(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final target = Uri.base
        .replace(
          path: normalizedPath,
          queryParameters: const <String, String>{},
          fragment: '',
        )
        .toString();

    final openedInSameTab = openUrlInCurrentTab(target);
    if (!openedInSameTab) {
      openUrlInNewTab(target);
    }
  }

  Widget _buildLoginCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 40, color: colorScheme.primary),
            const SizedBox(height: 10),
            Text('SmartSFA', style: textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Entrar com conta Google', style: textTheme.bodyMedium),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Codigo: ${_error!.code}',
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _error!.message,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            FilledButton.icon(
              onPressed: _loading ? null : _signInWithGoogle,
              icon: const Icon(Icons.login),
              label: Text(_loading ? 'Entrando...' : 'Continuar com Google'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: const Text('Entrar com e-mail/senha (suporte)'),
              childrenPadding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 10),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration(
                    colorScheme,
                    label: 'E-mail',
                    icon: Icons.alternate_email,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: _inputDecoration(
                    colorScheme,
                    label: 'Senha',
                    icon: Icons.lock_outline,
                  ),
                  onSubmitted: (_) => _signInWithEmailPassword(),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithEmailPassword,
                  icon: const Icon(Icons.alternate_email),
                  label: const Text('Entrar com e-mail/senha'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidePanel(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.14),
            colorScheme.secondary.withValues(alpha: 0.1),
          ],
        ),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Portal de Clientes SmartSFA',
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            'Acesse pedidos, clientes, tabelas de preco e billing em um unico ambiente, com controle por tenant e representada.',
            style: textTheme.bodyLarge,
          ),
          const SizedBox(height: 18),
          _siteInfoRow(context, Icons.public_outlined, 'Area publica com planos e informacoes institucionais.'),
          const SizedBox(height: 10),
          _siteInfoRow(context, Icons.payments_outlined, 'Checkout e gestao de assinatura no Billing do portal.'),
          const SizedBox(height: 10),
          _siteInfoRow(context, Icons.security_outlined, 'Acesso administrativo separado em URL dedicada.'),
          const Spacer(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _openPublicPage('/'),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Voltar para o site'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openPublicPage('/planos'),
                icon: const Icon(Icons.view_carousel_outlined),
                label: const Text('Ver planos'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openPublicPage('/terms'),
                icon: const Icon(Icons.gavel_outlined),
                label: const Text('Termos'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _siteInfoRow(BuildContext context, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 920;
                    if (!isWide) {
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildSidePanel(context),
                            const SizedBox(height: 16),
                            _buildLoginCard(context),
                          ],
                        ),
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildSidePanel(context)),
                        const SizedBox(width: 20),
                        SizedBox(width: 460, child: _buildLoginCard(context)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    ColorScheme colorScheme, {
    required String label,
    required IconData icon,
  }) {
    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      prefixIcon: Icon(icon, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: border(colorScheme.outlineVariant.withValues(alpha: 0.32)),
      focusedBorder: border(
        colorScheme.primary.withValues(alpha: 0.5),
        width: 1.25,
      ),
      errorBorder: border(colorScheme.error.withValues(alpha: 0.72)),
      focusedErrorBorder: border(colorScheme.error, width: 1.25),
    );
  }
}
