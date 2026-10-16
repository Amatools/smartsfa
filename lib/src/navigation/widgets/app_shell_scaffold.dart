import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/app_shell_scaffold_payload.dart';

class AppShellScaffold extends StatelessWidget {
  const AppShellScaffold({super.key, required this.payload});

  final AppShellScaffoldPayload payload;

  String _navigationLabel({required String label, required bool isWide}) {
    if (isWide) {
      return label;
    }

    final normalized = label.trim().toLowerCase();
    if (normalized == 'dashboard' || normalized == 'inicio') {
      return 'Inicio';
    }

    return label;
  }

  Widget _buildRepresentedScopeBar(
    BuildContext context, {
    required bool compactChrome,
  }) {
    final representedLabel = (payload.representedScopeLabel ?? '').trim();
    final subtitle = payload.representedScopeLoading
        ? 'Representada: carregando...'
        : representedLabel.isEmpty
        ? 'Representada: não selecionada'
        : 'Representada: $representedLabel';

    final content = Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: compactChrome ? 5 : 4,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.apartment_outlined, size: 13),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (payload.onRepresentedScopeTap != null)
            TextButton(
              onPressed: payload.onRepresentedScopeTap,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 18),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Trocar'),
            ),
        ],
      ),
    );

    if (payload.onRepresentedScopeTap == null) {
      return content;
    }

    return InkWell(onTap: payload.onRepresentedScopeTap, child: content);
  }

  @override
  Widget build(BuildContext context) {
    final rawMode =
        (kIsWeb ? Uri.base.queryParameters['mode'] : null)
            ?.trim()
            .toLowerCase() ??
        '';
    final isWebMobilePreview =
        kIsWeb && (rawMode == 'mobile' || rawMode == 'app');
    final isWide = kIsWeb
        ? !isWebMobilePreview
        : MediaQuery.sizeOf(context).width >= 900;
    final mobileNavigationBarHeight = kIsWeb ? 76.0 : 72.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        surfaceTintColor: Theme.of(context).colorScheme.primary,
        title: Text(payload.selectedItem.label),
        actions: [
          if (payload.onSwitchProfile != null)
            IconButton(
              onPressed: payload.onSwitchProfile,
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Trocar workspace',
            ),
          if (payload.onSyncNow != null)
            IconButton(
              onPressed: payload.syncRunning ? null : payload.onSyncNow,
              tooltip: payload.syncRunning
                  ? 'Sincronizando...'
                  : 'Sincronizar agora',
              icon: payload.syncRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
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
                    child: Column(
                      children: [
                        if (payload.showRepresentedScopeBar)
                          _buildRepresentedScopeBar(
                            context,
                            compactChrome: false,
                          ),
                        Expanded(
                          child: payload.selectedItem.builder(
                            context,
                            payload.identity,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  if (payload.showRepresentedScopeBar)
                    _buildRepresentedScopeBar(context, compactChrome: true),
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
          : NavigationBarTheme(
              data: NavigationBarThemeData(
                height: mobileNavigationBarHeight,
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: selected ? 11 : 10,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    letterSpacing: -0.1,
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: payload.selectedIndex,
                onDestinationSelected: payload.onDestinationSelected,
                destinations: payload.items
                    .map(
                      (item) => NavigationDestination(
                        icon: Icon(item.icon),
                        label: _navigationLabel(
                          label: item.label,
                          isWide: isWide,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }
}
