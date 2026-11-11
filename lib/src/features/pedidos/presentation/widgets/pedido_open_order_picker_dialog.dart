import 'package:flutter/material.dart';

import '../../../../core/models/pedido.dart';
import '../services/pedido_format_utils.dart';

class PedidoOpenOrderPickerDialog extends StatefulWidget {
  const PedidoOpenOrderPickerDialog({
    super.key,
    required this.orders,
    required this.contextLabel,
  });

  final List<Pedido> orders;
  final String contextLabel;

  @override
  State<PedidoOpenOrderPickerDialog> createState() =>
      _PedidoOpenOrderPickerDialogState();
}

class _PedidoOpenOrderPickerDialogState
    extends State<PedidoOpenOrderPickerDialog> {
  String? _selectedOrderId;

  @override
  void initState() {
    super.initState();
    if (widget.orders.length == 1) {
      _selectedOrderId = widget.orders.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Selecionar pedido em aberto',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Origem do item: ${widget.contextLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: RadioGroup<String>(
                groupValue: _selectedOrderId,
                onChanged: (value) {
                  setState(() {
                    _selectedOrderId = value;
                  });
                },
                child: ListView.separated(
                  itemCount: widget.orders.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final order = widget.orders[index];
                    final orderNumber = PedidoFormatUtils.pedidoDisplayNumber(
                      order.id,
                    );
                    final customerName =
                        (order.clienteReferencia?.nomeSnapshot ?? '').trim();
                    final customerDisplay = customerName.isEmpty
                        ? '-'
                        : customerName;

                    return RadioListTile<String>(
                      value: order.id,
                      title: Text('Pedido $orderNumber'),
                      subtitle: Text(
                        'Status: ${order.statusFila.label} · Cliente: $customerDisplay\nItens: ${order.itens.length} · Total: R\$ ${PedidoFormatUtils.formatMoneyBr(order.totalBruto)}',
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selectedOrderId == null
                        ? null
                        : () => Navigator.of(context).pop(_selectedOrderId),
                    child: const Text('Adicionar item'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
