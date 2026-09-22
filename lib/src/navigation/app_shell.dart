import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/models/app_identity.dart';
import '../features/portal/presentation/pages/web_portal_page.dart';
import 'models/app_shell_item.dart';
import 'models/app_shell_repository_bundle.dart';
import 'models/app_shell_scaffold_payload.dart';
import 'models/app_shell_selection.dart';
import 'models/app_shell_view_state.dart';
import 'services/app_shell_connectivity_coordinator.dart';
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
  });

  final AppIdentity identity;
  final VoidCallback onSignOut;
  final VoidCallback? onAccessUpdated;
  final VoidCallback? onSwitchProfile;

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

  AppShellViewState _viewState = AppShellViewState.initial();
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final AppShellNavigationFactory _navigationFactory =
      const AppShellNavigationFactory();
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

  AppShellRepositoryBundle? get _repositoryBundle =>
      _viewState.repositoryBundle;
  bool get _usingLocalFallback =>
      _repositoryBundle?.usingLocalFallback ?? false;

  void _updateViewState(
    AppShellViewState Function(AppShellViewState state) update,
  ) {
    setState(() {
      _viewState = update(_viewState);
    });
  }

  @override
  void initState() {
    super.initState();
    _connectivitySubscription = _connectivityCoordinator.watchOnlineChanges(
      connectivity: _connectivity,
      onOnline: _syncOfflineQueueIfOnline,
    );
    _initializeRepositories();
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

    if (repositoryBundle.usingLocalFallback) {
      return;
    }

    _seedFirestoreMocksIfNeeded();
    _syncOfflineQueueIfOnline();
  }

  Future<void> _syncOfflineQueueIfOnline() async {
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
      onAccessUpdated: widget.onAccessUpdated,
    );
  }

  void _setSelectedIndex(int index) {
    _updateViewState(
      (state) => _viewStateCoordinator.applySelectedIndex(
        state: state,
        selectedIndex: index,
      ),
    );
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
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
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
