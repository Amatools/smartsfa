import 'package:flutter/material.dart';

import '../../../../core/models/pedido.dart';
import '../services/pedido_format_utils.dart';

/// List item card for a single pedido in the pedidos list page. Extracted
/// from `pedidos_page.dart` (SRP).
class PedidoCard extends StatelessWidget {
  const PedidoCard(
    this.pedido, {
    super.key,
    required this.syncedRemotely,
    required this.selected,
    this.onTap,
    this.onPrimaryAction,
    required this.primaryActionTooltip,
    required this.primaryActionIcon,
    this.onEdit,
    this.onPreviewPdf,
    this.onDelete,
  });

  final Pedido pedido;
  final bool syncedRemotely;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onPrimaryAction;
  final String primaryActionTooltip;
  final IconData primaryActionIcon;
  final VoidCallback? onEdit;
  final VoidCallback? onPreviewPdf;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      color: selected
          ? Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.45)
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.receipt_long_outlined),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pedido ${PedidoFormatUtils.pedidoDisplayNumber(pedido.id)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${pedido.origemPedido.label} · ${pedido.statusFila.label} · ${pedido.clienteReferencia?.nomeSnapshot ?? '-'}\n'
                      'Itens: ${pedido.itens.length} · Quantidade: ${pedido.totalItens.toStringAsFixed(2)} · Total: R\$ ${PedidoFormatUtils.formatMoneyBr(pedido.totalBruto)}\n'
                      'Forma de pagamento: ${((pedido.formaPagamento ?? '').trim().isEmpty ? '-' : pedido.formaPagamento)}\n'
                      'Finalidade: ${pedido.salePurpose.label}\n'
                      'Origem empresa: ${pedido.originCompanyUnitLabel ?? '-'}${(pedido.originCompanyUf ?? '').trim().isEmpty ? '' : ' (${pedido.originCompanyUf})'}\n'
                      'Sync: ${syncedRemotely ? 'sincronizado' : 'pendente'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: IconButton(
                        tooltip: primaryActionTooltip,
                        icon: Icon(primaryActionIcon),
                        onPressed: onPrimaryAction,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: IconButton(
                        tooltip: 'Editar pedido',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: onEdit,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: IconButton(
                        tooltip: 'Abrir PDF',
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        onPressed: onPreviewPdf,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: IconButton(
                        tooltip: 'Excluir pedido',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
