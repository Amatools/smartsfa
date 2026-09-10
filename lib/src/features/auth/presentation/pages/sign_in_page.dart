import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

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
      String message;
      switch (e.code) {
        case 'operation-not-allowed':
          message = 'Login Google desabilitado no Firebase. Habilite em Authentication > Sign-in method.';
          break;
        case 'unauthorized-domain':
          message = 'Dominio nao autorizado. Adicione o dominio atual em Authentication > Settings > Authorized domains.';
          break;
        case 'popup-blocked':
          message = 'Popup bloqueado pelo navegador. Libere popups para continuar o login.';
          break;
        case 'popup-closed-by-user':
          message = 'Login cancelado antes da confirmacao.';
          break;
        default:
          message = e.message ?? 'Falha ao autenticar com Google.';
      }

      setState(() {
        _error = message;
      });
    } catch (_) {
      setState(() {
        _error = 'Erro inesperado durante o login.';
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
        _error = 'Informe e-mail e senha para entrar.';
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
      String message;
      switch (e.code) {
        case 'operation-not-allowed':
          message = 'Login por e-mail/senha desabilitado no Firebase. Habilite em Authentication > Sign-in method.';
          break;
        case 'invalid-email':
          message = 'E-mail invalido.';
          break;
        case 'user-disabled':
          message = 'Usuario desabilitado.';
          break;
        case 'user-not-found':
          message = 'Usuario nao encontrado.';
          break;
        case 'wrong-password':
        case 'invalid-credential':
          message = 'Credenciais invalidas.';
          break;
        default:
          message = e.message ?? 'Falha ao autenticar com e-mail/senha.';
      }

      setState(() {
        _error = message;
      });
    } catch (_) {
      setState(() {
        _error = 'Erro inesperado durante o login.';
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
                      child: Text(
                        _error!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
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
