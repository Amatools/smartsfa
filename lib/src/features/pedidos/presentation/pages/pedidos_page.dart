import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/pedido.dart';
import '../../../../core/repositories/pedido_repository.dart';

class PedidosPage extends StatelessWidget {
  const PedidosPage({
    super.key,
    required this.identity,
    required this.repository,
  });

  final AppIdentity identity;
  final PedidoRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Pedido>>(
      stream: repository.watchAll(tenantId: identity.tenantId),
      initialData: const [],
      builder: (context, snapshot) {
        final pedidos = snapshot.data ?? const [];

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderCard(
                  title: 'Pedidos',
                  subtitle:
                      'Fila offline-first com status de envio e visao por responsavel.',
                  actionLabel: 'Novo pedido',
                  onAction: () => _showSoon(context, 'Criacao de pedido'),
                ),
                const SizedBox(height: 16),
                if (pedidos.isEmpty)
                  const _EmptyState(
                    title: 'Nenhum pedido carregado',
                    subtitle:
                        'Os pedidos locais aparecerão aqui assim que a fila for preenchida.',
                  )
                else
                  ...pedidos.map(_PedidoCard.new),
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

class _PedidoCard extends StatelessWidget {
  const _PedidoCard(this.pedido);

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text('Pedido ${pedido.id}'),
        subtitle: Text(
          '${pedido.origemPedido.label} · ${pedido.statusFila.label} · ${pedido.clienteReferencia?.nomeSnapshot ?? '-'}',
        ),
        trailing: Text(pedido.vendedorId ?? '-'),
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