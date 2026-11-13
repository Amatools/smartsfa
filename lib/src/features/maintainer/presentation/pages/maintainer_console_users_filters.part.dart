part of 'maintainer_console_page.dart';

extension _MaintainerConsoleUsersFiltersPart on _MaintainerConsolePageState {
  Widget _buildUserFiltersRow(
    List<String> tenantOptions,
    String? selectedTenant,
    Map<String, String> tenantNamesById,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final stacked = maxWidth < 860;
        final searchWidth = stacked
            ? maxWidth
            : math.min(340.0, maxWidth * 0.34);
        final tenantWidth = stacked
            ? maxWidth
            : math.max(320.0, maxWidth - searchWidth - 12);
        final selectedTenantLabel =
            (selectedTenant == null || selectedTenant.trim().isEmpty)
            ? 'Todos os tenants'
            : _tenantFilterLabel(selectedTenant, tenantNamesById);
        final dropdownEntries = <DropdownMenuEntry<String>>[
          const DropdownMenuEntry<String>(value: '', label: 'Todos os tenants'),
          for (final tenantId in tenantOptions)
            (() {
              final label = _tenantFilterLabel(tenantId, tenantNamesById);
              return DropdownMenuEntry<String>(
                value: tenantId,
                label: label,
                labelWidget: Tooltip(
                  message: label,
                  waitDuration: const Duration(milliseconds: 350),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            })(),
        ];

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: searchWidth,
              child: TextField(
                controller: _userSearchController,
                onChanged: (_) => _resetUsersPageIndex(),
                decoration: const InputDecoration(
                  labelText: 'Buscar por e-mail, nome ou uid',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: tenantWidth,
              child: Tooltip(
                message: selectedTenantLabel,
                waitDuration: const Duration(milliseconds: 350),
                child: DropdownMenu<String>(
                  key: ValueKey<String>(selectedTenant ?? ''),
                  width: tenantWidth,
                  expandedInsets: EdgeInsets.zero,
                  enableFilter: true,
                  enableSearch: true,
                  requestFocusOnTap: true,
                  menuHeight: 420,
                  initialSelection: selectedTenant ?? '',
                  label: const Text('Filtrar por tenant (workspace)'),
                  hintText: 'Todos os tenants',
                  dropdownMenuEntries: dropdownEntries,
                  onSelected: (value) {
                    final normalized = (value ?? '').trim();
                    _applyUserTenantFilter(
                      normalized.isEmpty ? null : normalized,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
