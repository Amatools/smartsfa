import 'app_shell_item.dart';

class AppShellSelection {
  const AppShellSelection({
    required this.safeIndex,
    required this.selectedItem,
    required this.shouldNormalizeIndex,
  });

  final int safeIndex;
  final AppShellItem selectedItem;
  final bool shouldNormalizeIndex;
}
