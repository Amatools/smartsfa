import 'package:flutter/material.dart';

class ProductImageLibraryField extends StatelessWidget {
  const ProductImageLibraryField({
    super.key,
    required this.readOnly,
    required this.hasImage,
    required this.scopeLabel,
    required this.helperTextStyle,
    required this.onOpenLibrary,
    required this.onClearImage,
  });

  final bool readOnly;
  final bool hasImage;
  final String scopeLabel;
  final TextStyle? helperTextStyle;
  final VoidCallback onOpenLibrary;
  final VoidCallback onClearImage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: readOnly ? null : onOpenLibrary,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(hasImage ? 'Trocar imagem' : 'Biblioteca de imagens'),
            ),
            const SizedBox(width: 12),
            if (hasImage)
              TextButton.icon(
                onPressed: readOnly ? null : onClearImage,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remover imagem'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          hasImage
              ? 'Imagem vinculada ao contexto $scopeLabel. Ela pode ser reutilizada em outros produtos do mesmo contexto sem novo upload.'
              : 'As imagens ficam salvas por conta/contexto e podem ser reutilizadas em outros produtos.',
          style: helperTextStyle,
        ),
      ],
    );
  }
}