import 'package:flutter/material.dart';

import '../../core/models/app_identity.dart';
import '../models/app_shell_sync_status.dart';

class AppShellDashboardPage extends StatelessWidget {
  const AppShellDashboardPage({
    super.key,
    required this.identity,
    required this.usingLocalFallback,
    required this.syncStatus,
    required this.onSyncNow,
    required this.onRefreshSyncStatus,
  });

  final AppIdentity identity;
  final bool usingLocalFallback;
  final AppShellSyncStatus syncStatus;
  final VoidCallback? onSyncNow;
  final VoidCallback? onRefreshSyncStatus;

  String _syncResultLabel() {
    if (syncStatus.lastAttemptSucceeded == null) {
      return 'Ainda nao executada nesta sessao';
    }
    if (syncStatus.lastAttemptSucceeded == true) {
      return 'Ultima execucao concluida com sucesso';
    }
    return 'Ultima execucao com pendencias';
  }

  String _lastAttemptLabel() {
    final last = syncStatus.lastAttemptAt;
    if (last == null) {
      return 'Sem historico recente';
    }

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${twoDigits(last.day)}/${twoDigits(last.month)} ${twoDigits(last.hour)}:${twoDigits(last.minute)}';
  }

  String _lastCloudCheckLabel() {
    final last = syncStatus.cloudSnapshotAt;
    if (last == null) {
      return 'Ainda nao verificado';
    }

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${twoDigits(last.day)}/${twoDigits(last.month)} ${twoDigits(last.hour)}:${twoDigits(last.minute)}';
  }

  String _cloudReachabilityLabel() {
    final reachable = syncStatus.cloudSnapshotReachable;
    if (reachable == null) {
      return 'Nuvem nao consultada ainda';
    }
    if (reachable) {
      return 'Nuvem acessivel para leitura';
    }
    return 'Sem conexao para consultar nuvem';
  }

  bool _isUploadOk() {
    return syncStatus.totalUploadPending == 0;
  }

  bool _isDownloadOk() {
    return syncStatus.cloudSnapshotReachable == true &&
        syncStatus.totalDownloadPending == 0;
  }

  String _uploadSummaryLabel() {
    if (_isUploadOk()) {
      return 'Sem pendencias para envio';
    }
    return '${syncStatus.totalUploadPending} pendencia(s) para envio';
  }

  String _downloadSummaryLabel() {
    if (syncStatus.cloudSnapshotReachable != true) {
      return 'Falha ao consultar nuvem';
    }
    if (_isDownloadOk()) {
      return 'Sem pendencias para download';
    }
    return '${syncStatus.totalDownloadPending} pendencia(s) para download';
  }

  Widget _buildDirectionSummaryRow({
    required BuildContext context,
    required String label,
    required String subtitle,
    required bool ok,
  }) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.error,
          color: ok ? Colors.green : Colors.red,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSyncStatusCard(BuildContext context) {
    final uploadRows = <(String, String)>[
      ('Clientes para enviar', syncStatus.pendingUploadClientes.toString()),
      (
        'Pre-cadastros para enviar',
        syncStatus.pendingUploadPreCadastros.toString(),
      ),
      ('Pedidos para enviar', syncStatus.pendingUploadPedidos.toString()),
      ('Exclusoes para confirmar', syncStatus.pendingUploadDeletes.toString()),
    ];

    final downloadRows = <(String, String)>[
      ('Clientes para baixar', syncStatus.pendingDownloadClientes.toString()),
      ('Produtos para baixar', syncStatus.pendingDownloadProdutos.toString()),
      (
        'Tabelas de preco para baixar',
        syncStatus.pendingDownloadTabelasPreco.toString(),
      ),
      (
        'Regras fiscais para baixar',
        syncStatus.pendingDownloadTaxRules.toString(),
      ),
    ];

    return Card(
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        leading: const Icon(Icons.sync),
        title: Text(
          'Status da sincronizacao geral',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            children: [
              _buildDirectionSummaryRow(
                context: context,
                label: 'Upload',
                subtitle: _uploadSummaryLabel(),
                ok: _isUploadOk(),
              ),
              const SizedBox(height: 8),
              Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(context).dividerColor,
              ),
              const SizedBox(height: 8),
              _buildDirectionSummaryRow(
                context: context,
                label: 'Download',
                subtitle: _downloadSummaryLabel(),
                ok: _isDownloadOk(),
              ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const SizedBox(height: 4),
          Text(syncStatus.phase, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            'Resultado: ${_syncResultLabel()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            _cloudReachabilityLabel(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Ultima tentativa: ${_lastAttemptLabel()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Ultima leitura da nuvem: ${_lastCloudCheckLabel()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text('Upload', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...uploadRows.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(entry.$1)),
                  Text(entry.$2, style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total para enviar: ${syncStatus.totalUploadPending}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).dividerColor,
          ),
          const SizedBox(height: 12),
          Text('Download', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...downloadRows.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(entry.$1)),
                  Text(entry.$2, style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total para baixar: ${syncStatus.totalDownloadPending}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: (usingLocalFallback || syncStatus.isRunning)
                    ? null
                    : onSyncNow,
                icon: syncStatus.isRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  syncStatus.isRunning
                      ? 'Sincronizando...'
                      : 'Sincronizar agora',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Total pendente geral: ${syncStatus.totalPending}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('Tenant', identity.tenantName),
      ('Usuario', identity.userLabel),
      ('Perfil', identity.role),
      (
        'Conexao',
        usingLocalFallback ? 'Local mock / fallback' : 'Firebase autenticado',
      ),
    ];

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Painel inicial',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            _buildSyncStatusCard(context),
            const SizedBox(height: 16),
            Column(
              children: cards
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  entry.$1,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Flexible(
                                child: Text(entry.$2, textAlign: TextAlign.end),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            const AppShellStageCard(
              title: 'Proxima entrega',
              lines: [
                'Refatorar dados para tenants e memberships',
                'Criar navegacao funcional por modulo',
                'Mostrar listas reais de clientes, produtos e pedidos',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AppShellModulePage extends StatelessWidget {
  const AppShellModulePage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bullets,
  });

  final String title;
  final String subtitle;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            AppShellStageCard(title: 'Escopo inicial', lines: bullets),
          ],
        ),
      ),
    );
  }
}

class AppShellStageCard extends StatelessWidget {
  const AppShellStageCard({
    super.key,
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle, size: 8),
                    ),
                    Expanded(child: Text(line)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
