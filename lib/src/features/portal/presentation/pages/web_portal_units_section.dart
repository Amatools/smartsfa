part of 'web_portal_page.dart';

class _UnitsSection extends StatefulWidget {
  const _UnitsSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  State<_UnitsSection> createState() => _UnitsSectionState();
}

class _UnitsSectionState extends State<_UnitsSection> {
  final ProductUnitCatalogService _service = ProductUnitCatalogService(
    FirebaseFirestore.instance,
  );
  final TextEditingController _newMeasureController = TextEditingController();
  final TextEditingController _newMeasureShortCodeController =
      TextEditingController();
  final TextEditingController _newStandardController = TextEditingController();
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _primeDefaultUnits();
  }

  @override
  void dispose() {
    _newMeasureController.dispose();
    _newMeasureShortCodeController.dispose();
    _newStandardController.dispose();
    super.dispose();
  }

  void _primeDefaultUnits() {
    Future<void>(() async {
      try {
        await _service.ensureDefaultUnits(
          tenantId: widget.activeTenant.tenantId,
          type: ProductUnitCatalogType.measure,
          defaultValues: ProductEditorDefaults.bitolaUnits,
          defaultShortCodes: ProductEditorDefaults.bitolaUnitShortCodes,
        );
        await _service.ensureDefaultUnits(
          tenantId: widget.activeTenant.tenantId,
          type: ProductUnitCatalogType.standard,
          defaultValues: ProductEditorDefaults.standardUnits,
        );
      } catch (_) {
        // Best effort seeding for first use.
      }
    });
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unidades', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Gerencie os cadastros usados nos produtos de $scopeLabel. Somente unidades cadastradas aparecem no editor.',
            ),
            if (!canEditSettings) ...[
              const SizedBox(height: 10),
              _ownerOnlyReadOnlyNotice(
                context,
                message: 'Unidades ficam em modo somente leitura para este perfil. Apenas o owner pode alterar.',
              ),
            ],
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                final twoColumns = maxWidth >= 960;
                final panelWidth = twoColumns ? (maxWidth - 12) / 2 : maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: panelWidth,
                      child: _buildCatalogPanel(
                        type: ProductUnitCatalogType.measure,
                        title: 'Unidade de medida',
                        hint: 'Ex.: milimetro, litro',
                        inputController: _newMeasureController,
                        shortCodeController: _newMeasureShortCodeController,
                        canEditSettings: canEditSettings,
                      ),
                    ),
                    SizedBox(
                      width: panelWidth,
                      child: _buildCatalogPanel(
                        type: ProductUnitCatalogType.standard,
                        title: 'Unidade padrão',
                        hint: 'Ex.: Unidade, Kit',
                        inputController: _newStandardController,
                        shortCodeController: null,
                        canEditSettings: canEditSettings,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogPanel({
    required ProductUnitCatalogType type,
    required String title,
    required String hint,
    required TextEditingController inputController,
    required TextEditingController? shortCodeController,
    required bool canEditSettings,
  }) {
    final requiresShortCode = type == ProductUnitCatalogType.measure;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: inputController,
                  enabled: canEditSettings && !_working,
                  decoration: InputDecoration(
                    labelText: 'Nova unidade',
                    hintText: hint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) {
                    if (!canEditSettings || _working) {
                      return;
                    }
                    _addUnit(
                      type: type,
                      inputController: inputController,
                      shortCodeController: shortCodeController,
                    );
                  },
                ),
              ),
              if (requiresShortCode) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: shortCodeController,
                    enabled: canEditSettings && !_working,
                    textCapitalization: TextCapitalization.none,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Sigla',
                      hintText: 'mm',
                      counterText: '',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) {
                      if (!canEditSettings || _working) {
                        return;
                      }
                      _addUnit(
                        type: type,
                        inputController: inputController,
                        shortCodeController: shortCodeController,
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: canEditSettings && !_working
                    ? () => _addUnit(
                        type: type,
                        inputController: inputController,
                        shortCodeController: shortCodeController,
                      )
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<ProductUnitCatalogEntry>>(
            stream: _service.watchUnits(
              tenantId: widget.activeTenant.tenantId,
              type: type,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Falha ao carregar unidades: ${_extractErrorMessage(snapshot.error!)}',
                  ),
                );
              }

              final units = snapshot.data ?? const <ProductUnitCatalogEntry>[];
              if (snapshot.connectionState == ConnectionState.waiting &&
                  units.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (units.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Nenhuma unidade cadastrada.'),
                );
              }

              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: units.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = units[index];
                    final hasShortCode = entry.shortCode.trim().isNotEmpty;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        hasShortCode && requiresShortCode
                            ? '${entry.name} (${entry.shortCode})'
                            : entry.name,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Editar',
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: canEditSettings && !_working
                                ? () => _editUnit(type: type, entry: entry)
                                : null,
                          ),
                          IconButton(
                            tooltip: 'Excluir',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: canEditSettings && !_working
                                ? () => _deleteUnit(type: type, entry: entry)
                                : null,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addUnit({
    required ProductUnitCatalogType type,
    required TextEditingController inputController,
    required TextEditingController? shortCodeController,
  }) async {
    final value = inputController.text.trim();
    final shortCode = (shortCodeController?.text ?? '').trim();
    if (value.isEmpty) {
      return;
    }

    if (type == ProductUnitCatalogType.measure && shortCode.isEmpty) {
      _showMessage('Informe a sigla com ate 4 letras.');
      return;
    }

    await _runCatalogAction(() async {
      await _service.createUnit(
        tenantId: widget.activeTenant.tenantId,
        type: type,
        name: value,
        shortCode: type == ProductUnitCatalogType.measure ? shortCode : null,
      );
      inputController.clear();
      shortCodeController?.clear();
      _showMessage('Unidade cadastrada.');
    });
  }

  Future<void> _editUnit({
    required ProductUnitCatalogType type,
    required ProductUnitCatalogEntry entry,
  }) async {
    final nextUnit = await _promptUnitDraft(
      type: type,
      title: 'Editar unidade',
      initialName: entry.name,
      initialShortCode: entry.shortCode,
    );
    if (nextUnit == null) {
      return;
    }

    await _runCatalogAction(() async {
      await _service.updateUnit(
        tenantId: widget.activeTenant.tenantId,
        type: type,
        id: entry.id,
        name: nextUnit.name,
        shortCode: nextUnit.shortCode,
      );
      _showMessage('Unidade atualizada.');
    });
  }

  Future<void> _deleteUnit({
    required ProductUnitCatalogType type,
    required ProductUnitCatalogEntry entry,
  }) async {
    final confirmed = await _confirmDelete(entry.name);
    if (!confirmed) {
      return;
    }

    await _runCatalogAction(() async {
      await _service.deleteUnit(
        tenantId: widget.activeTenant.tenantId,
        type: type,
        id: entry.id,
      );
      _showMessage('Unidade removida.');
    });
  }

  Future<void> _runCatalogAction(Future<void> Function() action) async {
    setState(() {
      _working = true;
    });

    try {
      await action();
    } catch (error) {
      _showMessage('Falha ao salvar unidade: ${_extractErrorMessage(error)}');
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  String _extractErrorMessage(Object error) {
    final text = error.toString().trim();
    const prefix = 'Bad state: ';
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length);
    }
    return text;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmDelete(String unitName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir unidade'),
          content: Text('Deseja excluir "$unitName"?'),
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

    return result == true;
  }

  Future<_UnitDraft?> _promptUnitDraft({
    required ProductUnitCatalogType type,
    required String title,
    required String initialName,
    required String initialShortCode,
  }) async {
    final nameController = TextEditingController(text: initialName);
    final shortCodeController = TextEditingController(text: initialShortCode);
    final requiresShortCode = type == ProductUnitCatalogType.measure;

    final value = await showDialog<_UnitDraft>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nome da unidade',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (requiresShortCode) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: shortCodeController,
                    textCapitalization: TextCapitalization.none,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Sigla (ate 4 letras)',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      final normalizedName = nameController.text.trim();
                      final normalizedShortCode = shortCodeController.text
                          .trim();
                      if (normalizedName.isEmpty) {
                        return;
                      }
                      if (requiresShortCode && normalizedShortCode.isEmpty) {
                        return;
                      }
                      Navigator.of(dialogContext).pop(
                        _UnitDraft(
                          name: normalizedName,
                          shortCode: normalizedShortCode,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final normalizedName = nameController.text.trim();
                final normalizedShortCode = shortCodeController.text.trim();
                if (normalizedName.isEmpty) {
                  return;
                }
                if (requiresShortCode && normalizedShortCode.isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop(
                  _UnitDraft(
                    name: normalizedName,
                    shortCode: normalizedShortCode,
                  ),
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
    nameController.dispose();
    shortCodeController.dispose();
    return value;
  }
}

class _UnitDraft {
  const _UnitDraft({required this.name, required this.shortCode});

  final String name;
  final String shortCode;
}
