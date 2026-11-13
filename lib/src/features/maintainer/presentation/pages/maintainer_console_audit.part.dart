part of 'maintainer_console_page.dart';

extension _MaintainerConsoleAuditPart on _MaintainerConsolePageState {
  Widget _buildAuditCard(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auditoria critica',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Eventos criticos do painel admin: CRUD de administradores e alteracoes de status/billing.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 420,
                      child: TextField(
                        controller: _auditSearchController,
                        onChanged: (_) => _refreshAuditFilters(),
                        decoration: const InputDecoration(
                          labelText: 'Buscar por acao, ator, alvo ou detalhes',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<MaintainerCriticalAuditEntry>>(
                  stream: _criticalAuditStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }

                    if (snapshot.hasError) {
                      return Text(
                        'Falha ao carregar auditoria: ${snapshot.error}',
                      );
                    }

                    final entries = _filterCriticalAuditEntries(
                      snapshot.data ?? const <MaintainerCriticalAuditEntry>[],
                    );
                    if (entries.isEmpty) {
                      return const Text(
                        'Sem eventos para os filtros atuais.',
                      );
                    }

                    return SizedBox(
                      height: 520,
                      child: ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final actorText = _actorAuditLabel(entry);
                          final targetText = _targetAuditLabel(entry);
                          final detailsText = entry.details.isEmpty
                              ? '--'
                              : entry.details.toString();

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 2,
                              horizontal: 4,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Tooltip(
                                    message: entry.actionLabel,
                                    waitDuration: const Duration(
                                      milliseconds: 350,
                                    ),
                                    child: Text(
                                      entry.actionLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Tooltip(
                                    message: actorText,
                                    waitDuration: const Duration(
                                      milliseconds: 350,
                                    ),
                                    child: Text(
                                      'Ator: $actorText',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Tooltip(
                                    message: targetText,
                                    waitDuration: const Duration(
                                      milliseconds: 350,
                                    ),
                                    child: Text(
                                      'Alvo: $targetText',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Tooltip(
                                    message: detailsText,
                                    waitDuration: const Duration(
                                      milliseconds: 350,
                                    ),
                                    child: Text(
                                      'Detalhes: $detailsText',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    'Quando: ${_formatDateTime(entry.createdAt)}',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<MaintainerCriticalAuditEntry> _filterCriticalAuditEntries(
    List<MaintainerCriticalAuditEntry> entries,
  ) {
    final query = _auditSearchController.text.trim().toLowerCase();
    final filtered = entries.where((entry) {
      if (query.isEmpty) {
        return true;
      }

      final actor = _actorAuditLabel(entry).toLowerCase();
      final target = _targetAuditLabel(entry).toLowerCase();
      final action = entry.actionLabel.toLowerCase();
      final details = entry.details.toString().toLowerCase();

      return actor.contains(query) ||
          target.contains(query) ||
          action.contains(query) ||
          details.contains(query);
    }).toList(growable: false);

    filtered.sort((a, b) {
      final aTime = a.createdAt?.millisecondsSinceEpoch ?? -1;
      final bTime = b.createdAt?.millisecondsSinceEpoch ?? -1;
      return bTime.compareTo(aTime);
    });

    return filtered;
  }

  String _actorAuditLabel(MaintainerCriticalAuditEntry entry) {
    final uid = entry.actorUid.trim().isEmpty ? '--' : entry.actorUid.trim();
    final email = entry.actorEmail.trim();
    final label = entry.actorLabel.trim();
    if (label.isNotEmpty && email.isNotEmpty) {
      return '$label <$email> [$uid]';
    }
    if (label.isNotEmpty) {
      return '$label [$uid]';
    }
    if (email.isNotEmpty) {
      return '$email [$uid]';
    }
    return uid;
  }

  String _targetAuditLabel(MaintainerCriticalAuditEntry entry) {
    final uid = entry.targetUid.trim();
    final email = entry.targetEmail.trim();
    final label = entry.targetLabel.trim();

    if (uid.isEmpty && label.isEmpty && email.isEmpty) {
      return '--';
    }

    if (label.isNotEmpty && email.isNotEmpty && uid.isNotEmpty) {
      return '$label <$email> [$uid]';
    }
    if (label.isNotEmpty && uid.isNotEmpty) {
      return '$label [$uid]';
    }
    if (email.isNotEmpty && uid.isNotEmpty) {
      return '$email [$uid]';
    }
    if (label.isNotEmpty) {
      return label;
    }
    if (email.isNotEmpty) {
      return email;
    }
    return uid;
  }
}
