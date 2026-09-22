import '../models/app_shell_item.dart';
import '../models/app_shell_selection.dart';

class AppShellSelectionCoordinator {
  const AppShellSelectionCoordinator();

  AppShellSelection? resolve({
    required int selectedIndex,
    required List<AppShellItem> items,
  }) {
    if (items.isEmpty) {
      return null;
    }

    final safeIndex = selectedIndex.clamp(0, items.length - 1);
    return AppShellSelection(
      safeIndex: safeIndex,
      selectedItem: items[safeIndex],
      shouldNormalizeIndex: safeIndex != selectedIndex,
    );
  }
}
