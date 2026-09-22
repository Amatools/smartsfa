import 'package:flutter/material.dart';

import '../../core/models/app_identity.dart';

typedef AppShellPageBuilder = Widget Function(
  BuildContext context,
  AppIdentity identity,
);

class AppShellItem {
  const AppShellItem({
    required this.label,
    required this.icon,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final AppShellPageBuilder builder;
}
