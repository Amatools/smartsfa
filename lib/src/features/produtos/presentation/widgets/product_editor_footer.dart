import 'package:flutter/material.dart';

class ProductEditorFooter extends StatelessWidget {
  const ProductEditorFooter({
    super.key,
    required this.readOnly,
    required this.isEditing,
    required this.saving,
    required this.onClose,
    required this.onDelete,
    required this.onSave,
    required this.onSaveAndCreateAnother,
  });

  final bool readOnly;
  final bool isEditing;
  final bool saving;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onSave;
  final VoidCallback onSaveAndCreateAnother;

  @override
  Widget build(BuildContext context) {
    if (readOnly) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Cadastro de produto em modo somente leitura'),
          subtitle: Text(
            'Apenas owner pode cadastrar/editar/excluir produtos (ou quando o ERP estiver como fonte de verdade).',
          ),
        ),
      );
    }

    return Row(
      children: [
        if (isEditing)
          OutlinedButton.icon(
            onPressed: saving ? null : onDelete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir produto'),
          ),
        const Spacer(),
        OutlinedButton(
          onPressed: saving ? null : onClose,
          child: const Text('Cancelar'),
        ),
        if (!isEditing) ...[
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: saving ? null : onSaveAndCreateAnother,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Salvar e cadastrar outro'),
          ),
        ],
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: saving ? null : onSave,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(saving ? 'Salvando...' : 'Salvar produto'),
        ),
      ],
    );
  }
}