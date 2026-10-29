import 'package:flutter/material.dart';

/// Top chrome bar of the pedido inline editor: back button, title, and close
/// button. Purely presentational.
class PedidoEditorTopBar extends StatelessWidget {
  const PedidoEditorTopBar({
    super.key,
    required this.title,
    required this.compact,
    required this.canClose,
    required this.chromeColor,
    required this.onClose,
  });

  final String title;
  final bool compact;
  final bool canClose;
  final Color chromeColor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final iconConstraints = BoxConstraints(
      minWidth: compact ? 24 : 34,
      minHeight: compact ? 24 : 34,
    );

    return Container(
      width: double.infinity,
      color: chromeColor,
      padding: compact
          ? const EdgeInsets.fromLTRB(6, 0, 2, 0)
          : const EdgeInsets.fromLTRB(8, 2, 4, 2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Voltar para pedidos',
            onPressed: canClose ? onClose : null,
            icon: Icon(Icons.arrow_back_outlined, size: compact ? 20 : 24),
            visualDensity: VisualDensity.compact,
            constraints: iconConstraints,
            padding: EdgeInsets.zero,
          ),
          SizedBox(width: compact ? 2 : 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: compact
                      ? Theme.of(context).textTheme.labelLarge
                      : Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fechar editor',
            onPressed: canClose ? onClose : null,
            icon: Icon(Icons.close, size: compact ? 20 : 24),
            visualDensity: VisualDensity.compact,
            constraints: iconConstraints,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
