import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/models/app_identity.dart';
import '../core/constants/app_environment.dart';
import '../core/services/catalog_incremental_sync_service.dart';
import '../core/services/offline_sync_queue.dart';
import '../core/services/represented_scope_backfill_service.dart';
import '../core/services/sync_cost_metrics_service.dart';
import '../features/auth/services/workspace_profile_service.dart';
import '../features/portal/presentation/pages/web_portal_page.dart';
import 'models/app_shell_item.dart';
import 'models/app_shell_repository_bundle.dart';
import 'models/app_shell_scaffold_payload.dart';
import 'models/app_shell_selection.dart';
import 'models/app_shell_sync_status.dart';
import 'models/app_shell_view_state.dart';
import 'services/app_shell_connectivity_coordinator.dart';
import 'services/app_shell_catalog_sync_coordinator.dart';
import 'services/app_shell_mock_seed_coordinator.dart';
import 'services/app_shell_navigation_factory.dart';
import 'services/app_shell_offline_sync_coordinator.dart';
import 'services/app_shell_repository_bootstrap_coordinator.dart';
import 'services/app_shell_selection_coordinator.dart';
import 'services/app_shell_view_state_coordinator.dart';
import 'widgets/app_shell_scaffold.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({
    super.key,
    required this.identity,
    required this.onSignOut,
    this.onAccessUpdated,
    this.onSwitchProfile,
    this.forceMobilePreviewOnWeb = false,
  });

  final AppIdentity identity;
  final VoidCallback onSignOut;
  final VoidCallback? onAccessUpdated;
  final VoidCallback? onSwitchProfile;
  final bool forceMobilePreviewOnWeb;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  static const bool _enableFirestoreMockSeed = bool.fromEnvironment(
    'SEED_FIRESTORE_MOCKS',
    defaultValue: false,
  );
  static const bool _enableLocalMockFallback = bool.fromEnvironment(
    'ENABLE_LOCAL_MOCK_FALLBACK',
    defaultValue: false,
  );
  static final Duration _cloudDeltaRefreshInterval =
      AppEnvironmentConfig.cloudDeltaRefreshInterval;

  AppShellViewState _viewState = AppShellViewState.initial();
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final AppShellNavigationFactory _navigationFactory =
      const AppShellNavigationFactory();
  final AppShellCatalogSyncCoordinator _catalogSyncCoordinator =
      const AppShellCatalogSyncCoordinator();
  final AppShellOfflineSyncCoordinator _offlineSyncCoordinator =
      const AppShellOfflineSyncCoordinator();
  final AppShellRepositoryBootstrapCoordinator _repositoryBootstrapCoordinator =
      const AppShellRepositoryBootstrapCoordinator();
  final AppShellConnectivityCoordinator _connectivityCoordinator =
      const AppShellConnectivityCoordinator();
  final AppShellMockSeedCoordinator _mockSeedCoordinator =
      const AppShellMockSeedCoordinator();
  final AppShellSelectionCoordinator _selectionCoordinator =
      const AppShellSelectionCoordinator();
  final AppShellViewStateCoordinator _viewStateCoordinator =
      const AppShellViewStateCoordinator();
  final SyncCostMetricsService _syncCostMetricsService =
      SyncCostMetricsService();

  AppShellRepositoryBundle? get _repositoryBundle =>
      _viewState.repositoryBundle;
  bool get _usingLocalFallback =>
      _repositoryBundle?.usingLocalFallback ?? false;
  final WorkspaceProfileService _workspaceProfileService =
      WorkspaceProfileService(FirebaseFirestore.instance);
  final RepresentedScopeBackfillService _representedScopeBackfillService =
      RepresentedScopeBackfillService(FirebaseFirestore.instance);
  bool _catalogWarmupRunning = false;
  bool _representedScopeLoading = false;
  bool _representedScopeBackfillRunning = false;
  bool _representedScopeBackfillDone = false;
  AppShellSyncStatus _syncStatus = AppShellSyncStatus.initial();
  List<_RepresentedScopeOption> _representedScopeOptions =
      const <_RepresentedScopeOption>[];
  _RepresentedScopeOption? _selectedRepresentedScope;
  DateTime? _lastCloudDeltaCheckAt;
  SyncCostMetricsSnapshot _costMetrics = const SyncCostMetricsSnapshot.empty();
  SyncCostAlert? _costAlert;
  bool _queryReviewOverdue = true;

  void _updateViewState(
    AppShellViewState Function(AppShellViewState state) update,
  ) {
    if (!mounted) {
      return;
    }

    setState(() {
      _viewState = update(_viewState);
    });
  }

  @override
  void initState() {
    super.initState();
    _connectivitySubscription = _connectivityCoordinator.watchOnlineChanges(
      connectivity: _connectivity,
      onOnline: _handleOnlineSignal,
    );
    _initializeRepositories();
  }

  @override
  void didUpdateWidget(covariant AppShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.tenantId.trim() != widget.identity.tenantId.trim()) {
      _representedScopeOptions = const <_RepresentedScopeOption>[];
      _selectedRepresentedScope = null;
      _representedScopeBackfillDone = false;
      _syncStatus = AppShellSyncStatus.initial();
      _lastCloudDeltaCheckAt = null;
      _costMetrics = const SyncCostMetricsSnapshot.empty();
      _costAlert = null;
      _queryReviewOverdue = true;
      _loadRepresentedScopeContext();
      unawaited(_refreshSyncStatusSnapshot(includeCloudDeltaCheck: true));
      unawaited(_refreshSyncCostMetrics());
    }
  }

  Future<void> _handleOnlineSignal() async {
    await _runAutomaticSyncCycle();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeRepositories() async {
    final AppShellRepositoryBundle repositoryBundle =
        _repositoryBootstrapCoordinator.build(
          identity: widget.identity,
          isWeb: kIsWeb,
          enableLocalMockFallback: _enableLocalMockFallback,
          firestore: FirebaseFirestore.instance,
        );
    if (!mounted) {
      return;
    }

    _updateViewState(
      (state) => _viewStateCoordinator.applyRepositoryBundle(
        state: state,
        bundle: repositoryBundle,
      ),
    );

    // Cost metrics are local/session-scoped telemetry and should be visible
    // even if this runtime is using a local data fallback.
    unawaited(_refreshSyncCostMetrics());

    if (repositoryBundle.usingLocalFallback) {
      return;
    }

    _seedFirestoreMocksIfNeeded();
    unawaited(_runAutomaticSyncCycle());
    unawaited(_refreshSyncStatusSnapshot(includeCloudDeltaCheck: true));
    _loadRepresentedScopeContext();
  }

  String _resolveMetricsActorId() {
    final membershipId = (widget.identity.membershipId ?? '').trim();
    if (membershipId.isNotEmpty) {
      return membershipId;
    }

    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (authUid.isNotEmpty) {
      return authUid;
    }

    final normalizedUserLabel = widget.identity.userLabel.trim();
    if (normalizedUserLabel.isNotEmpty) {
      return normalizedUserLabel;
    }

    return 'unknown_user';
  }

  void _applyCostMetricsState(SyncCostMetricsSnapshot metrics) {
    if (!mounted) {
      return;
    }

    setState(() {
      _costMetrics = metrics;
      _costAlert = _syncCostMetricsService.evaluateRegression(summary: metrics);
      _queryReviewOverdue = _syncCostMetricsService
          .isQueryPaginationReviewOverdue(metrics);
    });
  }

  Future<void> _refreshSyncCostMetrics() async {
    final tenantId = widget.identity.tenantId.trim();
    if (tenantId.isEmpty) {
      return;
    }

    final metrics = await _syncCostMetricsService.readToday(
      tenantId: tenantId,
      userId: _resolveMetricsActorId(),
    );
    _applyCostMetricsState(metrics);
  }

  Future<void> _registerQueryPaginationReview() async {
    final tenantId = widget.identity.tenantId.trim();
    if (tenantId.isEmpty) {
      return;
    }

    final metrics = await _syncCostMetricsService.markQueryPaginationReview(
      tenantId: tenantId,
      userId: _resolveMetricsActorId(),
    );
    _applyCostMetricsState(metrics);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Revisao de queries/paginacao registrada nesta sessao.'),
      ),
    );
  }

  Future<void> _recordCloudSnapshotCostMetrics(
    _CloudPendingSnapshot snapshot,
  ) async {
    final tenantId = widget.identity.tenantId.trim();
    if (tenantId.isEmpty || snapshot.queryOperations <= 0) {
      return;
    }

    final metrics = await _syncCostMetricsService.recordCloudSnapshotCheck(
      tenantId: tenantId,
      userId: _resolveMetricsActorId(),
      queryOperations: snapshot.queryOperations,
      estimatedDocumentReads: snapshot.estimatedDocumentReads,
      fallbackFullReads: snapshot.fallbackFullReads,
    );
    _applyCostMetricsState(metrics);
  }

  Future<void> _recordWarmupCostMetrics(CatalogWarmupSummary summary) async {
    final tenantId = widget.identity.tenantId.trim();
    if (tenantId.isEmpty) {
      return;
    }

    if (summary.queryOperations <= 0 &&
        summary.estimatedDocumentReads <= 0 &&
        summary.fallbackFullReads <= 0 &&
        summary.pagesPulled <= 0) {
      return;
    }

    final metrics = await _syncCostMetricsService.recordWarmupRun(
      tenantId: tenantId,
      userId: _resolveMetricsActorId(),
      pagesPulled: summary.pagesPulled,
      itemsPulled: summary.itemsPulled,
      queryOperations: summary.queryOperations,
      estimatedDocumentReads: summary.estimatedDocumentReads,
      fallbackFullReads: summary.fallbackFullReads,
    );
    _applyCostMetricsState(metrics);
  }

  Future<void> _runAutomaticSyncCycle() async {
    await _syncOfflineQueueIfOnline();
    await _warmupCatalogsIfOnline();
    await _refreshSyncStatusSnapshot(includeCloudDeltaCheck: true);
  }

  bool _belongsToCurrentWorkspace(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (widget.identity.isPersonalWorkspace) {
      final currentTenantId = widget.identity.tenantId.trim();
      return normalizedTenantId.isEmpty ||
          normalizedTenantId == currentTenantId ||
          normalizedTenantId.startsWith('personal_');
    }

    return normalizedTenantId == widget.identity.tenantId.trim();
  }

  Future<_SyncQueueSnapshot> _readSyncQueueSnapshot() async {
    final pendingEntries = await OfflineSyncQueue.readAll();
    final pendingDeletes = await OfflineSyncQueue.readPendingDeletes();

    var pendingClientes = 0;
    var pendingPreCadastros = 0;
    var pendingPedidos = 0;
    var scopedPendingDeletes = 0;

    for (final entry in pendingEntries) {
      if (entry.synced || !_belongsToCurrentWorkspace(entry.tenantId)) {
        continue;
      }

      if (entry.type == 'cliente') {
        pendingClientes++;
      } else if (entry.type == 'cliente_pre_cadastro') {
        pendingPreCadastros++;
      } else if (entry.type == 'pedido') {
        pendingPedidos++;
      }
    }

    for (final tombstone in pendingDeletes) {
      final tombstoneTenantId = (tombstone['tenantId'] ?? '').toString();
      if (_belongsToCurrentWorkspace(tombstoneTenantId)) {
        scopedPendingDeletes++;
      }
    }

    return _SyncQueueSnapshot(
      pendingClientes: pendingClientes,
      pendingPreCadastros: pendingPreCadastros,
      pendingPedidos: pendingPedidos,
      pendingDeletes: scopedPendingDeletes,
    );
  }

  Future<_CloudPendingSnapshot> _readCloudPendingSnapshot() async {
    final tenantId = widget.identity.tenantId.trim();
    if (tenantId.isEmpty) {
      return const _CloudPendingSnapshot(
        pendingClientes: 0,
        pendingProdutos: 0,
        pendingPedidos: 0,
        pendingTabelasPreco: 0,
        pendingTaxRules: 0,
        queryOperations: 0,
        estimatedDocumentReads: 0,
        fallbackFullReads: 0,
      );
    }

    final syncService = CatalogIncrementalSyncService(
      FirebaseFirestore.instance,
    );
    final results = await Future.wait<CatalogSyncPendingCountResult>([
      syncService.countPendingCloudToDeviceDeltaDetailed(
        tenantId: tenantId,
        module: CatalogSyncModule.clientes,
      ),
      syncService.countPendingCloudToDeviceDeltaDetailed(
        tenantId: tenantId,
        module: CatalogSyncModule.produtos,
      ),
      syncService.countPendingCloudToDeviceDeltaDetailed(
        tenantId: tenantId,
        module: CatalogSyncModule.pedidos,
      ),
      syncService.countPendingCloudToDeviceDeltaDetailed(
        tenantId: tenantId,
        module: CatalogSyncModule.tabelasPreco,
      ),
      syncService.countPendingCloudToDeviceDeltaDetailed(
        tenantId: tenantId,
        module: CatalogSyncModule.taxRules,
      ),
    ]);

    final snapshot = _CloudPendingSnapshot(
      pendingClientes: results[0].pendingCount,
      pendingProdutos: results[1].pendingCount,
      pendingPedidos: results[2].pendingCount,
      pendingTabelasPreco: results[3].pendingCount,
      pendingTaxRules: results[4].pendingCount,
      queryOperations: results
          .map((item) => item.queryOperations)
          .fold<int>(0, (acc, item) => acc + item),
      estimatedDocumentReads: results
          .map((item) => item.estimatedDocumentReads)
          .fold<int>(0, (acc, item) => acc + item),
      fallbackFullReads: results
          .map((item) => item.fallbackFullReads)
          .fold<int>(0, (acc, item) => acc + item),
    );

    await _recordCloudSnapshotCostMetrics(snapshot);

    return snapshot;
  }

  Future<_SyncStatusSnapshot> _refreshSyncStatusSnapshot({
    required bool includeCloudDeltaCheck,
  }) async {
    final queueSnapshot = await _readSyncQueueSnapshot();

    _CloudPendingSnapshot? cloudSnapshot;
    var cloudReachable = _syncStatus.cloudSnapshotReachable;
    var cloudSnapshotAt = _syncStatus.cloudSnapshotAt;

    final now = DateTime.now();
    final shouldCheckCloudDelta =
        includeCloudDeltaCheck &&
        !_usingLocalFallback &&
        (_lastCloudDeltaCheckAt == null ||
            now.difference(_lastCloudDeltaCheckAt!) >=
                _cloudDeltaRefreshInterval);

    if (shouldCheckCloudDelta) {
      final hasConnection = await _connectivityCoordinator.hasConnection(
        _connectivity,
      );
      if (hasConnection) {
        try {
          cloudSnapshot = await _readCloudPendingSnapshot();
          cloudReachable = true;
          cloudSnapshotAt = now;
          _lastCloudDeltaCheckAt = now;
        } catch (_) {
          cloudReachable = false;
        }
      } else {
        cloudReachable = false;
      }
    }

    final effectiveDownloadPending =
        cloudSnapshot?.totalPending ??
        (cloudReachable == true ? _syncStatus.totalDownloadPending : 0);

    String idlePhase;
    if (cloudReachable == false) {
      idlePhase = queueSnapshot.totalPending > 0
          ? 'Ha pendencias locais; sem conexao para verificar nuvem'
          : 'Sem conexao para verificar pendencias da nuvem';
    } else if (queueSnapshot.totalPending == 0 &&
        effectiveDownloadPending == 0) {
      idlePhase = 'Fila local e nuvem em dia';
    } else if (queueSnapshot.totalPending > 0 &&
        effectiveDownloadPending == 0) {
      idlePhase = 'Ha pendencias locais para enviar ao Firebase';
    } else if (queueSnapshot.totalPending == 0 &&
        effectiveDownloadPending > 0) {
      idlePhase = 'Ha atualizacoes na nuvem para baixar';
    } else {
      idlePhase = 'Ha pendencias locais e atualizacoes na nuvem';
    }

    if (mounted) {
      setState(() {
        _syncStatus = _syncStatus.copyWith(
          pendingUploadClientes: queueSnapshot.pendingClientes,
          pendingUploadPreCadastros: queueSnapshot.pendingPreCadastros,
          pendingUploadPedidos: queueSnapshot.pendingPedidos,
          pendingUploadDeletes: queueSnapshot.pendingDeletes,
          pendingDownloadClientes:
              cloudSnapshot?.pendingClientes ??
              _syncStatus.pendingDownloadClientes,
          pendingDownloadProdutos:
              cloudSnapshot?.pendingProdutos ??
              _syncStatus.pendingDownloadProdutos,
          pendingDownloadPedidos:
              cloudSnapshot?.pendingPedidos ??
              _syncStatus.pendingDownloadPedidos,
          pendingDownloadTabelasPreco:
              cloudSnapshot?.pendingTabelasPreco ??
              _syncStatus.pendingDownloadTabelasPreco,
          pendingDownloadTaxRules:
              cloudSnapshot?.pendingTaxRules ??
              _syncStatus.pendingDownloadTaxRules,
          cloudSnapshotAt: cloudSnapshotAt,
          cloudSnapshotReachable: cloudReachable,
          phase: _syncStatus.isRunning ? _syncStatus.phase : idlePhase,
        );
      });
    }

    return _SyncStatusSnapshot(
      queue: queueSnapshot,
      cloud: cloudSnapshot,
      cloudReachable: cloudReachable,
    );
  }

  void _setSyncStatus({
    required String phase,
    required bool isRunning,
    DateTime? lastAttemptAt,
    bool? lastAttemptSucceeded,
    String? lastMessage,
    bool clearLastMessage = false,
  }) {
    if (!mounted) {
      return;
    }

    setState(() {
      _syncStatus = _syncStatus.copyWith(
        phase: phase,
        isRunning: isRunning,
        lastAttemptAt: lastAttemptAt,
        lastAttemptSucceeded: lastAttemptSucceeded,
        lastMessage: lastMessage,
        clearLastMessage: clearLastMessage,
      );
    });
  }

  Future<void> _syncWorkspaceNow() async {
    if (_syncStatus.isRunning ||
        _viewState.syncInProgress ||
        _catalogWarmupRunning) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ja existe uma sincronizacao em andamento.'),
          ),
        );
      }
      return;
    }

    _setSyncStatus(phase: 'Verificando conectividade...', isRunning: true);

    final hasConnection = await _connectivityCoordinator.hasConnection(
      _connectivity,
    );
    if (!hasConnection) {
      final snapshot = await _refreshSyncStatusSnapshot(
        includeCloudDeltaCheck: true,
      );
      _setSyncStatus(
        phase: 'Sem conexao para sincronizar agora',
        isRunning: false,
        lastAttemptAt: DateTime.now(),
        lastAttemptSucceeded: false,
        lastMessage: 'Conexao indisponivel',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sem internet no momento. ${snapshot.totalUploadPending} item(ns) locais continuam pendentes.',
            ),
          ),
        );
      }
      return;
    }

    try {
      _setSyncStatus(
        phase: 'Enviando dados do dispositivo para a nuvem...',
        isRunning: true,
      );
      await _syncOfflineQueueIfOnline();

      _setSyncStatus(
        phase: 'Baixando atualizacoes da nuvem para o dispositivo...',
        isRunning: true,
      );
      await _warmupCatalogsIfOnline(fullPull: true);

      final snapshot = await _refreshSyncStatusSnapshot(
        includeCloudDeltaCheck: true,
      );
      final hasUploadPending = snapshot.totalUploadPending > 0;
      final hasDownloadPending = snapshot.totalDownloadPending > 0;
      final hasPending = hasUploadPending || hasDownloadPending;

      _setSyncStatus(
        phase: hasPending
            ? 'Sincronizacao concluida com pendencias'
            : 'Sincronizacao concluida',
        isRunning: false,
        lastAttemptAt: DateTime.now(),
        lastAttemptSucceeded: !hasPending,
        clearLastMessage: true,
      );

      if (!mounted) {
        return;
      }

      final message = hasPending
          ? 'Sincronizacao finalizada. Pendentes: ${snapshot.totalUploadPending} para enviar e ${snapshot.totalDownloadPending} para baixar.'
          : 'Sincronizacao geral concluida com sucesso.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      await _refreshSyncStatusSnapshot(includeCloudDeltaCheck: true);
      _setSyncStatus(
        phase: 'Falha na sincronizacao geral',
        isRunning: false,
        lastAttemptAt: DateTime.now(),
        lastAttemptSucceeded: false,
        lastMessage: error.toString(),
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao sincronizar: $error')));
    }
  }

  Future<void> _refreshSyncStatusFromHome() async {
    if (_syncStatus.isRunning) {
      return;
    }

    _setSyncStatus(
      phase: 'Atualizando status de sincronizacao...',
      isRunning: true,
    );
    try {
      await _refreshSyncStatusSnapshot(includeCloudDeltaCheck: true);
      _setSyncStatus(
        phase: 'Status de sincronizacao atualizado',
        isRunning: false,
        clearLastMessage: true,
      );
    } catch (error) {
      _setSyncStatus(
        phase: 'Falha ao atualizar status',
        isRunning: false,
        lastMessage: error.toString(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar status: $error')),
      );
    }
  }

  bool _supportsRepresentedScope() {
    final role = widget.identity.role.trim().toLowerCase();
    return widget.identity.isPersonalWorkspace ||
        role == 'owner' ||
        role == 'gerente' ||
        role == 'representante' ||
        role == 'vendedor' ||
        role == 'seller' ||
        role == 'sales';
  }

  Future<void> _loadRepresentedScopeContext() async {
    if (_usingLocalFallback || _representedScopeLoading) {
      return;
    }
    if (!_supportsRepresentedScope()) {
      return;
    }

    final tenantId = widget.identity.tenantId.trim();
    if (tenantId.isEmpty) {
      return;
    }

    _representedScopeLoading = true;
    if (mounted) {
      setState(() {});
    }

    try {
      final workspace = await _workspaceProfileService
          .watchWorkspace(tenantId)
          .first;
      final workspaceType = (workspace?['workspaceType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
      final isEnterpriseWorkspace = workspaceType == 'brand_owner_workspace';
      final favoriteId = (workspace?['favoriteRepresentedCompanyId'] ?? '')
          .toString()
          .trim();
      final representedCompanies = await _workspaceProfileService
          .watchRepresentedCompanies(tenantId)
          .first;

      final options = <_RepresentedScopeOption>[];
      for (final company in representedCompanies) {
        final representedId = (company['companyId'] ?? '').toString().trim();
        if (representedId.isEmpty || company['ativo'] == false) {
          continue;
        }
        final representedName = (company['nomeFantasia'] ?? '')
            .toString()
            .trim();
        final originLabel = representedName.isEmpty
            ? representedId
            : representedName;
        final originUf = (company['uf'] ?? '').toString().trim().toUpperCase();
        options.add(
          _RepresentedScopeOption(
            representedCompanyId: representedId,
            representedCompanyName: originLabel,
            originCompanyUnitId: representedId,
            originCompanyUnitLabel: originLabel,
            originCompanyUf: originUf,
          ),
        );
      }

      options.sort(
        (a, b) => a.representedCompanyName.toLowerCase().compareTo(
          b.representedCompanyName.toLowerCase(),
        ),
      );

      _RepresentedScopeOption? selected;
      if (favoriteId.isNotEmpty) {
        for (final option in options) {
          if (option.representedCompanyId == favoriteId) {
            selected = option;
            break;
          }
        }
      }

      if (isEnterpriseWorkspace) {
        final enterpriseName = (workspace?['nomeFantasia'] ??
                widget.identity.tenantName)
            .toString()
            .trim();
        final enterpriseUf =
            (workspace?['uf'] ?? '').toString().trim().toUpperCase();
        final fallbackOption = _RepresentedScopeOption(
          representedCompanyId: '',
          representedCompanyName: enterpriseName.isEmpty
              ? 'Empresa do workspace'
              : enterpriseName,
          originCompanyUnitId: tenantId,
          originCompanyUnitLabel: enterpriseName.isEmpty
              ? 'Empresa do workspace'
              : enterpriseName,
          originCompanyUf: enterpriseUf,
        );

        selected ??= fallbackOption;
        if (options.isEmpty) {
          options.add(fallbackOption);
        }
      }

      selected ??= options.isEmpty ? null : options.first;

      if (!mounted) {
        return;
      }

      setState(() {
        _representedScopeOptions = List<_RepresentedScopeOption>.unmodifiable(
          options,
        );
        _selectedRepresentedScope = selected;
      });

      unawaited(
        _runRepresentedScopeBackfillIfNeeded(
          options: options,
          selected: selected,
        ),
      );
    } finally {
      _representedScopeLoading = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _runRepresentedScopeBackfillIfNeeded({
    required List<_RepresentedScopeOption> options,
    required _RepresentedScopeOption? selected,
  }) async {
    if (_representedScopeBackfillDone || _representedScopeBackfillRunning) {
      return;
    }
    if (_usingLocalFallback) {
      return;
    }

    final tenantId = widget.identity.tenantId.trim();
    final activeRepresentedCompanyIds = options
      .map((option) => option.representedCompanyId.trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
    final preferredRepresentedCompanyId =
      selected?.representedCompanyId.trim() ?? '';
    if (tenantId.isEmpty || activeRepresentedCompanyIds.isEmpty) {
      return;
    }

    _representedScopeBackfillRunning = true;
    try {
      final result = await _representedScopeBackfillService.runForTenant(
        tenantId: tenantId,
        activeRepresentedCompanyIds: activeRepresentedCompanyIds,
        preferredRepresentedCompanyId: preferredRepresentedCompanyId.isEmpty
            ? null
            : preferredRepresentedCompanyId,
      );

      _representedScopeBackfillDone = true;

      if (!mounted) {
        return;
      }

      if (result.totalUpdated > 0) {
        final message =
            'Migração concluída: ${result.produtosUpdated} produto(s) e ${result.taxRulesUpdated} regra(s) fiscal(is) vinculados à representada ativa.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      } else if (result.unresolved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Migração parcial: ${result.unresolved} registro(s) legado(s) ainda sem representada definida.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Falha ao migrar dados legados por representada: $error',
          ),
        ),
      );
    } finally {
      _representedScopeBackfillRunning = false;
    }
  }

  Future<void> _openRepresentedScopePicker() async {
    if (_usingLocalFallback || _representedScopeLoading) {
      return;
    }
    if (_representedScopeOptions.isEmpty) {
      await _loadRepresentedScopeContext();
      if (_representedScopeOptions.isEmpty || !mounted) {
        return;
      }
    }

    final selectedId = _selectedRepresentedScope?.representedCompanyId;
    final pickedId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Selecionar representada ativa')),
              for (final option in _representedScopeOptions)
                ListTile(
                  onTap: () {
                    Navigator.of(sheetContext).pop(option.representedCompanyId);
                  },
                  title: Text(option.representedCompanyName),
                  subtitle: option.originCompanyUf.trim().isEmpty
                      ? null
                      : Text('UF origem: ${option.originCompanyUf}'),
                  trailing: option.representedCompanyId == selectedId
                      ? const Icon(Icons.check_circle, size: 18)
                      : const Icon(Icons.circle_outlined, size: 18),
                ),
            ],
          ),
        );
      },
    );

    final normalizedPickedId = (pickedId ?? '').trim();
    if (normalizedPickedId.isEmpty || normalizedPickedId == selectedId) {
      return;
    }

    _RepresentedScopeOption? nextSelection;
    for (final option in _representedScopeOptions) {
      if (option.representedCompanyId == normalizedPickedId) {
        nextSelection = option;
        break;
      }
    }
    if (nextSelection == null) {
      return;
    }

    setState(() {
      _selectedRepresentedScope = nextSelection;
    });

    try {
      await _workspaceProfileService.setFavoriteRepresentedCompany(
        tenantId: widget.identity.tenantId,
        companyId: nextSelection.representedCompanyId,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar representada ativa: $error')),
      );
    }
  }

  Future<void> _warmupCatalogsIfOnline({bool fullPull = false}) async {
    if (_catalogWarmupRunning) {
      return;
    }

    final repositoryBundle = _repositoryBundle;
    if (repositoryBundle == null || repositoryBundle.usingLocalFallback) {
      return;
    }

    final tenantId = widget.identity.tenantId.trim();
    if (tenantId.isEmpty) {
      return;
    }

    final hasConnection = await _connectivityCoordinator.hasConnection(
      _connectivity,
    );
    if (!hasConnection) {
      return;
    }

    _catalogWarmupRunning = true;
    try {
      final summary = await _catalogSyncCoordinator.warmupCatalogs(
        firestore: FirebaseFirestore.instance,
        tenantId: tenantId,
        maxPagesPerModule: fullPull ? null : 10,
      );
      await _recordWarmupCostMetrics(summary);
    } finally {
      _catalogWarmupRunning = false;
    }
  }

  Future<void> _syncOfflineQueueIfOnline() async {
    if (!mounted) {
      return;
    }

    final repositoryBundle = _repositoryBundle;
    if (repositoryBundle == null || _viewState.syncInProgress) {
      return;
    }

    final hasConnection = await _connectivityCoordinator.hasConnection(
      _connectivity,
    );
    if (!hasConnection) {
      return;
    }

    _updateViewState(_viewStateCoordinator.beginSync);
    try {
      await _offlineSyncCoordinator.syncPendingChanges(
        identity: widget.identity,
        clienteRepository: repositoryBundle.clienteRepository,
        preCadastroRepository: repositoryBundle.preCadastroRepository,
        pedidoRepository: repositoryBundle.pedidoRepository,
      );
    } finally {
      if (mounted) {
        _updateViewState(_viewStateCoordinator.endSync);
      }
    }
  }

  Future<void> _seedFirestoreMocksIfNeeded() async {
    final feedbackMessage = await _mockSeedCoordinator.seedIfNeeded(
      isDebugMode: kDebugMode,
      enableFirestoreMockSeed: _enableFirestoreMockSeed,
      identity: widget.identity,
      firestore: FirebaseFirestore.instance,
      actorUid: FirebaseAuth.instance.currentUser?.uid,
    );
    if (feedbackMessage == null || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(feedbackMessage)));
    });
  }

  List<AppShellItem> _buildItems() {
    final repositoryBundle = _repositoryBundle;
    if (repositoryBundle == null) {
      return const <AppShellItem>[];
    }

    return _navigationFactory.buildItems(
      role: widget.identity.role,
      usingLocalFallback: _usingLocalFallback,
      clienteRepository: repositoryBundle.clienteRepository,
      preCadastroRepository: repositoryBundle.preCadastroRepository,
      produtoRepository: repositoryBundle.produtoRepository,
      pedidoRepository: repositoryBundle.pedidoRepository,
      selectedRepresentedCompanyId:
          _selectedRepresentedScope?.representedCompanyId,
      selectedRepresentedCompanyName:
          _selectedRepresentedScope?.representedCompanyName,
      selectedOriginCompanyUnitId:
          _selectedRepresentedScope?.originCompanyUnitId,
      selectedOriginCompanyUnitLabel:
          _selectedRepresentedScope?.originCompanyUnitLabel,
      selectedOriginCompanyUf: _selectedRepresentedScope?.originCompanyUf,
      syncStatus: _syncStatus,
      costMetrics: _costMetrics,
      costAlert: _costAlert,
      queryReviewOverdue: _queryReviewOverdue,
      onSyncNow: _usingLocalFallback ? null : _syncWorkspaceNow,
      onRefreshSyncStatus: _usingLocalFallback
          ? null
          : _refreshSyncStatusFromHome,
      onRegisterQueryReview: _registerQueryPaginationReview,
      onAccessUpdated: widget.onAccessUpdated,
    );
  }

  void _setSelectedIndex(int index) {
    final items = _buildItems();
    final isHomeIndex =
        index >= 0 &&
        index < items.length &&
        (items[index].label.trim().toLowerCase() == 'inicio' ||
            items[index].label.trim().toLowerCase() == 'dashboard');

    _updateViewState(
      (state) => _viewStateCoordinator.applySelectedIndex(
        state: state,
        selectedIndex: index,
      ),
    );

    if (!_usingLocalFallback && isHomeIndex && !_syncStatus.isRunning) {
      unawaited(_refreshSyncStatusSnapshot(includeCloudDeltaCheck: true));
    }
  }

  void _normalizeSelectedIndexAfterBuild(int normalizedIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _setSelectedIndex(normalizedIndex);
    });
  }

  AppShellScaffoldPayload _buildScaffoldPayload({
    required List<AppShellItem> items,
    required AppShellSelection selection,
  }) {
    return AppShellScaffoldPayload(
      identity: widget.identity,
      items: items,
      selectedIndex: selection.safeIndex,
      selectedItem: selection.selectedItem,
      onDestinationSelected: _setSelectedIndex,
      onSignOut: widget.onSignOut,
      onSwitchProfile: widget.onSwitchProfile,
      onSyncNow: _usingLocalFallback ? null : _syncWorkspaceNow,
      syncRunning:
          _syncStatus.isRunning ||
          _viewState.syncInProgress ||
          _catalogWarmupRunning,
      representedScopeLabel: _selectedRepresentedScope?.displayLabel,
      representedScopeLoading: _representedScopeLoading,
      showRepresentedScopeBar:
          !_usingLocalFallback &&
          (_supportsRepresentedScope() || _representedScopeOptions.isNotEmpty),
      onRepresentedScopeTap: _supportsRepresentedScope()
          ? ((_selectedRepresentedScope?.representedCompanyId ?? '')
                .trim()
                .isEmpty
              ? null
              : _openRepresentedScopePicker)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !widget.forceMobilePreviewOnWeb) {
      return WebPortalPage(
        identity: widget.identity,
        onSignOut: widget.onSignOut,
      );
    }

    if (!_viewState.hasRepositories) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final items = _buildItems();
    final AppShellSelection? selection = _selectionCoordinator.resolve(
      selectedIndex: _viewState.selectedIndex,
      items: items,
    );

    if (selection == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: Text('Nenhum modulo disponivel para este perfil.'),
          ),
        ),
      );
    }

    if (selection.shouldNormalizeIndex) {
      _normalizeSelectedIndexAfterBuild(selection.safeIndex);
    }

    return AppShellScaffold(
      payload: _buildScaffoldPayload(items: items, selection: selection),
    );
  }
}

