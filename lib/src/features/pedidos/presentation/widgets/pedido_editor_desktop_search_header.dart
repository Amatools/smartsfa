import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Desktop/wide layout search row (search field + quantity + add button)
/// plus the results-count hint text, used above the item list in the pedido
/// inline editor. Purely presentational.
class PedidoEditorDesktopSearchHeader extends StatelessWidget {
  const PedidoEditorDesktopSearchHeader({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.quantityController,
    required this.saving,
    required this.hasQuery,
    required this.visibleResultsCount,
    required this.searchResultsCount,
    required this.inputDecoration,
    required this.onSearchChanged,
    required this.onSubmitSearch,
    required this.onOpenSearchModal,
    required this.onAddFirstVisibleResult,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final TextEditingController quantityController;
  final bool saving;
  final bool hasQuery;
  final int visibleResultsCount;
  final int searchResultsCount;
  final InputDecoration Function({required String label}) inputDecoration;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSubmitSearch;
  final VoidCallback onOpenSearchModal;
  final VoidCallback? onAddFirstVisibleResult;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 560;

            final searchField = TextField(
              controller: searchController,
              focusNode: searchFocusNode,
              enabled: !saving,
              textInputAction: TextInputAction.search,
              onChanged: onSearchChanged,
              onSubmitted: (_) {
                if (!saving) {
                  onSubmitSearch();
                }
              },
              decoration:
                  inputDecoration(
                    label: 'Pesquisar produto (descrição, código, marca, NCM)',
                  ).copyWith(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Abrir busca completa',
                      onPressed: saving ? null : onOpenSearchModal,
                      icon: const Icon(Icons.manage_search_outlined),
                    ),
                  ),
            );

            final quantityField = TextField(
              controller: quantityController,
              enabled: !saving,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              decoration: inputDecoration(label: 'Qtd'),
            );

            final addButton = FilledButton.icon(
              onPressed: onAddFirstVisibleResult,
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('Adicionar'),
            );

            if (!isCompact) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 12),
                  SizedBox(width: 110, child: quantityField),
                  const SizedBox(width: 12),
                  addButton,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                searchField,
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 110, child: quantityField),
                    const SizedBox(width: 10),
                    Expanded(child: addButton),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          !hasQuery
              ? 'Digite na busca para listar produtos.'
              : visibleResultsCount == 0
              ? 'Nenhum item compatível com essa busca.'
              : 'Resultados: $searchResultsCount (exibindo $visibleResultsCount).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
