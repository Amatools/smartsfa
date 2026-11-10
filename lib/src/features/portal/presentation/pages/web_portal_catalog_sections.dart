part of 'web_portal_page.dart';

class _PricingCatalogSection extends StatelessWidget {
  const _PricingCatalogSection({
    required this.activeTenant,
    this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final userLabel = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final identity = AppIdentity(
      tenantId: activeTenant.tenantId,
      userLabel: (userLabel == null || userLabel.isEmpty)
          ? 'Portal'
          : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace:
          activeTenant.workspaceType == 'seller_solo_workspace',
    );

    return TabelasPrecoPage(
      identity: identity,
      activeTenant: activeTenant,
      selectedRepresentedCompanyId: selectedRepresentedCompanyId,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
      repository: FirestoreTabelaPrecoRepository(FirebaseFirestore.instance),
      productRepository: FirestoreProdutoRepository(FirebaseFirestore.instance),
      basePriceRepository: FirestoreProductBasePriceRepository(
        FirebaseFirestore.instance,
      ),
    );
  }
}

class _SimpleSectionPage extends StatelessWidget {
  const _SimpleSectionPage._({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  factory _SimpleSectionPage.politicas({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
  }) {
    return _SimpleSectionPage._(
      title: 'Políticas comerciais',
      subtitle: 'Limites, aprovações e travas da empresa ativa.',
      items: const [
        'Limites por perfil',
        'Aprovações fora da curva',
        'Regras por grupo de produto',
      ],
      activeTenant: activeTenant,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
    );
  }

  static Widget enterprisePoliticas({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
  }) {
    return _EnterprisePoliciesSection(
      activeTenant: activeTenant,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
    );
  }

  static Widget enterpriseConfiguracoes({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
  }) {
    return _EnterpriseSettingsSection(
      activeTenant: activeTenant,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
    );
  }

  static Widget erp({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
  }) {
    return EnterpriseErpIntegrationSection(activeTenant: activeTenant);
  }

  factory _SimpleSectionPage.convites({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
  }) {
    return _SimpleSectionPage._(
      title: 'Convites e memberships',
      subtitle: 'Entrada de novos usuários para o tenant ativo.',
      items: const [
        'Convites pendentes',
        'Revisão de memberships',
        'Aprovação e revogação',
      ],
      activeTenant: activeTenant,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
    );
  }

  static Widget auditoria({
    required TenantEntryOption activeTenant,
    String? activeRepresentedCompanyName,
    String? selectedRepresentedCompanyId,
  }) {
    return _AuditSection(
      activeTenant: activeTenant,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
      selectedRepresentedCompanyId: selectedRepresentedCompanyId,
    );
  }

  final String title;
  final String subtitle;
  final List<String> items;
  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final representedName = activeRepresentedCompanyName?.trim() ?? '';
    final representedSuffix = representedName.isEmpty
        ? ' Representada ativa: não selecionada.'
        : ' Representada ativa: $representedName.';

    return _SimpleCardSection(
      title: title,
      subtitle:
          '$subtitle Tenant ativo: ${activeTenant.tenantName}.$representedSuffix',
      items: items,
    );
  }
}

class _AuditSection extends StatefulWidget {
  const _AuditSection({
    required this.activeTenant,
    required this.activeRepresentedCompanyName,
    required this.selectedRepresentedCompanyId,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;
  final String? selectedRepresentedCompanyId;

  @override
  State<_AuditSection> createState() => _AuditSectionState();
}

class _AuditSectionState extends State<_AuditSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!_tabController.indexIsChanging && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final userLabel = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final identity = AppIdentity(
      tenantId: widget.activeTenant.tenantId,
      userLabel: (userLabel == null || userLabel.isEmpty)
          ? 'Portal'
          : userLabel,
      role: widget.activeTenant.role,
      tenantName: widget.activeTenant.tenantName,
      isMock: false,
      membershipId: widget.activeTenant.membershipId,
      isPersonalWorkspace:
          widget.activeTenant.workspaceType == 'seller_solo_workspace',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Auditoria', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Membership'),
            Tab(text: 'Contexto'),
          ],
        ),
        const SizedBox(height: 12),
        if (_tabController.index == 0)
          TenantMembershipAuditPage(
            identity: identity,
            embedded: true,
            showIntroHeader: false,
          )
        else
          _AuditRepresentedContextTab(
            activeTenant: widget.activeTenant,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
            selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
          ),
      ],
    );
  }
}

