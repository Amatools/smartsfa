import 'package:flutter/material.dart';

import '../../../../core/models/produto.dart';
import 'product_thumbnail.dart';
import 'products_table.dart';

class ProductCatalogTableSection extends StatelessWidget {
  const ProductCatalogTableSection({
    super.key,
    required this.visibleProducts,
    required this.updatingStatusProductIds,
    required this.onToggleStatus,
    required this.onOpen,
    required this.priceFormatter,
  });

  final List<Produto> visibleProducts;
  final Set<String> updatingStatusProductIds;
  final ValueChanged<Produto> onToggleStatus;
  final ValueChanged<Produto> onOpen;
  final String Function(Produto produto) priceFormatter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProductsTable(
          produtos: visibleProducts,
          updatingStatusProductIds: updatingStatusProductIds,
          onToggleStatus: onToggleStatus,
          onOpen: onOpen,
          thumbnailBuilder: (produto) => ProductThumbnail(produto: produto, size: 28),
          priceFormatter: priceFormatter,
        ),
        if (visibleProducts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Nenhum produto carregado ainda para este contexto.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
