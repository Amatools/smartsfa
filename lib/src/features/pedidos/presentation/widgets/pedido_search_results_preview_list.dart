import 'package:flutter/material.dart';

import '../../../../core/models/produto.dart';

/// Inline (inline, non-modal) preview list of up to [visibleResults] shown
/// below the desktop search bar, plus a "ver todos" button when there are
/// more results than fit the preview. Purely presentational.
class PedidoSearchResultsPreviewList extends StatelessWidget {
  const PedidoSearchResultsPreviewList({
    super.key,
    required this.visibleResults,
    required this.searchResultsCount,
    required this.hasMoreResults,
    required this.saving,
    required this.resolveCommercialCode,
    required this.formatMoneyBr,
    required this.onAddProduct,
    required this.onViewAllResults,
  });

  final List<Produto> visibleResults;
  final int searchResultsCount;
  final bool hasMoreResults;
  final bool saving;
  final String Function(Produto product) resolveCommercialCode;
  final String Function(double value) formatMoneyBr;
  final Future<void> Function(Produto product) onAddProduct;
  final VoidCallback onViewAllResults;

  @override
  Widget build(BuildContext context) {
    if (visibleResults.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visibleResults.length,
          separatorBuilder: (_, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final product = visibleResults[index];
            final displayCode = resolveCommercialCode(product);
            return Material(
              type: MaterialType.transparency,
              child: ListTile(
                dense: true,
                onTap: saving ? null : () => onAddProduct(product),
                title: Text(product.descricao),
                subtitle: Text(
                  '${displayCode.isEmpty ? '-' : displayCode} · ${product.marca?.trim().isEmpty ?? true ? '-' : product.marca} · NCM ${product.ncm?.trim().isEmpty ?? true ? '-' : product.ncm} · R\$ ${formatMoneyBr(product.valorBruto ?? 0)}',
                ),
                trailing: IconButton.filledTonal(
                  tooltip: 'Adicionar ao pedido',
                  onPressed: saving ? null : () => onAddProduct(product),
                  icon: const Icon(Icons.add),
                ),
              ),
            );
          },
        ),
        if (hasMoreResults) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: saving ? null : onViewAllResults,
              icon: const Icon(Icons.open_in_new),
              label: Text('Ver todos os resultados ($searchResultsCount)'),
            ),
          ),
        ],
      ],
    );
  }
}
