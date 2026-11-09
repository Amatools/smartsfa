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
        title: Text(
          'Detalhes fiscais',
          style: Theme.of(
            dialogContext,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
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

  // Linhas de cima: exibidas em linha inteira (label + valor lado a lado),
  // uma por vez - conteudo costuma ser mais longo (id de regra, lista de
  // criterios de desempate etc.) e nao cabe bem em 2 colunas estreitas.
  final fullWidthRows = <(String, String)>[
    ('Regra fiscal aplicada', snapshot.regraFiscalId ?? '-'),
    (
      'Nivel do casamento',
      PedidoFormatUtils.taxMatchTierLabel(snapshot.matchedTier),
    ),
    if (tieBreaks.isNotEmpty) ('Criterios de desempate', tieBreaks.join(', ')),
    ('Perfil de operacao', profileLabel),
    ('Origem do perfil', profileSourceLabel),
  ];

  // Dali pra baixo (a partir do NCM): campos curtos, exibidos em grade de
  // 2 colunas pra aproveitar melhor a largura em telas pequenas de mobile.
  final gridRows = <(String, String)>[
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
  final gridPairs = <List<(String, String)>>[
    for (var i = 0; i < gridRows.length; i += 2)
      gridRows.sublist(i, i + 2 > gridRows.length ? i + 1 : i + 2),
  ];

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final screenWidth = MediaQuery.of(dialogContext).size.width;
      const insetPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 16);
      const titlePadding = EdgeInsets.fromLTRB(16, 16, 16, 8);
      const contentPadding = EdgeInsets.fromLTRB(16, 8, 16, 8);
      final dialogWidth =
          screenWidth - insetPadding.horizontal - contentPadding.horizontal;

      Widget buildFullWidthRow(String label, String value) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: Text(label, style: theme.textTheme.labelMedium),
              ),
              Expanded(child: Text(value)),
            ],
          ),
        );
      }

      Widget buildGridCell(String label, String value) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(label, style: theme.textTheme.labelMedium),
            ),
            Expanded(child: Text(value)),
          ],
        );
      }

      return AlertDialog(
        insetPadding: insetPadding,
        titlePadding: titlePadding,
        contentPadding: contentPadding,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalhes fiscais',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.productName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in fullWidthRows)
                  buildFullWidthRow(row.$1, row.$2),
                const Divider(height: 12),
                for (final pair in gridPairs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: buildGridCell(pair[0].$1, pair[0].$2)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: pair.length > 1
                              ? buildGridCell(pair[1].$1, pair[1].$2)
                              : const SizedBox.shrink(),
                        ),
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
      );
    },
  );
}
