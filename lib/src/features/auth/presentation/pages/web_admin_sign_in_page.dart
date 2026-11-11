import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_error_info.dart';

class WebAdminSignInPage extends StatefulWidget {
  const WebAdminSignInPage({super.key});

  @override
  State<WebAdminSignInPage> createState() => _WebAdminSignInPageState();
}

class _WebAdminSignInPageState extends State<WebAdminSignInPage> {
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 40,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(height: 10),
                      Text('SmartSFA Admin', style: textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Entrar no painel administrativo',
                        style: textTheme.bodyMedium,
                      ),
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
                                style: TextStyle(
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      FilledButton.icon(
                        onPressed: _loading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.login),
                        label: Text(
                          _loading ? 'Entrando...' : 'Continuar com Google',
                        ),
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
                        title: const Text('Entrar com e-mail/senha (suporte interno)'),
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
                            onPressed: _loading
                                ? null
                                : _signInWithEmailPassword,
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