class _AuditRepresentedContextTab extends StatelessWidget {
  const _AuditRepresentedContextTab({
    required this.activeTenant,
    required this.activeRepresentedCompanyName,
    required this.selectedRepresentedCompanyId,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;
  final String? selectedRepresentedCompanyId;

  @override
  Widget build(BuildContext context) {
    final representedId = (selectedRepresentedCompanyId ?? '').trim();
    if (representedId.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Selecione uma representada ativa para visualizar o contexto de auditoria.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final workspaceProfileService = WorkspaceProfileService(
      FirebaseFirestore.instance,
    );
    final representedName = (activeRepresentedCompanyName ?? '').trim();
    final representedLabel = representedName.isEmpty
        ? representedId
        : representedName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AuditScopeChip(label: 'Tenant', value: activeTenant.tenantName),
            _AuditScopeChip(label: 'Representada', value: representedLabel),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final tileWidth = wide
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: StreamBuilder<List<PaymentConditionRule>>(
                    stream: workspaceProfileService.watchPaymentConditionRules(
                      tenantId: activeTenant.tenantId,
                      representedCompanyId: representedId,
                    ),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length;
                      return _AuditMetricCard(
                        title: 'Condições de pagamento',
                        value: count == null ? '--' : count.toString(),
                        caption: snapshot.hasError
                            ? 'Falha ao carregar dados.'
                            : 'Regras no escopo da representada ativa.',
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: StreamBuilder<List<CommercialAdjustmentRule>>(
                    stream: workspaceProfileService
                        .watchCommercialAdjustmentRules(
                          tenantId: activeTenant.tenantId,
                          representedCompanyId: representedId,
                        ),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length;
                      return _AuditMetricCard(
                        title: 'Ajustes comerciais',
                        value: count == null ? '--' : count.toString(),
                        caption: snapshot.hasError
                            ? 'Falha ao carregar dados.'
                            : 'Regras de acrescimo e desconto ativas.',
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: StreamBuilder<OrderDiscountPolicy>(
                    stream: workspaceProfileService.watchOrderDiscountPolicy(
                      tenantId: activeTenant.tenantId,
                      representedCompanyId: representedId,
                    ),
                    builder: (context, snapshot) {
                      final fields = snapshot.data?.fields.length;
                      return _AuditMetricCard(
                        title: 'Faixas de desconto',
                        value: fields == null ? '--' : fields.toString(),
                        caption: snapshot.hasError
                            ? 'Falha ao carregar dados.'
                            : 'Campos de desconto configurados para pedidos.',
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: StreamBuilder<List<ProductCategoryTaxonomyItem>>(
                    stream: workspaceProfileService
                        .watchRepresentedProductTaxonomy(
                          tenantId: activeTenant.tenantId,
                          representedCompanyId: representedId,
                        ),
                    builder: (context, snapshot) {
                      final taxonomy =
                          snapshot.data ??
                          const <ProductCategoryTaxonomyItem>[];
                      var subcategories = 0;
                      for (final category in taxonomy) {
                        subcategories += category.subcategories.length;
                      }
                      final hasData = snapshot.data != null;
                      return _AuditMetricCard(
                        title: 'Taxonomia de produtos',
                        value: hasData
                            ? '${taxonomy.length}/$subcategories'
                            : '--',
                        caption: snapshot.hasError
                            ? 'Falha ao carregar dados.'
                            : 'Categorias/Subcategorias no escopo ativo.',
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AuditScopeChip extends StatelessWidget {
  const _AuditScopeChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditMetricCard extends StatelessWidget {
  const _AuditMetricCard({
    required this.title,
    required this.value,
    required this.caption,
  });

  final String title;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(caption, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ProductsCatalogSection extends StatelessWidget {
  const _ProductsCatalogSection({
    required this.activeTenant,
    this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final userLabel = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final identity = AppIdentity(
      tenantId: activeTenant.tenantId,
      userLabel: (userLabel == null || userLabel.isEmpty)
          ? 'Portal'
          : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace:
          activeTenant.workspaceType == 'seller_solo_workspace',
    );

    return ProdutosPage(
      identity: identity,
      repository: FirestoreProdutoRepository(FirebaseFirestore.instance),
      selectedRepresentedCompanyId: selectedRepresentedCompanyId,
      activeRepresentedCompanyName: activeRepresentedCompanyName,
    );
  }
}

class _CampaignProductsSection extends StatefulWidget {
  const _CampaignProductsSection({
    required this.activeTenant,
    required this.sourceType,
    this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;
  final OrderItemSourceType sourceType;

  @override
  State<_CampaignProductsSection> createState() =>
      _CampaignProductsSectionState();
}

class _CampaignProductsSectionState extends State<_CampaignProductsSection> {
  final TextEditingController _searchController = TextEditingController();
  late final FirestoreProdutoRepository _produtoRepository;
  final WorkspaceProfileService _workspaceProfileService =
      WorkspaceProfileService(FirebaseFirestore.instance);
  static final Map<String, String> _selectedListIdByScope = <String, String>{};
  static const String _allBrandsFilterValue = '__all_brands__';
  static const String _allCategoriesFilterValue = '__all_categories__';

  String _searchTerm = '';
  String _selectedBrand = _allBrandsFilterValue;
  String _selectedCategory = _allCategoriesFilterValue;

  final Set<String> _syncingProductIds = <String>{};
  final Set<String> _bulkSelectedProductIds = <String>{};
  bool _updatingListCatalog = false;

  @override
  void initState() {
    super.initState();
    _produtoRepository = FirestoreProdutoRepository(FirebaseFirestore.instance);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _title {
    if (widget.sourceType == OrderItemSourceType.promotion) {
      return 'Promocoes';
    }
    return 'Destaques';
  }

  String get _sourceLabelPlural {
    if (widget.sourceType == OrderItemSourceType.promotion) {
      return 'promocoes';
    }
    return 'destaques';
  }

  bool get _isPromotion {
    return widget.sourceType == OrderItemSourceType.promotion;
  }

  String? get _effectiveRepresentedCompanyId {
    return EnterpriseRepresentedScope.effectiveRepresentedCompanyId(
      tenantId: widget.activeTenant.tenantId,
      representedCompanyId: widget.selectedRepresentedCompanyId,
    );
  }

  String get _selectionScopeKey {
    return '${widget.activeTenant.tenantId}::${_effectiveRepresentedCompanyId ?? 'tenant_default'}::${widget.sourceType.value}';
  }

  String _resolveScopeLabel() {
    final represented = (widget.activeRepresentedCompanyName ?? '').trim();
    if (represented.isNotEmpty) {
      return represented;
    }
    final tenantName = widget.activeTenant.tenantName.trim();
    if (tenantName.isNotEmpty) {
      return tenantName;
    }
    return 'empresa ativa';
  }

  bool _matchesSearch(Produto product, String normalizedTerm) {
    if (normalizedTerm.isEmpty) {
      return true;
    }

    final haystack = <String>[
      product.codigoInterno,
      product.descricao,
      product.marca ?? '',
      product.ncm ?? '',
      product.categoria ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(normalizedTerm);
  }

  bool _matchesScope(Produto product) {
    final selectedRepresentedId = (widget.selectedRepresentedCompanyId ?? '')
        .trim();
    if (selectedRepresentedId.isEmpty) {
      return true;
    }

    final productRepresentedId = (product.representedCompanyId ?? '').trim();
    if (productRepresentedId.isEmpty) {
      return true;
    }
    return productRepresentedId == selectedRepresentedId;
  }

  bool _matchesBrandAndCategory(Produto product) {
    final productBrand = (product.marca ?? '').trim().toLowerCase();
    final productCategory = (product.categoria ?? '').trim().toLowerCase();

    final matchesBrand =
        _selectedBrand == _allBrandsFilterValue ||
        productBrand == _selectedBrand;
    final matchesCategory =
        _selectedCategory == _allCategoriesFilterValue ||
        productCategory == _selectedCategory;

    return matchesBrand && matchesCategory;
  }

  List<String> _availableBrands(List<Produto> products) {
    final byKey = <String, String>{};
    for (final item in products) {
      final brand = (item.marca ?? '').trim();
      if (brand.isEmpty) {
        continue;
      }
      byKey.putIfAbsent(brand.toLowerCase(), () => brand);
    }
    final values = byKey.values.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<String> _availableCategories(List<Produto> products) {
    final byKey = <String, String>{};
    for (final item in products) {
      final category = (item.categoria ?? '').trim();
      if (category.isEmpty) {
        continue;
      }
      byKey.putIfAbsent(category.toLowerCase(), () => category);
    }
    final values = byKey.values.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  String _normalizeFilterValue(String raw) {
    return raw.trim().toLowerCase();
  }

  String _formatDateShort(String? isoValue) {
    final normalized = (isoValue ?? '').trim();
    if (normalized.isEmpty) {
      return '--/--/----';
    }
    final parsed = DateTime.tryParse(normalized)?.toLocal();
    if (parsed == null) {
      return '--/--/----';
    }
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final year = parsed.year.toString();
    return '$day/$month/$year';
  }

  CampaignProductList? _resolveSelectedList(List<CampaignProductList> lists) {
    if (lists.isEmpty) {
      _selectedListIdByScope.remove(_selectionScopeKey);
      return null;
    }

    final preferredId = (_selectedListIdByScope[_selectionScopeKey] ?? '')
        .trim();
    if (preferredId.isEmpty) {
      return null;
    }

    for (final item in lists) {
      if (item.id == preferredId) {
        return item;
      }
    }

    _selectedListIdByScope.remove(_selectionScopeKey);
    return null;
  }

  void _openListForEdit(CampaignProductList list) {
    setState(() {
      _selectedListIdByScope[_selectionScopeKey] = list.id;
      _bulkSelectedProductIds.clear();
    });
  }

  void _closeListEditor() {
    setState(() {
      _selectedListIdByScope.remove(_selectionScopeKey);
      _bulkSelectedProductIds.clear();
      _searchTerm = '';
      _searchController.clear();
    });
  }

  Future<DateTime?> _pickDate({required DateTime? initialDate}) {
    final now = DateTime.now();
    final current = initialDate ?? now;
    return showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
  }

  Future<String?> _askListName({String initialValue = ''}) async {
    final controller = TextEditingController(text: initialValue);

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? validationMessage;
        return StatefulBuilder(
          builder: (statefulContext, setDialogState) {
            return AlertDialog(
              title: Text(
                initialValue.trim().isEmpty
                    ? 'Nova lista de $_sourceLabelPlural'
                    : 'Renomear lista',
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nome da lista',
                  border: const OutlineInputBorder(),
                  errorText: validationMessage,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final normalized = controller.text.trim();
                    if (normalized.isEmpty) {
                      setDialogState(() {
                        validationMessage = 'Informe um nome para a lista.';
                      });
                      return;
                    }
                    if (normalized.length < 3) {
                      setDialogState(() {
                        validationMessage = 'Use pelo menos 3 caracteres.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(normalized);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return value;
  }

  Future<void> _createList() async {
    final name = await _askListName();
    if (!mounted || name == null || name.trim().isEmpty) {
      return;
    }

    setState(() {
      _updatingListCatalog = true;
    });

    try {
      await _workspaceProfileService.createCampaignProductList(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: _effectiveRepresentedCompanyId,
        sourceType: widget.sourceType,
        name: name,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _bulkSelectedProductIds.clear();
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lista "$name" criada.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao criar lista: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _updatingListCatalog = false;
        });
      }
    }
  }

  Future<void> _renameList(CampaignProductList list) async {
    final nextName = await _askListName(initialValue: list.name);
    if (!mounted || nextName == null || nextName.trim().isEmpty) {
      return;
    }
    if (nextName.trim() == list.name.trim()) {
      return;
    }

    await _saveList(
      list.copyWith(name: nextName.trim()),
      successMessage: 'Nome da lista atualizado.',
    );
  }

  Future<void> _setListValidity({
    required CampaignProductList list,
    required bool updateStart,
  }) async {
    final initialDate = DateTime.tryParse(
      updateStart ? (list.validFromIso ?? '') : (list.validUntilIso ?? ''),
    );
    final picked = await _pickDate(initialDate: initialDate);
    if (!mounted || picked == null) {
      return;
    }

    final normalizedIso = DateTime(
      picked.year,
      picked.month,
      picked.day,
    ).toUtc().toIso8601String();

    final updated = updateStart
        ? list.copyWith(validFromIso: normalizedIso)
        : list.copyWith(validUntilIso: normalizedIso);

    await _saveList(updated, successMessage: 'Vigencia atualizada.');
  }

  Future<void> _clearListValidity({
    required CampaignProductList list,
    required bool clearStart,
  }) {
    final updated = clearStart
        ? list.copyWith(validFromIso: '')
        : list.copyWith(validUntilIso: '');
    return _saveList(updated, successMessage: 'Vigencia atualizada.');
  }

  Future<void> _toggleListActive(CampaignProductList list, bool nextValue) {
    return _saveList(
      list.copyWith(active: nextValue),
      successMessage: nextValue ? 'Lista ativada.' : 'Lista desativada.',
    );
  }

  Future<void> _deleteList(CampaignProductList list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir lista'),
          content: Text(
            'Deseja excluir a lista "${list.name}"? Os produtos nao serao apagados do catalogo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _updatingListCatalog = true;
    });
    try {
      await _workspaceProfileService.deleteCampaignProductList(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: _effectiveRepresentedCompanyId,
        sourceType: widget.sourceType,
        listId: list.id,
      );
      _selectedListIdByScope.remove(_selectionScopeKey);
      if (!mounted) {
        return;
      }
      setState(() {
        _bulkSelectedProductIds.clear();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Lista excluida.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao excluir lista: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _updatingListCatalog = false;
        });
      }
    }
  }

  Future<void> _updateListProducts({
    required CampaignProductList list,
    required List<CampaignProductListItem> nextItems,
    required String actingProductId,
  }) async {
    if (_syncingProductIds.contains(actingProductId)) {
      return;
    }

    setState(() {
      _syncingProductIds.add(actingProductId);
    });

    try {
      await _workspaceProfileService.upsertCampaignProductList(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: _effectiveRepresentedCompanyId,
        list: list.copyWith(items: nextItems),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar lista: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncingProductIds.remove(actingProductId);
        });
      }
    }
  }

  Future<void> _saveList(
    CampaignProductList list, {
    String? successMessage,
  }) async {
    setState(() {
      _updatingListCatalog = true;
    });
    try {
      await _workspaceProfileService.upsertCampaignProductList(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: _effectiveRepresentedCompanyId,
        list: list,
      );
      if (!mounted) {
        return;
      }
      if (successMessage != null && successMessage.trim().isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao salvar lista: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _updatingListCatalog = false;
        });
      }
    }
  }

  Future<void> _updatePromotionPrice({
    required CampaignProductList list,
    required String productId,
    required double currentPrice,
  }) async {
    final controller = TextEditingController(
      text: currentPrice.toStringAsFixed(2).replaceAll('.', ','),
    );

    final nextRaw = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (statefulContext, setDialogState) {
            return AlertDialog(
              title: const Text('Preco promocional'),
              content: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Novo preco',
                  border: const OutlineInputBorder(),
                  prefixText: 'R\$ ',
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final normalized = controller.text.trim().replaceAll(
                      ',',
                      '.',
                    );
                    final parsed = double.tryParse(normalized);
                    if (parsed == null || parsed < 0) {
                      setDialogState(() {
                        errorText = 'Informe um valor numerico valido.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(parsed.toString());
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();

    if (!mounted || nextRaw == null) {
      return;
    }

    final parsed = double.tryParse(nextRaw);
    if (parsed == null) {
      return;
    }

    final nextItems = list.items
        .map((item) {
          if (item.productId != productId) {
            return item;
          }
          return item.copyWith(promotionPrice: parsed);
        })
        .toList(growable: false);

    await _updateListProducts(
      list: list,
      nextItems: nextItems,
      actingProductId: productId,
    );
  }

  Future<double?> _askPromotionPercentDelta() async {
    final controller = TextEditingController(text: '-10');

    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (statefulContext, setDialogState) {
            return AlertDialog(
              title: const Text('Aplicar percentual em massa'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Use valor negativo para desconto (ex.: -10) e positivo para acrescimo (ex.: 5). O calculo sempre usa o preco base do item.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Percentual',
                      border: const OutlineInputBorder(),
                      suffixText: '%',
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final raw = controller.text.trim().replaceAll(',', '.');
                    final parsed = double.tryParse(raw);
                    if (parsed == null) {
                      setDialogState(() {
                        errorText = 'Informe um percentual valido.';
                      });
                      return;
                    }
                    if (parsed <= -100) {
                      setDialogState(() {
                        errorText = 'O percentual deve ser maior que -100%.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(parsed);
                  },
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return value;
  }

  Future<void> _applyPromotionPercentToAllItems({
    required CampaignProductList list,
    required Map<String, Produto> productById,
  }) async {
    if (list.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A lista nao possui itens para ajustar.')),
      );
      return;
    }

    final percentDelta = await _askPromotionPercentDelta();
    if (!mounted || percentDelta == null) {
      return;
    }

    final factor = 1 + (percentDelta / 100);
    if (factor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Percentual invalido: o preco resultante ficou <= 0.'),
        ),
      );
      return;
    }

    var adjustedCount = 0;
    final nextItems = list.items
        .map((item) {
          final productId = item.productId.trim();
          if (productId.isEmpty) {
            return item;
          }

          final baseValue = productById[productId]?.valorBruto;
          if (baseValue == null || baseValue < 0) {
            return item;
          }

          adjustedCount += 1;
          final nextValue = PedidoFormatUtils.roundCurrency(baseValue * factor);
          return item.copyWith(promotionPrice: nextValue);
        })
        .toList(growable: false);

    if (adjustedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum item elegivel para ajuste percentual.'),
        ),
      );
      return;
    }

    await _updateListProducts(
      list: list,
      nextItems: nextItems,
      actingProductId: list.items.first.productId,
    );

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Percentual aplicado em $adjustedCount item(ns).'),
      ),
    );
  }

  Future<void> _addSingleProductToList({
    required CampaignProductList list,
    required Produto product,
  }) {
    final alreadyExists = list.items.any(
      (item) => item.productId == product.id,
    );
    if (alreadyExists) {
      return Future<void>.value();
    }

    final nextItems = List<CampaignProductListItem>.from(list.items)
      ..add(
        CampaignProductListItem(
          productId: product.id,
          promotionPrice: _isPromotion
              ? PedidoFormatUtils.roundCurrency(product.valorBruto ?? 0)
              : null,
        ),
      );

    return _updateListProducts(
      list: list,
      nextItems: nextItems,
      actingProductId: product.id,
    );
  }

  Future<void> _addBulkProductsToList({
    required CampaignProductList list,
    required List<Produto> products,
  }) async {
    if (products.isEmpty) {
      return;
    }

    final existingIds = list.items.map((item) => item.productId).toSet();
    final nextItems = List<CampaignProductListItem>.from(list.items);
    for (final product in products) {
      if (!existingIds.add(product.id)) {
        continue;
      }
      nextItems.add(
        CampaignProductListItem(
          productId: product.id,
          promotionPrice: _isPromotion
              ? PedidoFormatUtils.roundCurrency(product.valorBruto ?? 0)
              : null,
        ),
      );
    }

    await _updateListProducts(
      list: list,
      nextItems: nextItems,
      actingProductId: products.first.id,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _bulkSelectedProductIds.clear();
    });
  }

  Future<void> _removeProductFromList({
    required CampaignProductList list,
    required String productId,
  }) {
    final nextItems = list.items
        .where((item) => item.productId != productId)
        .toList(growable: false);
    return _updateListProducts(
      list: list,
      nextItems: nextItems,
      actingProductId: productId,
    );
  }

  void _toggleProductSelection(String productId) {
    setState(() {
      if (_bulkSelectedProductIds.contains(productId)) {
        _bulkSelectedProductIds.remove(productId);
      } else {
        _bulkSelectedProductIds.add(productId);
      }
    });
  }

  void _toggleSelectAllFiltered(List<Produto> filteredProducts) {
    final ids = filteredProducts.map((item) => item.id).toSet();
    if (ids.isEmpty) {
      return;
    }

    final allSelected = ids.every((id) => _bulkSelectedProductIds.contains(id));
    setState(() {
      if (allSelected) {
        _bulkSelectedProductIds.removeAll(ids);
      } else {
        _bulkSelectedProductIds.addAll(ids);
      }
    });
  }

  void _ensureFiltersValid({
    required List<String> brands,
    required List<String> categories,
  }) {
    final availableBrandKeys = brands.map(_normalizeFilterValue).toSet()
      ..add(_allBrandsFilterValue);
    final availableCategoryKeys = categories.map(_normalizeFilterValue).toSet()
      ..add(_allCategoriesFilterValue);

    if (!availableBrandKeys.contains(_selectedBrand)) {
      _selectedBrand = _allBrandsFilterValue;
    }
    if (!availableCategoryKeys.contains(_selectedCategory)) {
      _selectedCategory = _allCategoriesFilterValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scopeLabel = _resolveScopeLabel();
    final normalizedSearch = _searchTerm.trim().toLowerCase();
    final sourceColor = _isPromotion
        ? Colors.green.shade700
        : Colors.blue.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Configure listas de $_sourceLabelPlural para uso comercial. Escopo: $scopeLabel.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        StreamBuilder<List<CampaignProductList>>(
          stream: _workspaceProfileService.watchCampaignProductLists(
            tenantId: widget.activeTenant.tenantId,
            representedCompanyId: _effectiveRepresentedCompanyId,
            sourceType: widget.sourceType,
          ),
          builder: (context, listSnapshot) {
            if (listSnapshot.connectionState == ConnectionState.waiting &&
                !listSnapshot.hasData) {
              return const Card(
                child: SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final lists = listSnapshot.data ?? const <CampaignProductList>[];
            final selectedList = _resolveSelectedList(lists);

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (selectedList == null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Listas de $_sourceLabelPlural (${lists.length})',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _updatingListCatalog
                                ? null
                                : _createList,
                            icon: const Icon(Icons.add),
                            label: const Text('Nova lista'),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Lista ativa',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: selectedList.id,
                                  items: lists
                                      .map(
                                        (list) => DropdownMenuItem<String>(
                                          value: list.id,
                                          child: Text(list.name),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: _updatingListCatalog
                                      ? null
                                      : (value) {
                                          if (value == null ||
                                              value.trim().isEmpty) {
                                            return;
                                          }
                                          CampaignProductList? nextList;
                                          for (final list in lists) {
                                            if (list.id == value) {
                                              nextList = list;
                                              break;
                                            }
                                          }
                                          if (nextList == null) {
                                            return;
                                          }
                                          _openListForEdit(nextList);
                                        },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _updatingListCatalog
                                ? null
                                : _closeListEditor,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Voltar para listas'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _updatingListCatalog
                                ? null
                                : _createList,
                            icon: const Icon(Icons.add),
                            label: const Text('Nova lista'),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Renomear lista ativa',
                            onPressed: _updatingListCatalog
                                ? null
                                : () => _renameList(selectedList),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Excluir lista ativa',
                            onPressed: _updatingListCatalog
                                ? null
                                : () => _deleteList(selectedList),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    if (selectedList == null) ...[
                      const SizedBox(height: 16),
                      if (lists.isEmpty)
                        Text(
                          'Nenhuma lista de $_sourceLabelPlural criada ainda. Crie uma lista para começar.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      else ...[
                        Text(
                          'Tela inicial de $_sourceLabelPlural: escolha uma lista para abrir e configurar.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 420,
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: ListView.separated(
                              itemCount: lists.length,
                              separatorBuilder: (_, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final list = lists[index];
                                final validityStart = _formatDateShort(
                                  list.validFromIso,
                                );
                                final validityEnd = _formatDateShort(
                                  list.validUntilIso,
                                );
                                final statusLabel = list.active
                                    ? 'Ativa'
                                    : 'Inativa';

                                return ListTile(
                                  title: Text(list.name),
                                  subtitle: Text(
                                    '$statusLabel · Itens ${list.items.length} · Vigencia $validityStart a $validityEnd',
                                  ),
                                  trailing: FilledButton.icon(
                                    onPressed: _updatingListCatalog
                                        ? null
                                        : () => _openListForEdit(list),
                                    icon: const Icon(Icons.open_in_new),
                                    label: const Text('Abrir'),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ] else ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('Lista ativa'),
                            selected: selectedList.active,
                            onSelected: _updatingListCatalog
                                ? null
                                : (value) =>
                                      _toggleListActive(selectedList, value),
                          ),
                          OutlinedButton.icon(
                            onPressed: _updatingListCatalog
                                ? null
                                : () => _setListValidity(
                                    list: selectedList,
                                    updateStart: true,
                                  ),
                            icon: const Icon(Icons.play_arrow_outlined),
                            label: Text(
                              'Inicio: ${_formatDateShort(selectedList.validFromIso)}',
                            ),
                          ),
                          IconButton(
                            tooltip: 'Limpar data inicial',
                            onPressed: _updatingListCatalog
                                ? null
                                : () => _clearListValidity(
                                    list: selectedList,
                                    clearStart: true,
                                  ),
                            icon: const Icon(Icons.clear),
                          ),
                          OutlinedButton.icon(
                            onPressed: _updatingListCatalog
                                ? null
                                : () => _setListValidity(
                                    list: selectedList,
                                    updateStart: false,
                                  ),
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: Text(
                              'Fim: ${_formatDateShort(selectedList.validUntilIso)}',
                            ),
                          ),
                          IconButton(
                            tooltip: 'Limpar data final',
                            onPressed: _updatingListCatalog
                                ? null
                                : () => _clearListValidity(
                                    list: selectedList,
                                    clearStart: false,
                                  ),
                            icon: const Icon(Icons.clear),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isPromotion
                            ? 'Tela exclusiva de configuracao: monte promocoes, ajuste preco por item e vigencia. Nao adiciona em pedido nesta etapa.'
                            : 'Tela exclusiva de configuracao: monte destaques sem alterar preco. Nao adiciona em pedido nesta etapa.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: sourceColor),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 680,
                        child: StreamBuilder<List<Produto>>(
                          stream: _produtoRepository.watchAll(
                            tenantId: widget.activeTenant.tenantId,
                          ),
                          builder: (context, productSnapshot) {
                            if (productSnapshot.connectionState ==
                                    ConnectionState.waiting &&
                                !productSnapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final all =
                                productSnapshot.data ?? const <Produto>[];
                            final scopedProducts =
                                all
                                    .where(
                                      (item) =>
                                          item.status == ProductStatus.active,
                                    )
                                    .where(_matchesScope)
                                    .toList(growable: false)
                                  ..sort(
                                    (a, b) => a.descricao
                                        .toLowerCase()
                                        .compareTo(b.descricao.toLowerCase()),
                                  );

                            final brands = _availableBrands(scopedProducts);
                            final categories = _availableCategories(
                              scopedProducts,
                            );
                            _ensureFiltersValid(
                              brands: brands,
                              categories: categories,
                            );

                            final productById = <String, Produto>{
                              for (final item in scopedProducts) item.id: item,
                            };

                            final listedProducts = selectedList.items
                                .map((entry) => productById[entry.productId])
                                .whereType<Produto>()
                                .where(_matchesBrandAndCategory)
                                .where(
                                  (item) =>
                                      _matchesSearch(item, normalizedSearch),
                                )
                                .toList(growable: false);

                            final listedIdSet = selectedList.productIds.toSet();
                            final availableProducts = scopedProducts
                                .where((item) => !listedIdSet.contains(item.id))
                                .where(_matchesBrandAndCategory)
                                .where(
                                  (item) =>
                                      _matchesSearch(item, normalizedSearch),
                                )
                                .toList(growable: false);

                            final selectedInFiltered = availableProducts
                                .where(
                                  (item) =>
                                      _bulkSelectedProductIds.contains(item.id),
                                )
                                .toList(growable: false);
                            final allFilteredSelected =
                                availableProducts.isNotEmpty &&
                                selectedInFiltered.length ==
                                    availableProducts.length;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _searchController,
                                        onChanged: (value) {
                                          setState(() {
                                            _searchTerm = value;
                                          });
                                        },
                                        decoration: const InputDecoration(
                                          labelText: 'Buscar por descricao, codigo, marca ou NCM',
                                          prefixIcon: Icon(Icons.search),
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 220,
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _selectedBrand,
                                        decoration: const InputDecoration(
                                          labelText: 'Marca',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        items: <DropdownMenuItem<String>>[
                                          const DropdownMenuItem<String>(
                                            value: _allBrandsFilterValue,
                                            child: Text('Todas as marcas'),
                                          ),
                                          ...brands.map(
                                            (brand) => DropdownMenuItem<String>(
                                              value: _normalizeFilterValue(
                                                brand,
                                              ),
                                              child: Text(brand),
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) {
                                            return;
                                          }
                                          setState(() {
                                            _selectedBrand = value;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 240,
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _selectedCategory,
                                        decoration: const InputDecoration(
                                          labelText: 'Categoria',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        items: <DropdownMenuItem<String>>[
                                          const DropdownMenuItem<String>(
                                            value: _allCategoriesFilterValue,
                                            child: Text('Todas as categorias'),
                                          ),
                                          ...categories.map(
                                            (category) =>
                                                DropdownMenuItem<String>(
                                                  value: _normalizeFilterValue(
                                                    category,
                                                  ),
                                                  child: Text(category),
                                                ),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) {
                                            return;
                                          }
                                          setState(() {
                                            _selectedCategory = value;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Text(
                                      'Selecionados para incluir: ${selectedInFiltered.length}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: availableProducts.isEmpty
                                          ? null
                                          : () => _toggleSelectAllFiltered(
                                              availableProducts,
                                            ),
                                      icon: Icon(
                                        allFilteredSelected
                                            ? Icons.deselect
                                            : Icons.select_all,
                                      ),
                                      label: Text(
                                        allFilteredSelected
                                            ? 'Desmarcar filtrados'
                                            : 'Selecionar filtrados',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.icon(
                                      onPressed:
                                          selectedInFiltered.isEmpty ||
                                              _updatingListCatalog
                                          ? null
                                          : () => _addBulkProductsToList(
                                              list: selectedList,
                                              products: selectedInFiltered,
                                            ),
                                      icon: const Icon(Icons.playlist_add),
                                      label: const Text('Incluir selecionados'),
                                    ),
                                    if (_isPromotion) ...[
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: _updatingListCatalog
                                            ? null
                                            : () =>
                                                  _applyPromotionPercentToAllItems(
                                                    list: selectedList,
                                                    productById: productById,
                                                  ),
                                        icon: const Icon(Icons.percent),
                                        label: const Text('Aplicar % em todos'),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Produtos na lista (${listedProducts.length})',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Card(
                                    margin: EdgeInsets.zero,
                                    child: listedProducts.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'Nenhum produto nesta lista.',
                                            ),
                                          )
                                        : ListView.separated(
                                            itemCount: listedProducts.length,
                                            separatorBuilder: (_, index) =>
                                                const Divider(height: 1),
                                            itemBuilder: (context, index) {
                                              final product =
                                                  listedProducts[index];
                                              final itemEntry = selectedList
                                                  .itemForProductId(product.id);
                                              final isSyncing =
                                                  _syncingProductIds.contains(
                                                    product.id,
                                                  );
                                              final price =
                                                  PedidoFormatUtils.formatMoneyBr(
                                                    product.valorBruto ?? 0,
                                                  );
                                              final promotionPrice =
                                                  itemEntry?.promotionPrice;
                                              final promotionPriceLabel =
                                                  promotionPrice == null
                                                  ? '-'
                                                  : PedidoFormatUtils.formatMoneyBr(
                                                      promotionPrice,
                                                    );

                                              return ListTile(
                                                dense: true,
                                                title: Text(product.descricao),
                                                subtitle: Text(
                                                  _isPromotion
                                                      ? '${product.codigoInterno.trim().isEmpty ? '-' : product.codigoInterno.trim()} · ${product.marca?.trim().isEmpty ?? true ? '-' : product.marca?.trim()} · R\$ base $price · R\$ promocao $promotionPriceLabel'
                                                      : '${product.codigoInterno.trim().isEmpty ? '-' : product.codigoInterno.trim()} · ${product.marca?.trim().isEmpty ?? true ? '-' : product.marca?.trim()} · NCM ${product.ncm?.trim().isEmpty ?? true ? '-' : product.ncm?.trim()} · R\$ $price',
                                                ),
                                                trailing: Wrap(
                                                  spacing: 8,
                                                  children: [
                                                    if (_isPromotion)
                                                      OutlinedButton.icon(
                                                        onPressed: isSyncing
                                                            ? null
                                                            : () => _updatePromotionPrice(
                                                                list:
                                                                    selectedList,
                                                                productId:
                                                                    product.id,
                                                                currentPrice:
                                                                    promotionPrice ??
                                                                    (product.valorBruto ??
                                                                        0),
                                                              ),
                                                        icon: const Icon(
                                                          Icons.sell_outlined,
                                                        ),
                                                        label: const Text(
                                                          'Preco',
                                                        ),
                                                      ),
                                                    IconButton(
                                                      tooltip:
                                                          'Remover da lista',
                                                      onPressed: isSyncing
                                                          ? null
                                                          : () => _removeProductFromList(
                                                              list:
                                                                  selectedList,
                                                              productId:
                                                                  product.id,
                                                            ),
                                                      icon: const Icon(
                                                        Icons
                                                            .remove_circle_outline,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Produtos disponiveis para incluir (${availableProducts.length})',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Card(
                                    margin: EdgeInsets.zero,
                                    child: availableProducts.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'Nenhum produto disponivel para incluir com o filtro atual.',
                                            ),
                                          )
                                        : ListView.separated(
                                            itemCount: availableProducts.length,
                                            separatorBuilder: (_, index) =>
                                                const Divider(height: 1),
                                            itemBuilder: (context, index) {
                                              final product =
                                                  availableProducts[index];
                                              final isSyncing =
                                                  _syncingProductIds.contains(
                                                    product.id,
                                                  );
                                              final price =
                                                  PedidoFormatUtils.formatMoneyBr(
                                                    product.valorBruto ?? 0,
                                                  );
                                              final selectedForBulk =
                                                  _bulkSelectedProductIds
                                                      .contains(product.id);

                                              return ListTile(
                                                dense: true,
                                                onTap: isSyncing
                                                    ? null
                                                    : () =>
                                                          _toggleProductSelection(
                                                            product.id,
                                                          ),
                                                leading: Checkbox(
                                                  value: selectedForBulk,
                                                  onChanged: isSyncing
                                                      ? null
                                                      : (_) =>
                                                            _toggleProductSelection(
                                                              product.id,
                                                            ),
                                                ),
                                                title: Text(product.descricao),
                                                subtitle: Text(
                                                  '${product.codigoInterno.trim().isEmpty ? '-' : product.codigoInterno.trim()} · ${product.marca?.trim().isEmpty ?? true ? '-' : product.marca?.trim()} · NCM ${product.ncm?.trim().isEmpty ?? true ? '-' : product.ncm?.trim()} · R\$ $price',
                                                ),
                                                trailing: FilledButton.icon(
                                                  onPressed: isSyncing
                                                      ? null
                                                      : () =>
                                                            _addSingleProductToList(
                                                              list:
                                                                  selectedList,
                                                              product: product,
                                                            ),
                                                  icon: const Icon(Icons.add),
                                                  label: const Text('Incluir'),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

enum _EnterprisePolicySubmenu {
  tributacoes,
  condicoesPagamento,
  descontosPontuais,
  acrescimosDescontos,
  promocoes,
  destaques,
}

class _EnterprisePoliciesSection extends StatefulWidget {
  const _EnterprisePoliciesSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  State<_EnterprisePoliciesSection> createState() =>
      _EnterprisePoliciesSectionState();
}

class _EnterprisePoliciesSectionState
    extends State<_EnterprisePoliciesSection> {
  static final Map<String, _EnterprisePolicySubmenu> _submenuByTenantId =
      <String, _EnterprisePolicySubmenu>{};

  _EnterprisePolicySubmenu _activeSubmenu =
      _EnterprisePolicySubmenu.tributacoes;

  String get _tenantId => widget.activeTenant.tenantId;

  @override
  void initState() {
    super.initState();
    _activeSubmenu =
        _submenuByTenantId[_tenantId] ?? _EnterprisePolicySubmenu.tributacoes;
  }

  @override
  void didUpdateWidget(covariant _EnterprisePoliciesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTenant.tenantId != widget.activeTenant.tenantId) {
      _activeSubmenu =
          _submenuByTenantId[_tenantId] ?? _EnterprisePolicySubmenu.tributacoes;
    }
  }

  String get _representedCompanyId {
    return _enterpriseDefaultRepresentedCompanyId(widget.activeTenant);
  }

  String get _representedCompanyName {
    final name = (widget.activeRepresentedCompanyName ?? '').trim();
    if (name.isNotEmpty) {
      return name;
    }
    final tenantName = widget.activeTenant.tenantName.trim();
    return tenantName.isEmpty ? 'Empresa ativa' : tenantName;
  }

  @override
  Widget build(BuildContext context) {
    final canAccessPolicies = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );

    if (!canAccessPolicies) {
      return const _SimpleCardSection(
        title: 'Políticas comerciais',
        subtitle:
            'Acesso restrito ao owner da empresa no workspace enterprise.',
        items: [
          'Tributações',
          'Condições de pagamento',
          'Descontos pontuais',
          'Acréscimos ou descontos',
          'Promoções',
          'Destaques',
        ],
      );
    }

    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Políticas comerciais', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Configure as políticas da empresa ativa. Escopo: $_representedCompanyName.',
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
                  submenu: _EnterprisePolicySubmenu.tributacoes,
                  label: 'Tributações',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterprisePolicySubmenu.condicoesPagamento,
                  label: 'Condições de pagamento',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterprisePolicySubmenu.descontosPontuais,
                  label: 'Descontos pontuais',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterprisePolicySubmenu.acrescimosDescontos,
                  label: 'Acréscimos ou descontos',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterprisePolicySubmenu.promocoes,
                  label: 'Promoções',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterprisePolicySubmenu.destaques,
                  label: 'Destaques',
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
    required _EnterprisePolicySubmenu submenu,
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
      case _EnterprisePolicySubmenu.tributacoes:
        return _TaxationSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: _representedCompanyId,
          activeRepresentedCompanyName: _representedCompanyName,
        );
      case _EnterprisePolicySubmenu.condicoesPagamento:
        return _PaymentConditionsSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: null,
          activeRepresentedCompanyName: null,
        );
      case _EnterprisePolicySubmenu.descontosPontuais:
        return _OrderDiscountPoliciesSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: null,
          activeRepresentedCompanyName: null,
        );
      case _EnterprisePolicySubmenu.acrescimosDescontos:
        return _CommercialAdjustmentsSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: null,
          activeRepresentedCompanyName: null,
        );
      case _EnterprisePolicySubmenu.promocoes:
        return _CampaignProductsSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: _representedCompanyId,
          activeRepresentedCompanyName: _representedCompanyName,
          sourceType: OrderItemSourceType.promotion,
        );
      case _EnterprisePolicySubmenu.destaques:
        return _CampaignProductsSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: _representedCompanyId,
          activeRepresentedCompanyName: _representedCompanyName,
          sourceType: OrderItemSourceType.highlight,
        );
    }
  }
}

enum _EnterpriseSettingsSubmenu {
  parametros,
  categorias,
  unidades,
  fotos,
  periodoInatividade,
}

class _EnterpriseSettingsSection extends StatefulWidget {
  const _EnterpriseSettingsSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  State<_EnterpriseSettingsSection> createState() =>
      _EnterpriseSettingsSectionState();
}

class _EnterpriseSettingsSectionState
    extends State<_EnterpriseSettingsSection> {
  static final Map<String, _EnterpriseSettingsSubmenu> _submenuByTenantId =
      <String, _EnterpriseSettingsSubmenu>{};

  _EnterpriseSettingsSubmenu _activeSubmenu =
      _EnterpriseSettingsSubmenu.parametros;

  String get _tenantId => widget.activeTenant.tenantId;

  @override
  void initState() {
    super.initState();
    _activeSubmenu =
        _submenuByTenantId[_tenantId] ?? _EnterpriseSettingsSubmenu.parametros;
  }

  @override
  void didUpdateWidget(covariant _EnterpriseSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTenant.tenantId != widget.activeTenant.tenantId) {
      _activeSubmenu =
          _submenuByTenantId[_tenantId] ??
          _EnterpriseSettingsSubmenu.parametros;
    }
  }

  String get _representedCompanyId {
    return _enterpriseDefaultRepresentedCompanyId(widget.activeTenant);
  }

  String get _representedCompanyName {
    final name = (widget.activeRepresentedCompanyName ?? '').trim();
    if (name.isNotEmpty) {
      return name;
    }
    final tenantName = widget.activeTenant.tenantName.trim();
    return tenantName.isEmpty ? 'Empresa ativa' : tenantName;
  }

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );

    if (!canEditSettings) {
      return const _SimpleCardSection(
        title: 'Configurações',
        subtitle:
            'Acesso restrito ao owner da empresa no workspace enterprise.',
        items: [
          'Parâmetros',
          'Categorias',
          'Unidades',
          'Fotos',
          'Período de inatividade',
        ],
      );
    }

    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Configurações', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Gerencie recursos da empresa ativa. Escopo: $_representedCompanyName.',
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
                  submenu: _EnterpriseSettingsSubmenu.parametros,
                  label: 'Parâmetros',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterpriseSettingsSubmenu.categorias,
                  label: 'Categorias',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterpriseSettingsSubmenu.unidades,
                  label: 'Unidades',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterpriseSettingsSubmenu.fotos,
                  label: 'Fotos',
                ),
                _buildSubmenuChip(
                  context,
                  submenu: _EnterpriseSettingsSubmenu.periodoInatividade,
                  label: 'Período de inatividade',
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
    required _EnterpriseSettingsSubmenu submenu,
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
      case _EnterpriseSettingsSubmenu.parametros:
        return _WorkspaceParametersSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: _representedCompanyId,
        );
      case _EnterpriseSettingsSubmenu.categorias:
        return _CategoriesSection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: _representedCompanyId,
          activeRepresentedCompanyName: _representedCompanyName,
        );
      case _EnterpriseSettingsSubmenu.unidades:
        return _UnitsSection(
          activeTenant: widget.activeTenant,
          activeRepresentedCompanyName: _representedCompanyName,
        );
      case _EnterpriseSettingsSubmenu.fotos:
        return _MediaLibrarySection(
          activeTenant: widget.activeTenant,
          selectedRepresentedCompanyId: _representedCompanyId,
          activeRepresentedCompanyName: _representedCompanyName,
        );
      case _EnterpriseSettingsSubmenu.periodoInatividade:
        return _InactivityPeriodSection(
          activeTenant: widget.activeTenant,
          activeRepresentedCompanyName: _representedCompanyName,
        );
    }
  }
}

class _SimpleCardSection extends StatelessWidget {
  const _SimpleCardSection({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String title;
  final String subtitle;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(subtitle, style: textTheme.bodyLarge),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Blocos previstos', style: textTheme.titleMedium),
                const SizedBox(height: 12),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Icon(Icons.check_circle_outline, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(item)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PortalModule {
  const _PortalModule({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

class _PortalModuleCard extends StatelessWidget {
  const _PortalModuleCard({required this.module});

  final _PortalModule module;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(module.icon, size: 28),
            const SizedBox(height: 12),
            Text(module.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(module.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersSection extends StatelessWidget {
  const _OrdersSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final userLabel = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final identity = AppIdentity(
      tenantId: activeTenant.tenantId,
      userLabel: (userLabel == null || userLabel.isEmpty)
          ? 'Portal'
          : userLabel,
      role: activeTenant.role,
      tenantName: activeTenant.tenantName,
      isMock: false,
      membershipId: activeTenant.membershipId,
      isPersonalWorkspace:
          activeTenant.workspaceType == 'seller_solo_workspace',
    );

    final representedName = (activeRepresentedCompanyName ?? '').trim();
    if (representedName.isEmpty) {
      return PedidosPage(
        identity: identity,
        repository: FirestorePedidoRepository(FirebaseFirestore.instance),
        produtoRepository: FirestoreProdutoRepository(
          FirebaseFirestore.instance,
        ),
      );
    }

    return StreamBuilder<List<Map<String, Object?>>>(
      stream: WorkspaceProfileService(FirebaseFirestore.instance)
          .watchRepresentedCompanies(activeTenant.tenantId),
      builder: (context, snapshot) {
        final representedCompanies =
            snapshot.data ?? const <Map<String, Object?>>[];

        Map<String, Object?>? selectedCompany;
        for (final company in representedCompanies) {
          final companyName = (company['nomeFantasia'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (companyName == representedName.toLowerCase()) {
            selectedCompany = company;
            break;
          }
        }

        final originCompanyId = (selectedCompany?['companyId'] ?? '')
            .toString()
            .trim();
        final originCompanyLabel = (selectedCompany?['nomeFantasia'] ?? '')
            .toString()
            .trim();
        final originCompanyUf = (selectedCompany?['uf'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

        return PedidosPage(
          identity: identity,
          repository: FirestorePedidoRepository(FirebaseFirestore.instance),
          produtoRepository: FirestoreProdutoRepository(
            FirebaseFirestore.instance,
          ),
          representedCompanyId: originCompanyId.isEmpty
              ? null
              : originCompanyId,
          originCompanyUnitId: originCompanyId.isEmpty ? null : originCompanyId,
          originCompanyUnitLabel: originCompanyLabel.isEmpty
              ? null
              : originCompanyLabel,
          originCompanyUf: originCompanyUf.isEmpty ? null : originCompanyUf,
        );
      },
    );
  }
}
