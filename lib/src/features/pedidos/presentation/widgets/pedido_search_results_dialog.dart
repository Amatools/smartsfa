import 'package:flutter/material.dart';

import '../../../../core/models/produto.dart';

/// Dialog listing search results for the item-add flow (desktop/wide
/// layout). Purely presentational: product list, formatting, and the "add"
/// action are supplied by the parent.
class PedidoSearchResultsDialog extends StatelessWidget {
  const PedidoSearchResultsDialog({
    super.key,
    required this.searchResults,
    required this.saving,
    required this.resolveCommercialCode,
    required this.formatMoneyBr,
    required this.onAddProduct,
  });

  final List<Produto> searchResults;
  final bool saving;
  final String Function(Produto product) resolveCommercialCode;
  final String Function(double value) formatMoneyBr;
  final Future<void> Function(Produto product) onAddProduct;

  @override
  Widget build(BuildContext context) {
    final limitedResults = searchResults.take(200).toList();
    final hasTruncated = searchResults.length > limitedResults.length;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: MediaQuery.of(context).size.height * 0.84,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Resultados da busca (${searchResults.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar busca',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (hasTruncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Exibindo ${limitedResults.length} de ${searchResults.length}. Refine a busca para reduzir o volume.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: limitedResults.length,
                separatorBuilder: (_, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = limitedResults[index];
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
            ),
          ],
        ),
      ),
    );
  }
}
