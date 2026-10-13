import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_error_info.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
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

  InputDecoration _loginInputDecoration(
    BuildContext context, {
    required String label,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18),
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.26),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: border(colorScheme.outlineVariant.withValues(alpha: 0.32)),
      focusedBorder: border(
        colorScheme.primary.withValues(alpha: 0.48),
        width: 1.25,
      ),
      errorBorder: border(colorScheme.error.withValues(alpha: 0.72)),
      focusedErrorBorder: border(colorScheme.error, width: 1.25),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SmartSFA', style: textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Acesso corporativo com liberacao interna.',
                    style: textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Codigo: ${_error!.code}',
                            style: textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _error!.message,
                            style: textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Veja o manual de codigos em docs/firebase/auth_error_codes.md',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _loading ? null : _signInWithGoogle,
                    icon: const Icon(Icons.login),
                    label: Text(
                      _loading ? 'Entrando...' : 'Entrar com Google da empresa',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _loginInputDecoration(
                      context,
                      label: 'E-mail',
                      icon: Icons.alternate_email,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: _loginInputDecoration(
                      context,
                      label: 'Senha',
                      icon: Icons.lock_outline,
                    ),
                    onSubmitted: (_) => _signInWithEmailPassword(),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _signInWithEmailPassword,
                    icon: const Icon(Icons.alternate_email),
                    label: const Text('Entrar com e-mail/senha do Firebase'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
