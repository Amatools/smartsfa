import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../../core/data/in_memory/in_memory_cliente_pre_cadastro_repository.dart';
import '../../../../core/diagnostics/app_diagnostics.dart';
import '../../../../core/diagnostics/error_dialog.dart';
import '../../../../core/models/app_identity.dart';
import '../../../../core/models/cliente.dart';
import '../../../../core/models/cliente_pre_cadastro.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/repositories/cliente_pre_cadastro_repository.dart';
import '../../../../core/repositories/cliente_repository.dart';
import '../../../../core/services/offline_sync_queue.dart';
import '../../../auth/services/tenant_membership_service.dart';
import 'cliente_detail_page.dart';
import 'cliente_pre_cadastro_page.dart';
import 'pre_cadastro_detail_page.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({
    super.key,
    required this.identity,
    required this.repository,
    this.preCadastroRepository,
  });

  final AppIdentity identity;
  final ClienteRepository repository;
  final ClientePreCadastroRepository? preCadastroRepository;

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  int _preCadastroRefreshTick = 0;
  late Future<_ClienteLocalState> _localClientesFuture;
  int _pendingSyncCount = 0;
  bool _syncingAll = false;

  @override
  void initState() {
    super.initState();
    _localClientesFuture = _loadLocalClientes();
    _refreshPendingSyncCount();
  }

  /// Local-first records plus the tombstone set of ids deleted here. The
  /// tombstones must be applied to whatever the live Firestore stream in
  /// [build] returns, otherwise a cliente the user just excluded reappears
  /// the instant the stream re-emits — which happens immediately, since it
  /// is a live subscription, not a one-off fetch — while its best-effort
  /// remote delete is still pending or failing.
  Future<_ClienteLocalState> _loadLocalClientes() async {
    final records = await OfflineSyncQueue.readLocalClientes(
      tenantId: widget.identity.tenantId,
      includePersonalWorkspace: widget.identity.isPersonalWorkspace,
    );
    final deletedIds = await OfflineSyncQueue.readDeletedIds(type: 'cliente');
    return _ClienteLocalState(records: records, deletedIds: deletedIds);
  }

  bool _belongsToCurrentScope(String entityTenantId) {
    if (widget.identity.isPersonalWorkspace) {
      return true;
    }
    return entityTenantId == widget.identity.tenantId;
  }

  Future<void> _refreshPendingSyncCount() async {
    final all = await OfflineSyncQueue.readAll();
    final count = all.where((entry) {
      if (entry.synced) {
        return false;
      }
      if (entry.type != 'cliente_pre_cadastro' && entry.type != 'cliente') {
        return false;
      }
      return _belongsToCurrentScope(entry.tenantId);
    }).length;

    if (!mounted) {
      return;
    }
    setState(() {
      _pendingSyncCount = count;
    });
  }

  /// General "Sincronizar" action for this screen: pushes every unsynced
  /// local-first record related to clientes — pending pre-cadastros and
  /// already-approved clientes alike — to Firestore in one go. Failures per
  /// item are swallowed so one bad record never blocks the rest; anything
  /// that fails just stays pending for the next sync attempt.
  Future<void> _syncAllNow(BuildContext context) async {
    if (_syncingAll) {
      return;
    }

    setState(() => _syncingAll = true);

    final pending = await OfflineSyncQueue.readAll();
    var syncedCount = 0;
    var failedCount = 0;
    Object? lastError;
    StackTrace? lastStackTrace;

    for (final entry in pending) {
      if (entry.synced || !_belongsToCurrentScope(entry.tenantId)) {
        continue;
      }

      if (entry.type == 'cliente_pre_cadastro' &&
          widget.preCadastroRepository != null) {
        try {
          final entity = ClientePreCadastro.fromMap(entry.payloadMap);
          await widget.preCadastroRepository!.save(entity);
          await OfflineSyncQueue.markSynced(entry.id);
          syncedCount++;
        } catch (error, stackTrace) {
          // keep unsynced; user can retry later once connectivity is back.
          failedCount++;
          lastError = error;
          lastStackTrace = stackTrace;
          AppDiagnostics.log(
            tag: 'sync.pre_cadastro',
            message: 'Falha ao sincronizar pré-cadastro.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      } else if (entry.type == 'cliente') {
        try {
          final entity = Cliente.fromMap(entry.payloadMap);
          await widget.repository.save(entity);
          await OfflineSyncQueue.markSynced(entry.id);
          syncedCount++;
        } catch (error, stackTrace) {
          // keep unsynced; user can retry later once connectivity is back.
          failedCount++;
          lastError = error;
          lastStackTrace = stackTrace;
          AppDiagnostics.log(
            tag: 'sync.cliente',
            message: 'Falha ao sincronizar cliente.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    // Also retry confirming any pending local deletes (cancel pré-cadastro /
    // excluir cliente) whose remote delete hadn't succeeded yet — e.g. it
    // was attempted while offline. Each tombstone is cleared only once the
    // remote delete truly succeeds; otherwise it stays around so the record
    // keeps being filtered out of remote reads instead of resurfacing.
    final pendingDeletes = await OfflineSyncQueue.readPendingDeletes();
    for (final tombstone in pendingDeletes) {
      final type = tombstone['type']?.toString() ?? '';
      final id = tombstone['id']?.toString() ?? '';
      final tenantId = tombstone['tenantId']?.toString() ?? '';
      if (id.isEmpty || !_belongsToCurrentScope(tenantId)) {
        continue;
      }

      try {
        if (type == 'cliente_pre_cadastro' &&
            widget.preCadastroRepository != null) {
          await widget.preCadastroRepository!
              .delete(tenantId: tenantId, id: id);
          await OfflineSyncQueue.clearTombstone(id);
        } else if (type == 'cliente') {
          await widget.repository.delete(tenantId: tenantId, id: id);
          await OfflineSyncQueue.clearTombstone(id);
        }
      } catch (error, stackTrace) {
        AppDiagnostics.log(
          tag: 'sync.delete_retry',
          message: 'Falha ao confirmar exclusão remota de $type/$id.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _syncingAll = false;
      _localClientesFuture = _loadLocalClientes();
      _preCadastroRefreshTick++;
    });
    await _refreshPendingSyncCount();

    if (!context.mounted) {
      return;
    }

    if (syncedCount == 0 && failedCount > 0 && lastError != null) {
      await showAppErrorDialog(
        context,
        title: 'Não foi possível sincronizar',
        error: lastError,
        stackTrace: lastStackTrace,
        tag: 'sync.geral',
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          syncedCount > 0
              ? '$syncedCount registro(s) sincronizado(s) com o Firebase.'
                  '${failedCount > 0 ? ' $failedCount continuam pendentes.' : ''}'
              : 'Tudo já está sincronizado.',
        ),
      ),
    );
  }

  List<_ClienteEntry> _mergeClientes(
    List<Cliente> remote,
    List<LocalClienteRecord> local,
  ) {
    final seen = <String>{};
    final merged = <_ClienteEntry>[];

    for (final record in local) {
      if (seen.contains(record.entity.id)) {
        continue;
      }
      seen.add(record.entity.id);
      merged.add(_ClienteEntry(item: record.entity, isSyncedRemotely: record.synced));
    }

    for (final item in remote) {
      if (seen.contains(item.id)) {
        continue;
      }
      seen.add(item.id);
      merged.add(_ClienteEntry(item: item, isSyncedRemotely: true));
    }

    merged.sort((a, b) => a.item.nome.compareTo(b.item.nome));
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ClienteLocalState>(
      future: _localClientesFuture,
      builder: (context, localSnapshot) {
        final localState = localSnapshot.data ?? _ClienteLocalState.empty;

        return StreamBuilder<List<Cliente>>(
          stream: widget.repository.watchAll(tenantId: widget.identity.tenantId),
          initialData: const [],
          builder: (context, snapshot) {
            // The live stream re-emits immediately whenever the backend
            // still has a record the user deleted here — filter it out via
            // the tombstone set instead of letting it resurface.
            final remote = (snapshot.data ?? const <Cliente>[])
                .where((cliente) => !localState.deletedIds.contains(cliente.id))
                .toList();
            final clientes = _mergeClientes(remote, localState.records);

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeaderCard(
                      title: 'Clientes',
                      subtitle:
                          'Base visivel do tenant ${widget.identity.tenantName} com carga local-first.',
                      actionLabel: 'Novo pré-cadastro',
                      onAction: () {
                        _openPreCadastro(context);
                      },
                      pendingSyncCount: _pendingSyncCount,
                      syncing: _syncingAll,
                      onSync: () => _syncAllNow(context),
                    ),
                    const SizedBox(height: 16),
                    _PreCadastroSection(
                      key: ValueKey('pre-cadastro-${widget.identity.tenantId}-$_preCadastroRefreshTick'),
                      identity: widget.identity,
                      repository: widget.preCadastroRepository,
                      clienteRepository: widget.repository,
                      onClienteCreated: () {
                        setState(() {
                          _localClientesFuture = _loadLocalClientes();
                        });
                        _refreshPendingSyncCount();
                      },
                    ),
                    const SizedBox(height: 16),
                    if (clientes.isEmpty)
                      const _EmptyState(
                        title: 'Nenhum cliente carregado',
                        subtitle:
                            'Os primeiros clientes aparecem aqui quando a base for sincronizada.',
                      )
                    else
                      ...clientes.map(
                        (entry) => _ClienteCard(
                          entry: entry,
                          repository: widget.repository,
                          identity: widget.identity,
                          onChanged: () {
                            setState(() {
                              _localClientesFuture = _loadLocalClientes();
                            });
                            _refreshPendingSyncCount();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openPreCadastro(BuildContext context) async {
    final repository = widget.preCadastroRepository ??
        InMemoryClientePreCadastroRepository();

    String actorUid = widget.identity.userLabel;
    try {
      if (Firebase.apps.isNotEmpty) {
        actorUid =
            FirebaseAuth.instance.currentUser?.uid ?? widget.identity.userLabel;
      }
    } catch (_) {
      actorUid = widget.identity.userLabel;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientePreCadastroPage(
          tenantId: widget.identity.tenantId,
          requestedByUid: actorUid,
          repository: repository,
          clienteRepository: widget.repository,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _preCadastroRefreshTick++;
    });
    _refreshPendingSyncCount();
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.pendingSyncCount = 0,
    this.syncing = false,
    this.onSync,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final int pendingSyncCount;
  final bool syncing;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(subtitle),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ),
            if (onSync != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: syncing ? null : onSync,
                  icon: syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(
                    pendingSyncCount > 0
                        ? 'Sincronizar agora ($pendingSyncCount)'
                        : 'Sincronizar agora',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreCadastroSection extends StatefulWidget {
  const _PreCadastroSection({
    super.key,
    required this.identity,
    required this.repository,
    required this.clienteRepository,
    this.onClienteCreated,
  });

  final AppIdentity identity;
  final ClientePreCadastroRepository? repository;
  final ClienteRepository clienteRepository;
  final VoidCallback? onClienteCreated;

  @override
  State<_PreCadastroSection> createState() => _PreCadastroSectionState();
}

class _PreCadastroSectionState extends State<_PreCadastroSection> {
  late Future<List<_PreCadastroEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadEntries();
  }

  @override
  void didUpdateWidget(covariant _PreCadastroSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.tenantId != widget.identity.tenantId ||
        oldWidget.identity.isPersonalWorkspace !=
            widget.identity.isPersonalWorkspace ||
        oldWidget.repository != widget.repository) {
      _entriesFuture = _loadEntries();
    }
  }

  bool get _canApprove {
    if (widget.identity.isPersonalWorkspace) {
      return true;
    }
    const managementRoles = {'owner', 'gerente', 'platform_admin'};
    return managementRoles.contains(widget.identity.role.trim().toLowerCase());
  }

  /// A pre-cadastro can be cancelled/excluded by whoever can approve it, or
  /// by the person who originally requested it (self-service cleanup of a
  /// mistaken/duplicate request) while it is still not a final decision.
  bool _canCancelPreCadastro(ClientePreCadastro item) {
    if (item.status != PreRegistrationStatus.pending &&
        item.status != PreRegistrationStatus.rejected) {
      return false;
    }
    if (_canApprove) {
      return true;
    }
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return currentUid != null &&
        currentUid.isNotEmpty &&
        currentUid == item.requestedByUid;
  }

  Future<List<_PreCadastroEntry>> _loadEntries() async {
    // Duplicates could only have been created before duplicate documents
    // started being blocked; clean them up opportunistically so the list
    // self-heals without needing a manual one-off migration.
    await OfflineSyncQueue.deduplicatePreCadastros();

    // Local-first: the on-device queue is the source of truth for what the
    // user can see and approve. A remote fetch only adds pre-cadastros that
    // exist on the backend but were never created on this device (e.g. by
    // another user/session) — it is best-effort and must never hide or
    // delay locally known records if it fails or is slow.
    var remote = <ClientePreCadastro>[];
    if (widget.repository != null) {
      try {
        remote = await widget.repository!
            .fetchAll(tenantId: widget.identity.tenantId);
      } catch (_) {
        remote = const [];
      }
    }

    var localRecords = await OfflineSyncQueue.readLocalPreCadastroRecords(
      tenantId: widget.identity.tenantId,
      includePersonalWorkspace: widget.identity.isPersonalWorkspace,
    );

    // Records the user cancelled/excluded here must never resurface just
    // because their best-effort remote delete hasn't completed yet (offline,
    // transient error, or a permission mismatch) — the remote fetch above is
    // filtered against this tombstone set before being merged in below.
    final deletedIds =
        await OfflineSyncQueue.readDeletedIds(type: 'cliente_pre_cadastro');
    remote = remote.where((item) => !deletedIds.contains(item.id)).toList();

    // Self-heal: earlier versions of this screen marked a pre-cadastro as
    // "aprovado" without ever creating the corresponding cliente record. These
    // orphaned records block a clean re-use of the same data, so remove them
    // locally instead of leaving them stuck in limbo.
    final legacyApproved = localRecords.where((record) =>
        record.entity.status == PreRegistrationStatus.approved &&
        (record.entity.mergedClienteId == null ||
            record.entity.mergedClienteId!.isEmpty));
    if (legacyApproved.isNotEmpty) {
      await OfflineSyncQueue.removeOrphanApprovedPreCadastros(
        tenantId: widget.identity.tenantId,
        includePersonalWorkspace: widget.identity.isPersonalWorkspace,
      );
      localRecords = await OfflineSyncQueue.readLocalPreCadastroRecords(
        tenantId: widget.identity.tenantId,
        includePersonalWorkspace: widget.identity.isPersonalWorkspace,
      );
    }

    final seen = <String>{};
    final merged = <_PreCadastroEntry>[];

    for (final record in localRecords) {
      // The id must be marked as seen the instant it is known locally,
      // regardless of its status — otherwise, when the local approval
      // (pending -> merged) hasn't finished syncing to Firestore yet, the
      // remote fetch below still returns the stale 'pendente' copy of the
      // very same document, which — with nothing recorded in `seen` to stop
      // it — gets merged back in and the just-approved pre-cadastro
      // reappears here even though it already shows up as an official
      // cliente.
      if (seen.contains(record.entity.id)) {
        continue;
      }
      seen.add(record.entity.id);

      // Only a truly pending pre-cadastro belongs in this section. Once it
      // is approved it becomes an official cliente and must disappear from
      // here regardless of the exact terminal status value (covers both
      // the current 'merged' status and any stale 'approved' records left
      // over from before pre-cadastro approval created a cliente).
      if (record.entity.status != PreRegistrationStatus.pending) {
        continue;
      }
      merged.add(
        _PreCadastroEntry(item: record.entity, isSyncedRemotely: record.synced),
      );
    }

    for (final item in remote) {
      if (seen.contains(item.id) || item.status != PreRegistrationStatus.pending) {
        continue;
      }
      seen.add(item.id);
      merged.add(_PreCadastroEntry(item: item, isSyncedRemotely: true));
    }

    merged.sort((a, b) => (b.item.updatedAt ?? b.item.createdAt ?? DateTime.now())
        .compareTo(a.item.updatedAt ?? a.item.createdAt ?? DateTime.now()));

    return merged;
  }

  Future<Map<String, String>> _resolveScopeIdsForCurrentUser(String tenantId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return {
        'ownerId': '',
        'gerenteId': '',
        'representanteId': '',
        'vendedorId': '',
      };
    }

    try {
      final membership = await TenantMembershipService(FirebaseFirestore.instance)
          .loadById('${tenantId}_$uid');
      if (membership != null) {
        return {
          'ownerId': membership.ownerId,
          'gerenteId': membership.gerenteId,
          'representanteId': membership.representanteId,
          'vendedorId': membership.vendedorId,
        };
      }
    } catch (_) {
      // Fall back to the current user role-based defaults below.
    }

    final role = widget.identity.role.trim().toLowerCase();
    switch (role) {
      case 'owner':
        return {
          'ownerId': uid,
          'gerenteId': '',
          'representanteId': '',
          'vendedorId': '',
        };
      case 'gerente':
        return {
          'ownerId': uid,
          'gerenteId': uid,
          'representanteId': '',
          'vendedorId': '',
        };
      case 'representante':
        return {
          'ownerId': uid,
          'gerenteId': uid,
          'representanteId': uid,
          'vendedorId': '',
        };
      case 'vendedor':
        return {
          'ownerId': uid,
          'gerenteId': uid,
          'representanteId': uid,
          'vendedorId': uid,
        };
      default:
        return {
          'ownerId': uid,
          'gerenteId': uid,
          'representanteId': uid,
          'vendedorId': uid,
        };
    }
  }

  /// Converts a pre-cadastro into an official cliente: writes the cliente
  /// to the local-first cache first (so it's visible immediately regardless
  /// of connectivity), then best-effort syncs both the new cliente and the
  /// pre-cadastro's new `merged` status with Firestore. Used both by a
  /// fresh approval and by the self-heal pass in [_loadEntries] for legacy
  /// "aprovado" records that never got converted.
  Future<({ClientePreCadastro merged, bool clienteSyncedRemotely})>
      _convertToOfficialCliente(ClientePreCadastro item) async {
    final now = DateTime.now();
    final scopeIds = await _resolveScopeIdsForCurrentUser(item.tenantId);

    final cliente = Cliente(
      id: 'cli-${now.microsecondsSinceEpoch}',
      tenantId: item.tenantId,
      nome: item.nome,
      documento: item.documento,
      origemCadastro: item.origemCadastro,
      status: CustomerStatus.approved,
      ownerId: scopeIds['ownerId'],
      gerenteId: scopeIds['gerenteId'],
      representanteId: scopeIds['representanteId'],
      vendedorId: scopeIds['vendedorId'],
      tipoPessoa: item.tipoPessoa,
      nomeFantasia: item.nomeFantasia,
      email: item.email,
      emailFinanceiro: item.emailFinanceiro,
      canal: item.canal,
      celular: item.celular,
      telefone: item.telefone,
      cep: item.cep,
      logradouro: item.logradouro,
      numero: item.numero,
      complemento: item.complemento,
      bairro: item.bairro,
      cidade: item.cidade,
      estado: item.estado,
      pais: item.pais,
      inscricaoEstadual: item.inscricaoEstadual,
      inscricaoMunicipal: item.inscricaoMunicipal,
      observacoes: item.observacoes,
      createdAt: item.createdAt ?? now,
      updatedAt: now,
    );

    await OfflineSyncQueue.enqueue(
      type: 'cliente',
      tenantId: cliente.tenantId,
      payload: cliente.toMap(),
    );

    var clienteSyncedRemotely = false;
    try {
      await widget.clienteRepository.save(cliente);
      await OfflineSyncQueue.markSynced(cliente.id);
      clienteSyncedRemotely = true;
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'cliente.save',
        message: 'Falha ao sincronizar cliente ${cliente.nome} com o Firebase.',
        error: error,
        stackTrace: stackTrace,
      );
      // keep unsynced locally; a later sync pass will retry.
    }

    final merged = item.copyWith(
      status: PreRegistrationStatus.merged,
      mergedClienteId: cliente.id,
      updatedAt: now,
    );

    // Always update the local-first record so the approval is reflected
    // immediately regardless of connectivity.
    await OfflineSyncQueue.updatePreCadastroStatus(item.id, merged);

    // Best-effort background push to the backend; failure here must never
    // block the local approval from being visible.
    if (widget.repository != null) {
      try {
        await widget.repository!.save(merged);
        await OfflineSyncQueue.markSynced(item.id);
      } catch (error, stackTrace) {
        AppDiagnostics.log(
          tag: 'pre_cadastro.save',
          message: 'Falha ao sincronizar pr\u00e9-cadastro ${merged.nome} com o Firebase.',
          error: error,
          stackTrace: stackTrace,
        );
        // keep unsynced locally; a later sync pass will retry.
      }
    }

    widget.onClienteCreated?.call();
    return (merged: merged, clienteSyncedRemotely: clienteSyncedRemotely);
  }

  Future<void> _approvePreCadastro(
    BuildContext context,
    ClientePreCadastro item,
    bool isSyncedRemotely,
  ) async {
    final result = await _convertToOfficialCliente(item);

    if (!context.mounted) {
      return;
    }

    setState(() {
      _entriesFuture = _loadEntries();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.clienteSyncedRemotely
              ? '${result.merged.nome} aprovado e cadastrado como cliente oficial.'
              : '${result.merged.nome} aprovado e cadastrado localmente; sera sincronizado assim que houver conexao.',
        ),
      ),
    );
  }

  void _openPreCadastroDetail(
    BuildContext context,
    ClientePreCadastro item,
    bool isSyncedRemotely,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreCadastroDetailPage(
          item: item,
          isSyncedRemotely: isSyncedRemotely,
          canApprove: _canApprove,
          onApprove: () => _approvePreCadastro(context, item, isSyncedRemotely),
          canCancel: _canCancelPreCadastro(item),
          onCancel: () => _cancelPreCadastro(context, item),
        ),
      ),
    );
  }

  Future<void> _cancelPreCadastro(
    BuildContext context,
    ClientePreCadastro item,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Cancelar pré-cadastro'),
            content: Text(
              'Tem certeza que deseja cancelar e excluir o pré-cadastro de "${item.nome}"? Esta ação não pode ser desfeita.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Voltar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Cancelar pré-cadastro'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    // Local-first: always drop it from the on-device queue first so it
    // disappears immediately regardless of connectivity, and record a
    // tombstone so a remote fetch never resurrects it just because the
    // best-effort remote delete below hasn't completed yet (or fails).
    await OfflineSyncQueue.markDeleted(
      type: 'cliente_pre_cadastro',
      tenantId: item.tenantId,
      id: item.id,
    );

    if (widget.repository != null) {
      try {
        await widget.repository!.delete(tenantId: item.tenantId, id: item.id);
        await OfflineSyncQueue.clearTombstone(item.id);
      } catch (error, stackTrace) {
        AppDiagnostics.log(
          tag: 'pre_cadastro.delete',
          message:
              'Falha ao excluir pré-cadastro ${item.nome} remotamente; tentativa será repetida na próxima sincronização.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (!context.mounted) {
      return;
    }

    setState(() {
      _entriesFuture = _loadEntries();
    });
    widget.onClienteCreated?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pré-cadastro de ${item.nome} cancelado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_PreCadastroEntry>>(
      future: _entriesFuture,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <_PreCadastroEntry>[];

        if (items.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pré-cadastro',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Nenhum pré-cadastro pendente neste tenant.'),
                ],
              ),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pré-cadastro',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                ...items.take(5).map((entry) {
                  final item = entry.item;
                  final badgeColor = entry.isSyncedRemotely
                      ? Colors.green.shade100
                      : Colors.orange.shade100;
                  final badgeText = entry.isSyncedRemotely
                      ? 'Sincronizado'
                      : 'Local • pendente sync';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${item.nome} - ${item.documento}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeText,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Abrir',
                            onPressed: () => _openPreCadastroDetail(
                              context,
                              item,
                              entry.isSyncedRemotely,
                            ),
                            icon: const Icon(Icons.visibility_outlined),
                          ),
                          if (_canApprove &&
                              item.status == PreRegistrationStatus.pending)
                            IconButton(
                              tooltip: 'Aprovar',
                              onPressed: () => _approvePreCadastro(
                                context,
                                item,
                                entry.isSyncedRemotely,
                              ),
                              icon: const Icon(Icons.check_circle_outline),
                            ),
                          if (_canCancelPreCadastro(item))
                            IconButton(
                              tooltip: 'Cancelar',
                              onPressed: () => _cancelPreCadastro(context, item),
                              icon: const Icon(Icons.delete_outline),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreCadastroEntry {
  const _PreCadastroEntry({
    required this.item,
    required this.isSyncedRemotely,
  });

  final ClientePreCadastro item;
  final bool isSyncedRemotely;
}

class _ClienteEntry {
  const _ClienteEntry({required this.item, required this.isSyncedRemotely});

  final Cliente item;
  final bool isSyncedRemotely;
}

class _ClienteLocalState {
  const _ClienteLocalState({required this.records, required this.deletedIds});

  static const empty = _ClienteLocalState(
    records: <LocalClienteRecord>[],
    deletedIds: <String>{},
  );

  final List<LocalClienteRecord> records;
  final Set<String> deletedIds;
}

class _ClienteCard extends StatelessWidget {
  const _ClienteCard({
    required this.entry,
    required this.repository,
    required this.identity,
    required this.onChanged,
  });

  final _ClienteEntry entry;
  final ClienteRepository repository;
  final AppIdentity identity;
  final VoidCallback onChanged;

  Future<void> _openDetail(BuildContext context, Cliente cliente) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClienteDetailPage(
          cliente: cliente,
          repository: repository,
          identity: identity,
        ),
      ),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cliente = entry.item;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: () => _openDetail(context, cliente),
        leading: const Icon(Icons.person_outline),
        title: Text(cliente.nome),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${cliente.documento} · ${cliente.origemCadastro.label} · ${cliente.status.label}',
            ),
            if (!entry.isSyncedRemotely) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Local • pendente sync',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          tooltip: 'Abrir cliente',
          icon: const Icon(Icons.visibility_outlined),
          onPressed: () => _openDetail(context, cliente),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
      ),
    );
  }
}