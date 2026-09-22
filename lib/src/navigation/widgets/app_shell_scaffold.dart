import 'package:flutter/material.dart';

import '../models/app_shell_scaffold_payload.dart';

class AppShellScaffold extends StatelessWidget {
  const AppShellScaffold({super.key, required this.payload});

  final AppShellScaffoldPayload payload;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: Text(payload.selectedItem.label),
        actions: [
          if (payload.onSwitchProfile != null)
            IconButton(
              onPressed: payload.onSwitchProfile,
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Trocar perfil',
            ),
          IconButton(
            onPressed: payload.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
          ),
        ],
      ),
      body: SafeArea(
        child: isWide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: payload.selectedIndex,
                    onDestinationSelected: payload.onDestinationSelected,
                    labelType: NavigationRailLabelType.all,
                    destinations: payload.items
                        .map(
                          (item) => NavigationRailDestination(
                            icon: Icon(item.icon),
                            label: Text(item.label),
                          ),
                        )
                        .toList(),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: payload.selectedItem.builder(
                      context,
                      payload.identity,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(
                    child: payload.selectedItem.builder(
                      context,
                      payload.identity,
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: payload.selectedIndex,
              onDestinationSelected: payload.onDestinationSelected,
              destinations: payload.items
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
    );
  }
}
