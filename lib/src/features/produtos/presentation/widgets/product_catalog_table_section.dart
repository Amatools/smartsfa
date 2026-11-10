import 'package:flutter/material.dart';

import '../../../../core/models/produto.dart';
import '../../../../shared/presentation/widgets/product_image_preview_dialog.dart';
import 'product_thumbnail.dart';
import 'products_table.dart';

class ProductCatalogTableSection extends StatefulWidget {
  const ProductCatalogTableSection({
    super.key,
    required this.visibleProducts,
    required this.updatingStatusProductIds,
    required this.onToggleStatus,
    required this.onOpen,
    required this.currentPage,
    required this.hasPreviousPage,
    required this.hasNextPage,
    required this.loadingPage,
    required this.pageSize,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.priceFormatter,
  });

  final List<Produto> visibleProducts;
  final Set<String> updatingStatusProductIds;
  final ValueChanged<Produto> onToggleStatus;
  final ValueChanged<Produto> onOpen;
  final int currentPage;
  final bool hasPreviousPage;
  final bool hasNextPage;
  final bool loadingPage;
  final int pageSize;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final String Function(Produto produto) priceFormatter;

  @override
  State<ProductCatalogTableSection> createState() =>
      _ProductCatalogTableSectionState();
}

class _ProductCatalogTableSectionState extends State<ProductCatalogTableSection> {
  ProductsTableSortField _sortField = ProductsTableSortField.name;
  bool _sortAscending = true;

  int _compareString(String a, String b) {
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  int _compareDouble(double? a, double? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }

  List<Produto> _sortedProducts(List<Produto> products) {
    final sorted = List<Produto>.from(products);
    sorted.sort((a, b) {
      final result = switch (_sortField) {
        ProductsTableSortField.code =>
          _compareString(
            ProductsTable.resolveDisplayCode(a),
            ProductsTable.resolveDisplayCode(b),
          ),
        ProductsTableSortField.name =>
          _compareString(a.descricao.trim(), b.descricao.trim()),
        ProductsTableSortField.price => _compareDouble(a.valorBruto, b.valorBruto),
      };
      if (_sortAscending) {
        return result;
      }
      return -result;
    });
    return sorted;
  }

  void _handleSort(ProductsTableSortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sortedProducts = _sortedProducts(widget.visibleProducts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProductsTable(
          produtos: sortedProducts,
          updatingStatusProductIds: widget.updatingStatusProductIds,
          onToggleStatus: widget.onToggleStatus,
          onOpen: widget.onOpen,
          onPreviewImage: (produto) {
            showProductImagePreviewDialog(context: context, produto: produto);
          },
          thumbnailBuilder: (produto) =>
              ProductThumbnail(produto: produto, size: 28),
          priceFormatter: widget.priceFormatter,
          sortField: _sortField,
          sortAscending: _sortAscending,
          onSortRequested: _handleSort,
        ),
        if (sortedProducts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                if (compact) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Pagina anterior',
                        onPressed: widget.loadingPage || !widget.hasPreviousPage
                            ? null
                            : widget.onPreviousPage,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        widget.loadingPage
                            ? 'Carregando...'
                            : 'Pagina ${widget.currentPage + 1}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      IconButton(
                        tooltip: 'Proxima pagina',
                        onPressed: widget.loadingPage || !widget.hasNextPage
                            ? null
                            : widget.onNextPage,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Pagina anterior',
                      onPressed: widget.loadingPage || !widget.hasPreviousPage
                          ? null
                          : widget.onPreviousPage,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(
                      widget.loadingPage
                          ? 'Carregando...'
                          : 'Pagina ${widget.currentPage + 1}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    IconButton(
                      tooltip: 'Proxima pagina',
                      onPressed: widget.loadingPage || !widget.hasNextPage
                          ? null
                          : widget.onNextPage,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                );
              },
            ),
          ),
        if (sortedProducts.isEmpty)
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
