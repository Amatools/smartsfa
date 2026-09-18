import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';

class ProductEditorHeader extends StatelessWidget {
  const ProductEditorHeader({
    super.key,
    required this.title,
    required this.status,
    required this.readOnly,
    required this.saving,
    required this.labelStyle,
    required this.onClose,
    required this.onStatusChanged,
  });

  final String title;
  final ProductStatus status;
  final bool readOnly;
  final bool saving;
  final TextStyle labelStyle;
  final VoidCallback onClose;
  final ValueChanged<ProductStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Text(
          status == ProductStatus.active ? 'Ativo' : 'Inativo',
          style: labelStyle,
        ),
        const SizedBox(width: 6),
        Switch.adaptive(
          value: status == ProductStatus.active,
          onChanged: readOnly
              ? null
              : (value) {
                  onStatusChanged(value ? ProductStatus.active : ProductStatus.inactive);
                },
          thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
            final isActive = states.contains(WidgetState.selected);
            if (isActive) {
              return null;
            }
            return Colors.red.shade400;
          }),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: saving ? null : onClose,
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}