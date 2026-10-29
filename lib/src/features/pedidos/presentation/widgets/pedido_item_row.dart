import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/pedido.dart';
import '../../../../core/models/produto.dart';
import '../../../auth/services/workspace_profile_service.dart';

/// Renders a single order item row inside the pedido inline editor's item
/// list, in either the compact (mobile card) or wide (desktop table) layout.
class PedidoItemRow extends StatelessWidget {
  const PedidoItemRow({
    super.key,
    required this.item,
    required this.product,
    required this.index,
    required this.isCompactItems,
    required this.saving,
    required this.policyFields,
    required this.columnWidths,
    required this.rowHorizontalPadding,
    required this.actionSlotWidth,
    required this.resolveItemDisplayCode,
    required this.formatPercent,
    required this.formatMoney,
    required this.formatQuantity,
    required this.readIntegerQuantity,
    required this.formatPointDiscountSummary,
    required this.ensureDiscountControllersForItem,
    required this.buildItemThumbnail,
    required this.showItemTaxDetailsDialog,
    required this.onDecrementQuantity,
    required this.onIncrementQuantity,
    required this.onSetQuantity,
    required this.onApplyInlineDiscounts,
    required this.onRemoveDiscountField,
    required this.onAddDiscountField,
    required this.onRemoveItem,
  });

  final PedidoItem item;
  final Produto? product;
  final int index;
  final bool isCompactItems;
  final bool saving;
  final List<OrderDiscountFieldRule> policyFields;
  final Map<int, TableColumnWidth> columnWidths;
  final double rowHorizontalPadding;
  final double actionSlotWidth;
  final String Function(PedidoItem item, Produto? product)
  resolveItemDisplayCode;
  final String Function(double value) formatPercent;
  final String Function(double value) formatMoney;
  final String Function(double value) formatQuantity;
  final int Function(String raw) readIntegerQuantity;
  final String Function(List<double> discounts) formatPointDiscountSummary;
  final List<TextEditingController> Function(PedidoItem item, int slotCount)
  ensureDiscountControllersForItem;
  final Widget Function(Produto? product, String productName)
  buildItemThumbnail;
  final void Function(PedidoItem item) showItemTaxDetailsDialog;
  final Future<void> Function(int index) onDecrementQuantity;
  final Future<void> Function(int index) onIncrementQuantity;
  final Future<void> Function(int index, int nextQuantity) onSetQuantity;
  final Future<bool> Function(int index, {bool showErrors})
  onApplyInlineDiscounts;
  final Future<void> Function(int itemIndex, int discountIndex)
  onRemoveDiscountField;
  final Future<void> Function(int index) onAddDiscountField;
  final VoidCallback onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final snapshot = item.taxSnapshot;
    final displayCode = resolveItemDisplayCode(item, product);
    final ipi = snapshot?.aliquotaIpiPercent ?? product?.aliquotaIpiBase;
    final ncm = (snapshot?.ncm ?? item.ncm ?? '').trim();
    final cest = (snapshot?.cest ?? '').trim();
    final ipiText = ipi == null ? 'IPI -' : 'IPI ${formatPercent(ipi)}';
    final fiscalMetaText = [
      if (ncm.isNotEmpty) 'NCM $ncm',
      if (cest.isNotEmpty) 'CEST $cest',
    ].join(' · ');
    final discountSummary = formatPointDiscountSummary(
      item.appliedDiscountPercents,
    );
    final maxDiscountSlots = policyFields.length;
    final activeDiscountSlots = item.appliedDiscountPercents.length;
    final canAddDiscountSlot =
        maxDiscountSlots > 0 && activeDiscountSlots < maxDiscountSlots;
    final inlineDiscountControllers = activeDiscountSlots > 0
        ? ensureDiscountControllersForItem(item, activeDiscountSlots)
        : const <TextEditingController>[];