class _RepresentedScopeOption {
  const _RepresentedScopeOption({
    required this.representedCompanyId,
    required this.representedCompanyName,
    required this.originCompanyUnitId,
    required this.originCompanyUnitLabel,
    required this.originCompanyUf,
  });

  final String representedCompanyId;
  final String representedCompanyName;
  final String originCompanyUnitId;
  final String originCompanyUnitLabel;
  final String originCompanyUf;

  String get displayLabel {
    final uf = originCompanyUf.trim().toUpperCase();
    if (uf.isEmpty) {
      return representedCompanyName;
    }
    return '$representedCompanyName ($uf)';
  }
}

class _SyncQueueSnapshot {
  const _SyncQueueSnapshot({
    required this.pendingClientes,
    required this.pendingPreCadastros,
    required this.pendingPedidos,
    required this.pendingDeletes,
  });

  final int pendingClientes;
  final int pendingPreCadastros;
  final int pendingPedidos;
  final int pendingDeletes;

  int get totalPending =>
      pendingClientes + pendingPreCadastros + pendingPedidos + pendingDeletes;
}

class _CloudPendingSnapshot {
  const _CloudPendingSnapshot({
    required this.pendingClientes,
    required this.pendingProdutos,
    required this.pendingPedidos,
    required this.pendingTabelasPreco,
    required this.pendingTaxRules,
    required this.queryOperations,
    required this.estimatedDocumentReads,
    required this.fallbackFullReads,
  });

  final int pendingClientes;
  final int pendingProdutos;
  final int pendingPedidos;
  final int pendingTabelasPreco;
  final int pendingTaxRules;
  final int queryOperations;
  final int estimatedDocumentReads;
  final int fallbackFullReads;

  int get totalPending =>
      pendingClientes +
      pendingProdutos +
      pendingPedidos +
      pendingTabelasPreco +
      pendingTaxRules;
}

class _SyncStatusSnapshot {
  const _SyncStatusSnapshot({
    required this.queue,
    required this.cloud,
    required this.cloudReachable,
  });

  final _SyncQueueSnapshot queue;
  final _CloudPendingSnapshot? cloud;
  final bool? cloudReachable;

  int get totalUploadPending => queue.totalPending;
  int get totalDownloadPending => cloud?.totalPending ?? 0;
}
