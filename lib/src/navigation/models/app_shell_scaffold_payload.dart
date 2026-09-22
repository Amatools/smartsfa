import 'package:flutter/material.dart';

import '../../core/models/app_identity.dart';
import 'app_shell_item.dart';

class AppShellScaffoldPayload {
  const AppShellScaffoldPayload({
    required this.identity,
    required this.items,
    required this.selectedIndex,
    required this.selectedItem,
    required this.onDestinationSelected,
    required this.onSignOut,
    required this.onSwitchProfile,
  });

  final AppIdentity identity;
  final List<AppShellItem> items;
  final int selectedIndex;
  final AppShellItem selectedItem;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSignOut;
  final VoidCallback? onSwitchProfile;
}
