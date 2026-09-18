import 'package:flutter/material.dart';

enum DisableErpSyncAction {
  keepCurrent,
  deactivateErpProducts,
}

Future<DisableErpSyncAction?> showDisableErpSyncDialog(BuildContext context) async {
  var selected = DisableErpSyncAction.keepCurrent;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Desativar sincronizacao ERP'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Escolha como tratar os produtos de origem ERP apos desligar a sincronizacao.',
                ),
                const SizedBox(height: 12),
                SegmentedButton<DisableErpSyncAction>(
                  segments: const [
                    ButtonSegment<DisableErpSyncAction>(
                      value: DisableErpSyncAction.keepCurrent,
                      label: Text('Manter'),
                      icon: Icon(Icons.lock_open_outlined),
                    ),
                    ButtonSegment<DisableErpSyncAction>(
                      value: DisableErpSyncAction.deactivateErpProducts,
                      label: Text('Inativar ERP'),
                      icon: Icon(Icons.cancel_outlined),
                    ),
                  ],
                  selected: <DisableErpSyncAction>{selected},
                  onSelectionChanged: (value) {
                    setDialogState(() {
                      selected = value.first;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  selected == DisableErpSyncAction.keepCurrent
                      ? 'Acao selecionada: manter produtos ERP como estao e apenas liberar cadastro manual.'
                      : 'Acao selecionada: inativar produtos ERP, mantendo historico e IDs de integracao.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed != true) {
    return null;
  }
  return selected;
}
