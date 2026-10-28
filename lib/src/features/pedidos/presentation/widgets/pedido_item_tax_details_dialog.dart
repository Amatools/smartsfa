import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';
import '../../../../core/models/pedido.dart';
import '../services/pedido_format_utils.dart';

/// Shows the read-only "detalhes fiscais" dialog for a single pedido item,
/// rendering the fields captured in its [PedidoItem.taxSnapshot] (regra
/// fiscal, tier de casamento, NCM/CEST, valores de IPI/ST/DIFAL/FCP, etc.).
///
/// Extracted from `_PedidoInlineEditorState._showItemTaxDetailsDialog` since
/// this is purely presentational and only depends on the item itself plus
/// pure formatting helpers.
void showPedidoItemTaxDetailsDialog(BuildContext context, PedidoItem item) {
  final snapshot = item.taxSnapshot;
  if (snapshot == null) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Detalhes fiscais'),
        content: Text(
          'Nenhum dado fiscal foi calculado para "${item.productName}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    return;
  }

  final tieBreaks = <String>[
    if (snapshot.matchedByBuyerRegime)
      'Desempate pelo regime tributario do comprador',
    if (snapshot.matchedByCest) 'Desempate por CEST',
  ];
  final profileLabel = (snapshot.operationProfileKey ?? '').isEmpty
      ? '-'
      : TaxOperationProfileKey.fromValue(snapshot.operationProfileKey!).label;
  final profileSourceLabel = snapshot.operationProfileSource == 'override'
      ? 'Override dinamico${snapshot.operationProfileOverrideId != null ? ' (id ${snapshot.operationProfileOverrideId})' : ''}'
      : 'Padrao nativo do motor';

  final rows = <(String, String)>[
    ('Regra fiscal aplicada', snapshot.regraFiscalId ?? '-'),
    (
      'Nivel do casamento',
      PedidoFormatUtils.taxMatchTierLabel(snapshot.matchedTier),
    ),
    if (tieBreaks.isNotEmpty) ('Criterios de desempate', tieBreaks.join(', ')),
    ('Perfil de operacao', profileLabel),
    ('Origem do perfil', profileSourceLabel),
    ('NCM', (snapshot.ncm ?? '-').isEmpty ? '-' : snapshot.ncm!),
    ('CEST', (snapshot.cest ?? '-').isEmpty ? '-' : snapshot.cest!),
    ('UF destino', snapshot.ufDestino ?? '-'),
    ('IPI', PedidoFormatUtils.formatMoney(snapshot.valorIpi ?? 0)),
    ('ICMS-ST', PedidoFormatUtils.formatMoney(snapshot.valorSt ?? 0)),
    ('DIFAL', PedidoFormatUtils.formatMoney(snapshot.valorDifal ?? 0)),
    ('FCP', PedidoFormatUtils.formatMoney(snapshot.valorFcp ?? 0)),
    ('FCP-ST', PedidoFormatUtils.formatMoney(snapshot.valorFcpSt ?? 0)),
    ('FCP-DIFAL', PedidoFormatUtils.formatMoney(snapshot.valorFcpDifal ?? 0)),
    (
      'Total do item',
      PedidoFormatUtils.formatMoney(snapshot.valorTotalItem ?? item.totalPrice),
    ),
  ];

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Detalhes fiscais — ${item.productName}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 160,
                        child: Text(
                          row.$1,
                          style: Theme.of(dialogContext).textTheme.labelMedium,
                        ),
                      ),
                      Expanded(child: Text(row.$2)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
