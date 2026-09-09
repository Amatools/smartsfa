import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/cliente.dart';
import '../../../../core/repositories/cliente_repository.dart';

class ClientesPage extends StatelessWidget {
  const ClientesPage({
    super.key,
    required this.identity,
    required this.repository,
  });

  final AppIdentity identity;
  final ClienteRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Cliente>>(
      stream: repository.watchAll(tenantId: identity.tenantId),
      initialData: const [],
      builder: (context, snapshot) {
        final clientes = snapshot.data ?? const [];

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderCard(
                  title: 'Clientes',
                  subtitle:
                      'Base visivel do tenant ${identity.tenantName} com carga local-first.',
                  actionLabel: 'Novo cliente',
                  onAction: () => _showSoon(context, 'Cadastro de cliente'),
                ),
                const SizedBox(height: 16),
                if (clientes.isEmpty)
                  const _EmptyState(
                    title: 'Nenhum cliente carregado',
                    subtitle:
                        'Os primeiros clientes aparecem aqui quando a base for sincronizada.',
                  )
                else
                  ...clientes.map(_ClienteCard.new),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(subtitle),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _ClienteCard extends StatelessWidget {
  const _ClienteCard(this.cliente);

  final Cliente cliente;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(cliente.nome),
        subtitle: Text(
          '${cliente.documento} · ${cliente.origemCadastro.label} · ${cliente.status.label}',
        ),
        trailing: Text(cliente.vendedorId ?? '-'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
      ),
    );
  }
}

void _showSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$feature ainda esta em construcao.')),
  );
}