    if (isCompactItems) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildItemThumbnail(product, item.productName),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$displayCode · ${item.productName}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => showItemTaxDetailsDialog(item),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  fiscalMetaText.isEmpty
                                      ? '$ipiText · ICMS-ST por regra fiscal'
                                      : '$ipiText · $fiscalMetaText · ICMS-ST por regra fiscal',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.info_outline,
                                size: 14,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remover item',
                    onPressed: saving ? null : onRemoveItem,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Quantidade',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Diminuir quantidade',
                    onPressed: saving ? null : () => onDecrementQuantity(index),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 72,
                    child: TextFormField(
                      key: ValueKey(
                        'qtd_${item.id}_${formatQuantity(item.quantity)}',
                      ),
                      initialValue: formatQuantity(item.quantity),
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (value) {
                        final parsed = readIntegerQuantity(value);
                        onSetQuantity(index, parsed);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Aumentar quantidade',
                    onPressed: saving ? null : () => onIncrementQuantity(index),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                discountSummary,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (activeDiscountSlots == 0)
                    TextButton.icon(
                      onPressed: saving
                          ? null
                          : () => onAddDiscountField(index),
                      icon: const Icon(Icons.percent_outlined, size: 16),
                      label: const Text('Adicionar desconto'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              if (activeDiscountSlots > 0) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (var i = 0; i < activeDiscountSlots; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant
                                .withValues(alpha: 0.55),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 96,
                              child: TextField(
                                controller: inlineDiscountControllers[i],
                                enabled: !saving,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: i < policyFields.length
                                      ? policyFields[i].label
                                      : 'Desconto ${i + 1}',
                                  suffixText: '%',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => onApplyInlineDiscounts(
                                  index,
                                  showErrors: true,
                                ),
                                onChanged: (_) => onApplyInlineDiscounts(
                                  index,
                                  showErrors: false,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Remover este desconto',
                              onPressed: saving
                                  ? null
                                  : () => onRemoveDiscountField(index, i),
                              icon: const Icon(Icons.close, size: 16),
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                    if (canAddDiscountSlot)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: FloatingActionButton.small(
                          heroTag:
                              'item_discount_fab_${item.id}_$activeDiscountSlots',
                          tooltip: 'Adicionar próximo campo',
                          onPressed: saving
                              ? null
                              : () => onAddDiscountField(index),
                          child: const Icon(Icons.add, size: 18),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Preco unitario: R\$ ${formatMoney(item.unitPrice)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Total: R\$ ${formatMoney(item.totalPrice)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: rowHorizontalPadding,
        vertical: 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildItemThumbnail(product, item.productName),
          const SizedBox(width: 10),
          Expanded(
            child: Table(
              columnWidths: columnWidths,
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '$displayCode · ${item.productName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Diminuir quantidade',
                            onPressed: saving
                                ? null
                                : () => onDecrementQuantity(index),
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 18,
                            ),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 26,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 52,
                            child: TextFormField(
                              key: ValueKey(
                                'qtd_${item.id}_${formatQuantity(item.quantity)}',
                              ),
                              initialValue: formatQuantity(item.quantity),
                              enabled: !saving,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(5),
                              ],
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 6,
                                ),
                                border: OutlineInputBorder(),
                              ),
                              onFieldSubmitted: (value) {
                                final parsed = readIntegerQuantity(value);
                                onSetQuantity(index, parsed);
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Aumentar quantidade',
                            onPressed: saving
                                ? null
                                : () => onIncrementQuantity(index),
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 18,
                            ),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 26,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(formatMoney(item.unitPrice)),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(formatMoney(item.totalPrice)),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: InkWell(
                        onTap: () => showItemTaxDetailsDialog(item),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                fiscalMetaText.isEmpty
                                    ? '$ipiText · ICMS-ST por regra fiscal'
                                    : '$ipiText · $fiscalMetaText · ICMS-ST por regra fiscal',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.info_outline,
                              size: 14,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                  ],
                ),
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            discountSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (activeDiscountSlots == 0)
                                TextButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () => onAddDiscountField(index),
                                  icon: const Icon(
                                    Icons.percent_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Adicionar desconto'),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 0,
                                    ),
                                    minimumSize: const Size(0, 30),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                            ],
                          ),
                          if (activeDiscountSlots > 0) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (var i = 0; i < activeDiscountSlots; i++)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.35),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withValues(alpha: 0.55),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 96,
                                          child: TextField(
                                            controller:
                                                inlineDiscountControllers[i],
                                            enabled: !saving,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            decoration: InputDecoration(
                                              labelText: i < policyFields.length
                                                  ? policyFields[i].label
                                                  : 'Desconto ${i + 1}',
                                              suffixText: '%',
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 8,
                                                  ),
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                            onSubmitted: (_) =>
                                                onApplyInlineDiscounts(
                                                  index,
                                                  showErrors: true,
                                                ),
                                            onChanged: (_) =>
                                                onApplyInlineDiscounts(
                                                  index,
                                                  showErrors: false,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          tooltip: 'Remover este desconto',
                                          onPressed: saving
                                              ? null
                                              : () => onRemoveDiscountField(
                                                  index,
                                                  i,
                                                ),
                                          icon: const Icon(
                                            Icons.close,
                                            size: 16,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                            minHeight: 24,
                                          ),
                                          padding: EdgeInsets.zero,
                                        ),
                                      ],
                                    ),
                                  ),
                                if (canAddDiscountSlot)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: FloatingActionButton.small(
                                      heroTag:
                                          'item_discount_fab_${item.id}_$activeDiscountSlots',
                                      tooltip: 'Adicionar próximo campo',
                                      onPressed: saving
                                          ? null
                                          : () => onAddDiscountField(index),
                                      child: const Icon(Icons.add, size: 18),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: actionSlotWidth,
            child: Column(
              children: [
                IconButton(
                  tooltip: 'Remover item',
                  onPressed: saving ? null : onRemoveItem,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
