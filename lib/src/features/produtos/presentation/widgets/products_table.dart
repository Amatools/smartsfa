import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';

typedef ProductThumbnailBuilder = Widget Function(Produto produto);
typedef ProductPriceFormatter = String Function(Produto produto);

class ProductsTable extends StatelessWidget {
  const ProductsTable({
    super.key,
    required this.produtos,
    required this.updatingStatusProductIds,
    required this.onToggleStatus,
    required this.onOpen,
    required this.thumbnailBuilder,
    required this.priceFormatter,
  });

  final List<Produto> produtos;
  final Set<String> updatingStatusProductIds;
  final void Function(Produto produto) onToggleStatus;
  final void Function(Produto produto) onOpen;
  final ProductThumbnailBuilder thumbnailBuilder;
  final ProductPriceFormatter priceFormatter;

  // Kept for hot-reload compatibility after refactoring away from Table.
  // ignore: unused_field
  static const Map<int, TableColumnWidth> _columnWidths = {
    0: FixedColumnWidth(_ProductTableLayout.eyeColumnWidth),
    1: FixedColumnWidth(_ProductTableLayout.thumbnailColumnWidth),
    2: FixedColumnWidth(_ProductTableLayout.columnGap),
    3: FixedColumnWidth(_ProductTableLayout.codeColumnWidth),
    4: FixedColumnWidth(_ProductTableLayout.columnGap),
    5: FlexColumnWidth(),
    6: FixedColumnWidth(_ProductTableLayout.columnGap),
    7: FixedColumnWidth(_ProductTableLayout.priceColumnWidth),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    );
    const rowTextStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: Colors.black87,
    );
    final dividerColor = theme.colorScheme.outline.withValues(alpha: 0.2);
    final alternateRowColor = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _ProductTableLayout.minTableWidth;
        final tableWidth = math.max(availableWidth, _ProductTableLayout.minTableWidth);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _ProductTableLayout.rowHorizontalPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderRow(
                    dividerColor: dividerColor,
                    style: headerStyle,
                  ),
                  for (var i = 0; i < produtos.length; i++)
                    _buildProductRow(
                      context: context,
                      produto: produtos[i],
                      rowTextStyle: rowTextStyle,
                      statusUpdating: updatingStatusProductIds.contains(produtos[i].id),
                      onToggleStatus: () => onToggleStatus(produtos[i]),
                      onTap: () => onOpen(produtos[i]),
                      backgroundColor: i.isOdd ? alternateRowColor : Colors.transparent,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow({
    required Color dividerColor,
    required TextStyle style,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: _ProductTableLayout.eyeColumnWidth),
          SizedBox(
            width: _ProductTableLayout.thumbnailColumnWidth,
            child: Text('Fotos', style: style),
          ),
          const SizedBox(width: _ProductTableLayout.columnGap),
          SizedBox(
            width: _ProductTableLayout.codeColumnWidth,
            child: Text('Código', style: style),
          ),
          const SizedBox(width: _ProductTableLayout.columnGap),
          Expanded(
            child: Text('Nome', style: style),
          ),
          const SizedBox(width: _ProductTableLayout.columnGap),
          SizedBox(
            width: _ProductTableLayout.priceColumnWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Preço', style: style, textAlign: TextAlign.right),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow({
    required BuildContext context,
    required Produto produto,
    required TextStyle rowTextStyle,
    required bool statusUpdating,
    required VoidCallback onToggleStatus,
    required VoidCallback onTap,
    required Color backgroundColor,
  }) {
    final theme = Theme.of(context);
    final isActive = produto.status == ProductStatus.active;
    final codigo = (produto.codigoFabricante ?? '').trim();

    Widget tappableCell(Widget child, {bool alignRight = false}) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Align(
            alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          ),
        ),
      );
    }

    return Container(
      color: backgroundColor,
      child: Row(
        children: [
          SizedBox(
            width: _ProductTableLayout.eyeColumnWidth,
            child: Center(
              child: statusUpdating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: isActive ? 'Inativar produto' : 'Ativar produto',
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: onToggleStatus,
                      icon: Icon(
                        isActive ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: isActive ? theme.colorScheme.primary : theme.colorScheme.error,
                      ),
                    ),
            ),
          ),
          SizedBox(
            width: _ProductTableLayout.thumbnailColumnWidth,
            child: tappableCell(thumbnailBuilder(produto)),
          ),
          const SizedBox(width: _ProductTableLayout.columnGap),
          SizedBox(
            width: _ProductTableLayout.codeColumnWidth,
            child: tappableCell(
              Text(
                codigo.isEmpty ? '---' : codigo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: rowTextStyle,
              ),
            ),
          ),
          const SizedBox(width: _ProductTableLayout.columnGap),
          Expanded(
            child: tappableCell(
              Text(
                produto.descricao.trim().isEmpty ? '---' : produto.descricao,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: rowTextStyle,
              ),
            ),
          ),
          const SizedBox(width: _ProductTableLayout.columnGap),
          SizedBox(
            width: _ProductTableLayout.priceColumnWidth,
            child: tappableCell(
              Text(
                priceFormatter(produto),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: rowTextStyle,
                textAlign: TextAlign.right,
              ),
              alignRight: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTableLayout {
  static const double rowHorizontalPadding = 16;
  static const double eyeColumnWidth = 40;
  static const double thumbnailColumnWidth = 44;
  static const double codeColumnWidth = 120;
  static const double priceColumnWidth = 130;
  static const double columnGap = 24;
  static const double minNameColumnWidth = 220;

  static const double minTableWidth =
      eyeColumnWidth +
      thumbnailColumnWidth +
      codeColumnWidth +
      priceColumnWidth +
      (columnGap * 3) +
      minNameColumnWidth +
      (rowHorizontalPadding * 2);
}
