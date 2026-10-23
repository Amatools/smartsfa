import 'package:flutter/material.dart';

import '../../domain/models/enterprise_erp_connector_option.dart';

class ErpConnectorCard extends StatelessWidget {
  const ErpConnectorCard({
    super.key,
    required this.option,
    required this.selected,
    this.onTap,
    this.showStatusBadge = false,
  });

  final EnterpriseErpConnectorOption option;
  final bool selected;
  final VoidCallback? onTap;
  final bool showStatusBadge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = selected
        ? colorScheme.primary
        : colorScheme.outlineVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        width: 190,
        height: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.38)
              : colorScheme.surface,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 20, child: Text(option.logoLabel)),
                  const Spacer(),
                  if (showStatusBadge)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Ativa',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: colorScheme.onPrimary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(option.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                option.subtitle,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                option.enabled
                    ? (selected ? 'Selecionado' : 'Disponivel')
                    : 'Em breve',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
