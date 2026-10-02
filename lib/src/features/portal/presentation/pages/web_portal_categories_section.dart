part of 'web_portal_page.dart';

class _CategoriesSection extends StatefulWidget {
  const _CategoriesSection({
    required this.activeTenant,
    required this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_CategoriesSection> createState() => _CategoriesSectionState();
}

class _CategoriesSectionState extends State<_CategoriesSection> {
  final WorkspaceProfileService _service = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );
  final TextEditingController _newCategoryController = TextEditingController();
  final TextEditingController _inlineEditController = TextEditingController();
  List<ProductCategoryTaxonomyItem> _draftTaxonomy = const [];
  String? _selectedCategory;
  final Set<String> _expandedCategories = <String>{};
  String? _editingCategoryName;
  String? _editingSubcategoryCategoryName;
  String? _editingSubcategoryName;
  String _loadedScope = '';
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    _newCategoryController.dispose();
    _inlineEditController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );
    final representedName = (widget.activeRepresentedCompanyName ?? '').trim();
    final scopeLabel = representedName.isEmpty
        ? widget.activeTenant.tenantName
        : representedName;

    return StreamBuilder<List<ProductCategoryTaxonomyItem>>(
      stream: _service.watchRepresentedProductTaxonomy(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: widget.selectedRepresentedCompanyId,
      ),
      builder: (context, snapshot) {
        final scopeKey = _scopeKey();
        final incoming = snapshot.data ?? const <ProductCategoryTaxonomyItem>[];
        if (_loadedScope != scopeKey || !_dirty) {
          _draftTaxonomy = incoming
              .map(
                (item) => ProductCategoryTaxonomyItem(
                  name: item.name,
                  subcategories: [...item.subcategories],
                ),
              )
              .toList(growable: false);
          _selectedCategory = _draftTaxonomy.isNotEmpty
              ? _draftTaxonomy.first.name
              : null;
          _expandedCategories
            ..clear()
            ..addAll(_draftTaxonomy.map((item) => item.name));
          _loadedScope = scopeKey;
          _dirty = false;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Categorias',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Classificacao usada em filtros, catalogo e regras para $scopeLabel.',
                ),
                const SizedBox(height: 16),
                Text(
                  'Adicionar nova categoria',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 320,
                      child: TextField(
                        controller: _newCategoryController,
                        enabled: canEditSettings && !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Nome',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) {
                          if (!canEditSettings) {
                            return;
                          }
                          _addRootCategory();
                        },
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: canEditSettings && !_saving
                          ? _addRootCategory
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar categoria pai'),
                    ),
                  ],
                ),
                if (!canEditSettings) ...[
                  const SizedBox(height: 10),
                  _ownerOnlyReadOnlyNotice(
                    context,
                    message: 'Categorias ficam em modo somente leitura para este perfil. Apenas o owner pode alterar.',
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Arvore de categorias',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _draftTaxonomy.isEmpty
                          ? null
                          : () {
                              setState(() {
                                _expandedCategories
                                  ..clear()
                                  ..addAll(
                                    _draftTaxonomy.map((item) => item.name),
                                  );
                              });
                            },
                      icon: const Icon(Icons.unfold_more),
                      label: const Text('Expandir tudo'),
                    ),
                    TextButton.icon(
                      onPressed: _draftTaxonomy.isEmpty
                          ? null
                          : () {
                              setState(() {
                                _expandedCategories.clear();
                              });
                            },
                      icon: const Icon(Icons.unfold_less),
                      label: const Text('Recolher tudo'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_draftTaxonomy.isEmpty)
                  const Text('Nenhuma categoria criada ainda.')
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _draftTaxonomy
                        .map(
                          (item) => _buildCategoryTreeNode(
                            context,
                            item,
                            canEditSettings,
                          ),
                        )
                        .toList(growable: false),
                  ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: canEditSettings && !_saving && _dirty
                        ? _save
                        : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Salvando...' : 'Salvar categorias'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _addRootCategory() {
    final value = _newCategoryController.text.trim();
    if (value.isEmpty) {
      return;
    }

    final exists = _draftTaxonomy.any(
      (item) => item.name.toLowerCase() == value.toLowerCase(),
    );
    if (exists) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Categoria ja existente.')));
      return;
    }

    setState(() {
      _draftTaxonomy = [
        ..._draftTaxonomy,
        ProductCategoryTaxonomyItem(name: value, subcategories: const []),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _selectedCategory = value;
      _expandedCategories.add(value);
      _dirty = true;
      _newCategoryController.clear();
    });
  }

  Future<void> _promptAddSubcategory(String categoryName) async {
    final nameController = TextEditingController();
    String? validationMessage;

    final subcategoryName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Nova subcategoria em $categoryName'),
              content: SizedBox(
                width: 320,
                child: TextField(
                  controller: nameController,
                  autofocus: true,
                  enabled: true,
                  decoration: InputDecoration(
                    labelText: 'Nome da subcategoria',
                    errorText: validationMessage,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    final value = nameController.text.trim();
                    if (value.isEmpty) {
                      setDialogState(() {
                        validationMessage = 'Informe o nome da subcategoria.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(value);
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final value = nameController.text.trim();
                    if (value.isEmpty) {
                      setDialogState(() {
                        validationMessage = 'Informe o nome da subcategoria.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(value);
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();

    if (subcategoryName == null || subcategoryName.trim().isEmpty) {
      return;
    }

    _addSubcategoryToCategory(
      categoryName: categoryName,
      subcategoryName: subcategoryName.trim(),
    );
  }

  void _addSubcategoryToCategory({
    required String categoryName,
    required String subcategoryName,
  }) {
    final categoryIndex = _draftTaxonomy.indexWhere(
      (item) => item.name == categoryName,
    );
    if (categoryIndex < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Categoria pai nao encontrada.')),
      );
      return;
    }

    final category = _draftTaxonomy[categoryIndex];
    final existsAsSubcategory = category.subcategories.any(
      (item) => item.toLowerCase() == subcategoryName.toLowerCase(),
    );
    if (existsAsSubcategory) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subcategoria ja existente.')),
      );
      return;
    }

    final nextSubcategories = [...category.subcategories, subcategoryName]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final nextTaxonomy = [..._draftTaxonomy];
    nextTaxonomy[categoryIndex] = ProductCategoryTaxonomyItem(
      name: category.name,
      subcategories: nextSubcategories,
    );

    setState(() {
      _draftTaxonomy = nextTaxonomy;
      _selectedCategory = category.name;
      _expandedCategories.add(category.name);
      _dirty = true;
    });
  }

  void _startRenameCategory(String categoryName) {
    setState(() {
      _editingCategoryName = categoryName;
      _editingSubcategoryCategoryName = null;
      _editingSubcategoryName = null;
      _inlineEditController.text = categoryName;
      _expandedCategories.add(categoryName);
    });
  }

  void _startRenameSubcategory({
    required String categoryName,
    required String subcategoryName,
  }) {
    setState(() {
      _editingCategoryName = null;
      _editingSubcategoryCategoryName = categoryName;
      _editingSubcategoryName = subcategoryName;
      _inlineEditController.text = subcategoryName;
      _expandedCategories.add(categoryName);
    });
  }

  void _cancelInlineRename() {
    setState(() {
      _editingCategoryName = null;
      _editingSubcategoryCategoryName = null;
      _editingSubcategoryName = null;
      _inlineEditController.clear();
    });
  }

  void _commitInlineRename() {
    final value = _inlineEditController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe um nome valido.')));
      return;
    }

    final editingCategory = _editingCategoryName;
    if (editingCategory != null) {
      final existsCategory = _draftTaxonomy.any(
        (item) =>
            item.name.toLowerCase() == value.toLowerCase() &&
            item.name != editingCategory,
      );
      if (existsCategory) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Categoria ja existente.')),
        );
        return;
      }

      final categoryIndex = _draftTaxonomy.indexWhere(
        (item) => item.name == editingCategory,
      );
      if (categoryIndex < 0) {
        _cancelInlineRename();
        return;
      }

      final currentCategory = _draftTaxonomy[categoryIndex];
      final nextTaxonomy = [..._draftTaxonomy];
      nextTaxonomy[categoryIndex] = ProductCategoryTaxonomyItem(
        name: value,
        subcategories: [...currentCategory.subcategories],
      );
      nextTaxonomy.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      setState(() {
        _draftTaxonomy = nextTaxonomy;
        if (_selectedCategory == editingCategory) {
          _selectedCategory = value;
        }
        if (_expandedCategories.remove(editingCategory)) {
          _expandedCategories.add(value);
        }
        _editingCategoryName = null;
        _editingSubcategoryCategoryName = null;
        _editingSubcategoryName = null;
        _inlineEditController.clear();
        _dirty = true;
      });
      return;
    }

    final editingSubcategoryCategory = _editingSubcategoryCategoryName;
    final editingSubcategory = _editingSubcategoryName;
    if (editingSubcategoryCategory == null || editingSubcategory == null) {
      return;
    }

    final categoryIndex = _draftTaxonomy.indexWhere(
      (item) => item.name == editingSubcategoryCategory,
    );
    if (categoryIndex < 0) {
      _cancelInlineRename();
      return;
    }

    final currentCategory = _draftTaxonomy[categoryIndex];
    final existsSubcategory = currentCategory.subcategories.any(
      (item) =>
          item.toLowerCase() == value.toLowerCase() &&
          item != editingSubcategory,
    );
    if (existsSubcategory) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subcategoria ja existente.')),
      );
      return;
    }

    final nextSubcategories =
        currentCategory.subcategories
            .map((item) => item == editingSubcategory ? value : item)
            .toList(growable: false)
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final nextTaxonomy = [..._draftTaxonomy];
    nextTaxonomy[categoryIndex] = ProductCategoryTaxonomyItem(
      name: currentCategory.name,
      subcategories: nextSubcategories,
    );

    setState(() {
      _draftTaxonomy = nextTaxonomy;
      _editingCategoryName = null;
      _editingSubcategoryCategoryName = null;
      _editingSubcategoryName = null;
      _inlineEditController.clear();
      _dirty = true;
    });
  }

  Widget _buildCategoryTreeNode(
    BuildContext context,
    ProductCategoryTaxonomyItem item,
    bool canEditSettings,
  ) {
    final isExpanded = _expandedCategories.contains(item.name);
    final isSelected = item.name == _selectedCategory;
    final isEditingCategory = _editingCategoryName == item.name;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _selectedCategory = item.name;
                if (item.subcategories.isNotEmpty) {
                  if (isExpanded) {
                    _expandedCategories.remove(item.name);
                  } else {
                    _expandedCategories.add(item.name);
                  }
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    item.subcategories.isEmpty
                        ? Icons.label_outline
                        : (isExpanded
                              ? Icons.expand_more
                              : Icons.chevron_right),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: isEditingCategory
                        ? TextField(
                            controller: _inlineEditController,
                            autofocus: true,
                            enabled: canEditSettings && !_saving,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _commitInlineRename(),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                          )
                        : Text(
                            item.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                  ),
                  Text(
                    '${item.subcategories.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                  if (isEditingCategory) ...[
                    IconButton(
                      tooltip: 'Salvar nome',
                      onPressed: canEditSettings && !_saving
                          ? _commitInlineRename
                          : null,
                      icon: const Icon(Icons.check, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Cancelar edicao',
                      onPressed: canEditSettings && !_saving
                          ? _cancelInlineRename
                          : null,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: 'Renomear categoria',
                      onPressed: canEditSettings && !_saving
                          ? () => _startRenameCategory(item.name)
                          : null,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Adicionar subcategoria',
                      onPressed: canEditSettings && !_saving
                          ? () => _promptAddSubcategory(item.name)
                          : null,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Excluir categoria',
                      onPressed: canEditSettings && !_saving
                          ? () => _removeCategory(item.name)
                          : null,
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isExpanded && item.subcategories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(34, 0, 10, 8),
              child: Column(
                children: item.subcategories
                    .map((sub) {
                      final isEditingSubcategory =
                          _editingSubcategoryCategoryName == item.name &&
                          _editingSubcategoryName == sub;
                      return ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(
                          horizontal: -2,
                          vertical: -3,
                        ),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.subdirectory_arrow_right,
                          size: 16,
                        ),
                        title: isEditingSubcategory
                            ? TextField(
                                controller: _inlineEditController,
                                autofocus: true,
                                enabled: canEditSettings && !_saving,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _commitInlineRename(),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                ),
                              )
                            : Text(sub),
                        trailing: isEditingSubcategory
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Salvar nome',
                                    onPressed: canEditSettings && !_saving
                                        ? _commitInlineRename
                                        : null,
                                    icon: const Icon(Icons.check, size: 16),
                                  ),
                                  IconButton(
                                    tooltip: 'Cancelar edicao',
                                    onPressed: canEditSettings && !_saving
                                        ? _cancelInlineRename
                                        : null,
                                    icon: const Icon(Icons.close, size: 16),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Renomear subcategoria',
                                    onPressed: canEditSettings && !_saving
                                        ? () => _startRenameSubcategory(
                                            categoryName: item.name,
                                            subcategoryName: sub,
                                          )
                                        : null,
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Excluir subcategoria',
                                    onPressed: canEditSettings && !_saving
                                        ? () => _removeSubcategory(
                                            categoryName: item.name,
                                            subcategoryName: sub,
                                          )
                                        : null,
                                    icon: const Icon(Icons.close, size: 16),
                                  ),
                                ],
                              ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }

  void _removeCategory(String category) {
    setState(() {
      _draftTaxonomy = _draftTaxonomy
          .where((item) => item.name != category)
          .toList(growable: false);
      _expandedCategories.remove(category);
      if (_editingCategoryName == category ||
          _editingSubcategoryCategoryName == category) {
        _editingCategoryName = null;
        _editingSubcategoryCategoryName = null;
        _editingSubcategoryName = null;
        _inlineEditController.clear();
      }
      if (_selectedCategory == category) {
        _selectedCategory = _draftTaxonomy.isNotEmpty
            ? _draftTaxonomy.first.name
            : null;
      }
      _dirty = true;
    });
  }

  void _removeSubcategory({
    required String categoryName,
    required String subcategoryName,
  }) {
    final categoryIndex = _draftTaxonomy.indexWhere(
      (item) => item.name == categoryName,
    );
    if (categoryIndex < 0) {
      return;
    }

    final category = _draftTaxonomy[categoryIndex];
    final nextSubcategories = category.subcategories
        .where((item) => item != subcategoryName)
        .toList(growable: false);

    final nextTaxonomy = [..._draftTaxonomy];
    nextTaxonomy[categoryIndex] = ProductCategoryTaxonomyItem(
      name: category.name,
      subcategories: nextSubcategories,
    );

    setState(() {
      _draftTaxonomy = nextTaxonomy;
      if (_editingSubcategoryCategoryName == categoryName &&
          _editingSubcategoryName == subcategoryName) {
        _editingSubcategoryCategoryName = null;
        _editingSubcategoryName = null;
        _inlineEditController.clear();
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });

    try {
      await _service.updateRepresentedProductTaxonomy(
        tenantId: widget.activeTenant.tenantId,
        representedCompanyId: widget.selectedRepresentedCompanyId,
        taxonomy: _draftTaxonomy,
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Categorias salvas.')));
      setState(() {
        _dirty = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar categorias: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _scopeKey() {
    final raw = (widget.selectedRepresentedCompanyId ?? '').trim();
    return raw.isEmpty ? 'tenant_default' : raw;
  }
}
