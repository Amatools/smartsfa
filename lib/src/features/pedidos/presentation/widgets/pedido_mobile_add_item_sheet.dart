import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/produto.dart';

/// Mobile "add item" bottom sheet: search box + quantity + results list.
/// Owns its own local search/quantity state; all business logic (product
/// search, quantity parsing, formatting, and adding the product to the
/// pedido) is supplied by the parent via callbacks.
class PedidoMobileAddItemSheet extends StatefulWidget {
  const PedidoMobileAddItemSheet({
    super.key,
    required this.saving,
    required this.normalizeSearch,
    required this.buildProductResultsForQuery,
    required this.readIntegerQuantity,
    required this.resolveCommercialCode,
    required this.formatMoneyBr,
    required this.inputDecoration,
    required this.onAddProduct,
  });

  final bool saving;
  final String Function(String value) normalizeSearch;
  final List<Produto> Function(String query) buildProductResultsForQuery;
  final int Function(String raw) readIntegerQuantity;
  final String Function(Produto product) resolveCommercialCode;
  final String Function(double value) formatMoneyBr;
  final InputDecoration Function({required String label}) inputDecoration;
  final Future<void> Function(Produto product, {required int quantityOverride})
  onAddProduct;

  @override
  State<PedidoMobileAddItemSheet> createState() =>
      _PedidoMobileAddItemSheetState();
}

class _PedidoMobileAddItemSheetState extends State<PedidoMobileAddItemSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );
  String _localQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _addSelectedProduct(Produto product) async {
    final quantity = widget.readIntegerQuantity(_quantityController.text);
    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe uma quantidade inteira maior que zero para adicionar.',
          ),
        ),
      );
      return;
    }

    final sheetNavigator = Navigator.of(context);
    await widget.onAddProduct(product, quantityOverride: quantity);
    if (!mounted) {
      return;
    }
    if (sheetNavigator.canPop()) {
      sheetNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalized = widget.normalizeSearch(_localQuery);
    final results = normalized.isEmpty
        ? const <Produto>[]
        : widget.buildProductResultsForQuery(_localQuery).take(120).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.84,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Adicionar item ao pedido',
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) {
                        setState(() {
                          _localQuery = value;
                        });
                      },
                      decoration: widget
                          .inputDecoration(
                            label: 'Buscar por descrição, código, marca ou NCM',
                          )
                          .copyWith(prefixIcon: const Icon(Icons.search)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      decoration: widget.inputDecoration(label: 'Qtd'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (normalized.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Digite para buscar produtos.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    results.isEmpty
                        ? 'Nenhum item compatível com essa busca.'
                        : 'Resultados: ${results.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: results.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = results[index];
                        final displayCode = widget.resolveCommercialCode(
                          product,
                        );
                        return ListTile(
                          dense: true,
                          onTap: widget.saving
                              ? null
                              : () => _addSelectedProduct(product),
                          title: Text(product.descricao),
                          subtitle: Text(
                            '${displayCode.isEmpty ? '-' : displayCode} · ${product.marca?.trim().isEmpty ?? true ? '-' : product.marca} · NCM ${product.ncm?.trim().isEmpty ?? true ? '-' : product.ncm} · R\$ ${widget.formatMoneyBr(product.valorBruto ?? 0)}',
                          ),
                          trailing: IconButton.filledTonal(
                            tooltip: 'Adicionar ao pedido',
                            onPressed: widget.saving
                                ? null
                                : () => _addSelectedProduct(product),
                            icon: const Icon(Icons.add),
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
