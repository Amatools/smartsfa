part of 'web_portal_page.dart';

enum _TaxationSubmenu { matrizTributaria, gruposTributarios, perfisOperacao }

class _TaxationSection extends StatefulWidget {
  const _TaxationSection({
    required this.activeTenant,
    this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_TaxationSection> createState() => _TaxationSectionState();
}

class _TaxationSectionState extends State<_TaxationSection> {
  static final Map<String, _TaxationSubmenu> _submenuByTenantId =
      <String, _TaxationSubmenu>{};

  late _TaxationSubmenu _activeSubmenu;

  String get _tenantId => widget.activeTenant.tenantId;

  @override
  void initState() {
    super.initState();
    _activeSubmenu =
        _submenuByTenantId[_tenantId] ?? _TaxationSubmenu.matrizTributaria;
  }

  @override
  void didUpdateWidget(covariant _TaxationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTenant.tenantId != widget.activeTenant.tenantId) {
      _activeSubmenu =
          _submenuByTenantId[_tenantId] ?? _TaxationSubmenu.matrizTributaria;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tributações', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Estruture a tributação em três frentes: matriz, grupos tributários e perfis de operação.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.45),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildSubmenuChip(
                  context,
                  submenu: _TaxationSubmenu.matrizTributaria,
                  label: 'Matriz tributária',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _TaxationSubmenu.gruposTributarios,
                  label: 'Grupos tributários',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _TaxationSubmenu.perfisOperacao,
                  label: 'Perfis de operação',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildSubmenuContent(),
      ],
    );
  }

  Widget _buildSubmenuChip(
    BuildContext context, {
    required _TaxationSubmenu submenu,
    required String label,
  }) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      selectedColor: Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: 0.8),
      backgroundColor: Colors.white,
      selected: _activeSubmenu == submenu,
      onSelected: (_) {
        setState(() {
          _activeSubmenu = submenu;
          _submenuByTenantId[_tenantId] = submenu;
        });
      },
    );
  }

  Widget _buildSubmenuContent() {
    switch (_activeSubmenu) {
      case _TaxationSubmenu.matrizTributaria:
        return _TaxRulesSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
          activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
        );
      case _TaxationSubmenu.gruposTributarios:
        return _TaxRuleGroupsSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
          activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
        );
      case _TaxationSubmenu.perfisOperacao:
        return _TaxOperationProfilesSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
          activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
        );
    }
  }
}
