import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/diagnostics/app_diagnostics.dart';

/// Lists every diagnostic event (errors and notable background failures)
/// recorded this session, so a user can inspect and copy the technical
/// details when asking for support — in dev and, more importantly, in
/// production where there is no debugger attached.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  @override
  Widget build(BuildContext context) {
    final entries = AppDiagnostics.entries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico'),
        actions: [
          IconButton(
            tooltip: 'Limpar',
            onPressed: entries.isEmpty
                ? null
                : () => setState(AppDiagnostics.clear),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum evento registrado nesta sessão. Erros e falhas em '
                  'segundo plano aparecem aqui automaticamente.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _DiagnosticEntryCard(entry: entries[index]),
            ),
    );
  }
}

class _DiagnosticEntryCard extends StatelessWidget {
  const _DiagnosticEntryCard({required this.entry});

  final DiagnosticEntry entry;

  static String _formatTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(entry.message),
        subtitle: Text('${entry.tag} • ${_formatTimestamp(entry.timestamp)}'),
        children: [
          if (entry.details != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  entry.details!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: '${entry.tag} • ${_formatTimestamp(entry.timestamp)}\n'
                          '${entry.message}\n\n${entry.details ?? ''}',
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copiado.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
