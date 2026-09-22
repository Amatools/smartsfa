import '../models/app_shell_repository_bundle.dart';
import '../models/app_shell_view_state.dart';

class AppShellViewStateCoordinator {
  const AppShellViewStateCoordinator();

  AppShellViewState applyRepositoryBundle({
    required AppShellViewState state,
    required AppShellRepositoryBundle bundle,
  }) {
    return state.copyWith(repositoryBundle: bundle);
  }

  AppShellViewState applySelectedIndex({
    required AppShellViewState state,
    required int selectedIndex,
  }) {
    return state.copyWith(selectedIndex: selectedIndex);
  }

  AppShellViewState beginSync(AppShellViewState state) {
    return state.copyWith(syncInProgress: true);
  }

  AppShellViewState endSync(AppShellViewState state) {
    return state.copyWith(syncInProgress: false);
  }
}
