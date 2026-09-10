import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_diagnostics.dart';

/// Shows a real error dialog: a human-readable message plus expandable
/// technical details (raw error + stack trace) and a "Copiar diagnóstico"
/// action, so a user hitting an unexpected failure can actually explain
/// what happened when asking for support instead of just seeing a vague
/// snackbar. Also records the error into [AppDiagnostics] so it shows up
/// on the Diagnóstico screen even if the dialog gets dismissed quickly.
Future<void> showAppErrorDialog(
  BuildContext context, {
  required String title,
  required Object error,
  StackTrace? stackTrace,
  String? tag,
}) async {
  final humanMessage = AppDiagnostics.describeError(error);

  AppDiagnostics.log(
    tag: tag ?? title,
    message: humanMessage,
    error: error,
    stackTrace: stackTrace,
  );

  final technicalDetails = <String>[
    error.toString(),
    if (stackTrace != null) stackTrace.toString(),
  ].join('\n\n');

  if (!context.mounted) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(humanMessage),
                const SizedBox(height: 12),
                Theme(
                  data: Theme.of(dialogContext).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Detalhes técnicos'),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          technicalDetails,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: '$title\n$humanMessage\n\n$technicalDetails'),
              );
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Diagnóstico copiado.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar diagnóstico'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      );
    },
  );
}
