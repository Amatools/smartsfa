import 'app_shell_repository_bundle.dart';

class AppShellViewState {
  const AppShellViewState({
    required this.selectedIndex,
    required this.syncInProgress,
    required this.repositoryBundle,
  });

  factory AppShellViewState.initial() {
    return const AppShellViewState(
      selectedIndex: 0,
      syncInProgress: false,
      repositoryBundle: null,
    );
  }

  final int selectedIndex;
  final bool syncInProgress;
  final AppShellRepositoryBundle? repositoryBundle;

  bool get hasRepositories => repositoryBundle != null;

  AppShellViewState copyWith({
    int? selectedIndex,
    bool? syncInProgress,
    AppShellRepositoryBundle? repositoryBundle,
    bool clearRepositoryBundle = false,
  }) {
    return AppShellViewState(
      selectedIndex: selectedIndex ?? this.selectedIndex,
      syncInProgress: syncInProgress ?? this.syncInProgress,
      repositoryBundle: clearRepositoryBundle
          ? null
          : repositoryBundle ?? this.repositoryBundle,
    );
  }
}
