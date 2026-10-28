import 'package:flutter/material.dart';

import '../../../../core/models/pedido.dart';
import '../services/pedido_format_utils.dart';

/// Header action card used at the top of the pedidos (orders) list page.
/// Extracted from `pedidos_page.dart` (SRP).
class PedidoHeaderCard extends StatelessWidget {
  const PedidoHeaderCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.actionEnabled = true,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final bool actionEnabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(subtitle),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: actionEnabled ? onAction : null,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// List item card for a single pedido in the pedidos list page. Extracted
/// from `pedidos_page.dart` (SRP).
class PedidoCard extends StatelessWidget {
  const PedidoCard(
    this.pedido, {
    super.key,
    required this.syncedRemotely,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final Pedido pedido;
  final bool syncedRemotely;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      color: selected
          ? Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
          : null,
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(
          'Pedido ${PedidoFormatUtils.pedidoDisplayNumber(pedido.id)}',
        ),
        subtitle: Text(
          '${pedido.origemPedido.label} · ${pedido.statusFila.label} · ${pedido.clienteReferencia?.nomeSnapshot ?? '-'}\n'
          'Itens: ${pedido.itens.length} · Quantidade: ${pedido.totalItens.toStringAsFixed(2)} · Total: R\$ ${PedidoFormatUtils.formatMoneyBr(pedido.totalBruto)}\n'
          'Forma de pagamento: ${((pedido.formaPagamento ?? '').trim().isEmpty ? '-' : pedido.formaPagamento)}\n'
          'Finalidade: ${pedido.salePurpose.label}\n'
          'Origem empresa: ${pedido.originCompanyUnitLabel ?? '-'}${(pedido.originCompanyUf ?? '').trim().isEmpty ? '' : ' (${pedido.originCompanyUf})'}\n'
          'Sync: ${syncedRemotely ? 'sincronizado' : 'pendente'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Excluir pedido',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// Generic empty-state card used in the pedidos list page. Extracted from
/// `pedidos_page.dart` (SRP).
class PedidoEmptyState extends StatelessWidget {
  const PedidoEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
  });

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
