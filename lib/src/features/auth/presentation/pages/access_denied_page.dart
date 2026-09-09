import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AccessDeniedPage extends StatelessWidget {
  const AccessDeniedPage({
    super.key,
    required this.user,
    required this.role,
  });

  final User user;
  final String role;

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
                Text(
                  'Acesso bloqueado',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text('Usuario: ${user.email ?? user.uid}'),
                const SizedBox(height: 8),
                Text('Perfil atual: $role'),
                const SizedBox(height: 16),
                const Text('Seu login existe, mas ainda nao esta ativo neste tenant.'),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Sair'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}