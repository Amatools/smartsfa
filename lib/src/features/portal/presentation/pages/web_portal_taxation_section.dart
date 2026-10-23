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

class _TaxRuleGroupsSection extends StatefulWidget {
  const _TaxRuleGroupsSection({
    required this.activeTenant,
    this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_TaxRuleGroupsSection> createState() => _TaxRuleGroupsSectionState();
}

class _TaxRuleGroupsSectionState extends State<_TaxRuleGroupsSection> {
  final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('tax_rule_groups');

  bool _working = false;

  String get _selectedRepresentedCompanyId {
    return (widget.selectedRepresentedCompanyId ?? '').trim();
  }

  bool _hasRepresentedScope() {
    return _selectedRepresentedCompanyId.isNotEmpty;
  }

  bool _matchesSelectedScope(_TaxRuleGroupEntity entity) {
    final selected = _selectedRepresentedCompanyId;
    if (selected.isEmpty) {
      return true;
    }
    final scope = (entity.representedCompanyId ?? '').trim();
    return scope.isEmpty || scope == selected;
  }

  List<_TaxRuleGroupEntity> _sortForDisplay(List<_TaxRuleGroupEntity> groups) {
    final selected = _selectedRepresentedCompanyId;
    final sorted = List<_TaxRuleGroupEntity>.from(groups);
    sorted.sort((a, b) {
      final aScope = (a.representedCompanyId ?? '').trim();
      final bScope = (b.representedCompanyId ?? '').trim();
      final aIsSelected = selected.isNotEmpty && aScope == selected;
      final bIsSelected = selected.isNotEmpty && bScope == selected;
      if (aIsSelected != bIsSelected) {
        return aIsSelected ? -1 : 1;
      }
      final priorityCompare = b.priority.compareTo(a.priority);
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  Stream<List<_TaxRuleGroupEntity>> _watchGroups() {
    return _collection
        .where('tenantId', isEqualTo: widget.activeTenant.tenantId)
        .snapshots()
        .map((snapshot) {
          final groups = <_TaxRuleGroupEntity>[];
          for (final doc in snapshot.docs) {
            final entity = _TaxRuleGroupEntity.fromDoc(doc.id, doc.data());
            if (entity == null) {
              continue;
            }
            groups.add(entity);
          }
          final scoped = groups
              .where(_matchesSelectedScope)
              .toList(growable: false);
          return _sortForDisplay(scoped);
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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Grupos tributários',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cadastre grupos para classificar produtos e simplificar o match da matriz tributária para $scopeLabel.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: canEditSettings && !_working
                          ? _downloadTemplate
                          : null,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Baixar modelo XLSX'),
                    ),
                    OutlinedButton.icon(
                      onPressed: canEditSettings && !_working
                          ? _openImportSheet
                          : null,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Importar planilha'),
                    ),
                    OutlinedButton.icon(
                      onPressed: canEditSettings && !_working
                          ? _openErpSyncHint
                          : null,
                      icon: const Icon(Icons.sync_alt_outlined),
                      label: const Text('Integração ERP'),
                    ),
                    FilledButton.icon(
                      onPressed: canEditSettings && !_working
                          ? () => _openGroupDialog()
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Novo grupo'),
                    ),
                  ],
                ),
              ],
            ),
            if (!canEditSettings) ...[
              const SizedBox(height: 10),
              _ownerOnlyReadOnlyNotice(
                context,
                message: 'Grupos tributários ficam em modo somente leitura para este perfil. Apenas o owner pode alterar.',
              ),
            ],
            const SizedBox(height: 14),
            StreamBuilder<List<_TaxRuleGroupEntity>>(
              stream: _watchGroups(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Falha ao carregar grupos tributários: ${_extractErrorMessage(snapshot.error!)}',
                  );
                }

                final groups = snapshot.data ?? const <_TaxRuleGroupEntity>[];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    groups.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (groups.isEmpty) {
                  return const Text(
                    'Nenhum grupo tributário cadastrado neste contexto. Use "Novo grupo", "Importar planilha" ou "Integração ERP" para começar.',
                  );
                }

                final activeCount = groups
                    .where((item) => item.isActive)
                    .length;
                final inactiveCount = groups.length - activeCount;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statChip(context, 'Total: ${groups.length}'),
                        _statChip(context, 'Ativos: $activeCount'),
                        _statChip(context, 'Inativos: $inactiveCount'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: groups.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        final subtitleParts = <String>[
                          if ((group.externalCode ?? '').trim().isNotEmpty)
                            'Código externo: ${group.externalCode!.trim()}',
                          if ((group.erpProvider ?? '').trim().isNotEmpty)
                            'ERP: ${group.erpProvider!.trim()}',
                          'Origem: ${group.sourceLabel}',
                          'Prioridade: ${group.priority}',
                        ];

                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              14,
                              10,
                              8,
                              10,
                            ),
                            title: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _statChip(context, group.name),
                                _statChip(
                                  context,
                                  group.isActive ? 'Ativo' : 'Inativo',
                                ),
                                _statChip(context, group.scopeLabel),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                [
                                  if ((group.description ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    group.description!.trim(),
                                  subtitleParts.join(' | '),
                                ].join('\n'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Editar grupo',
                                  onPressed: canEditSettings && !_working
                                      ? () => _openGroupDialog(existing: group)
                                      : null,
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Excluir grupo',
                                  onPressed: canEditSettings && !_working
                                      ? () => _deleteGroup(group)
                                      : null,
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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

  Widget _statChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.6),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }

  Future<void> _openErpSyncHint() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Integração ERP de grupos tributários'),
          content: const Text(
            'Nesta fase a tela já está preparada para integração. No próximo ciclo conectaremos os conectores (Sankhya, TOTVS e outros ERPs) para preenchimento automático do catálogo de grupos tributários.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Entendi'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadTemplate() async {
    final bytes = TabularSpreadsheetService.buildXlsxWithSheets(
      sheets: <TabularSpreadsheetSheet>[
        const TabularSpreadsheetSheet(
          sheetName: 'GruposTributarios',
          headers: <String>[
            'id',
            'nome',
            'descricao',
            'status',
            'codigoExterno',
            'erpProvider',
            'prioridade',
            'escopo',
          ],
          rows: <List<String>>[
            <String>[
              '',
              'Grupo exemplo',
              'Grupo para produtos de revenda padrão',
              'active',
              'GRP-001',
              'sankhya',
              '100',
              'representada',
            ],
          ],
        ),
        const TabularSpreadsheetSheet(
          sheetName: 'Instrucoes',
          headers: <String>['Campo', 'Obrigatório', 'Regra'],
          rows: <List<String>>[
            <String>['nome', 'Sim', 'Nome do grupo tributário.'],
            <String>[
              'descricao',
              'Não',
              'Descrição para orientar o time comercial/fiscal.',
            ],
            <String>[
              'status',
              'Não',
              'Use active/inactive. Vazio assume active.',
            ],
            <String>[
              'codigoExterno',
              'Não',
              'Código usado no ERP externo (quando existir).',
            ],
            <String>[
              'erpProvider',
              'Não',
              'Ex.: sankhya, totvs, sap. Texto livre.',
            ],
            <String>[
              'prioridade',
              'Não',
              'Inteiro. Maior número = maior prioridade visual/lógica.',
            ],
            <String>[
              'escopo',
              'Não',
              'Use global ou representada. Se vazio, assume representada quando houver representada ativa, senão global.',
            ],
          ],
        ),
      ],
    );

    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await downloadFileBytes(
      bytes: bytes,
      fileName: 'modelo_grupos_tributarios_$stamp.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> _openImportSheet() async {
    PlatformFile? selectedFile;
    _TaxGroupImportValidation? validation;
    var importing = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickFile() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const <String>['xlsx', 'xls', 'csv'],
                allowMultiple: false,
                withData: true,
              );
              final file = result?.files.isNotEmpty == true
                  ? result!.files.first
                  : null;
              if (file == null) {
                return;
              }

              setSheetState(() {
                selectedFile = file;
                validation = null;
              });
            }

            Future<void> validate() async {
              final file = selectedFile;
              if (file == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Selecione uma planilha primeiro.'),
                  ),
                );
                return;
              }

              final report = _validateImportFile(file);
              setSheetState(() {
                validation = report;
              });
            }

            Future<void> importFile() async {
              final file = selectedFile;
              if (file == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Selecione uma planilha para importar.'),
                  ),
                );
                return;
              }

              final report = validation ?? _validateImportFile(file);
              if (!report.ok) {
                setSheetState(() {
                  validation = report;
                });
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(report.message)));
                return;
              }

              setSheetState(() {
                importing = true;
              });
              setState(() {
                _working = true;
              });

              try {
                final result = await _importRows(report.rows);
                if (!context.mounted) {
                  return;
                }
                Navigator.of(sheetContext).pop();
                _showMessage(
                  'Importação concluída: ${result.imported} grupo(s) salvo(s), ${result.skipped} linha(s) ignorada(s).',
                );
              } catch (error) {
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Falha ao importar grupos: ${_extractErrorMessage(error)}',
                    ),
                  ),
                );
              } finally {
                if (context.mounted) {
                  setSheetState(() {
                    importing = false;
                  });
                }
                if (mounted) {
                  setState(() {
                    _working = false;
                  });
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Importar grupos tributários',
                      style: Theme.of(sheetContext).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use o modelo XLSX para manter cabeçalhos e formatos padronizados.',
                    ),
                    const SizedBox(height: 12),
                    if (selectedFile != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(selectedFile!.name),
                        subtitle: Text(
                          '${(selectedFile!.size / 1024).toStringAsFixed(1)} KB',
                        ),
                      ),
                    if (validation != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          validation!.ok
                              ? Icons.verified_outlined
                              : Icons.error_outline,
                          color: validation!.ok ? Colors.green : Colors.red,
                        ),
                        title: Text(
                          validation!.ok
                              ? 'Validação concluída'
                              : 'Validação com erro',
                        ),
                        subtitle: Text(validation!.message),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: importing ? null : pickFile,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Selecionar planilha'),
                        ),
                        OutlinedButton.icon(
                          onPressed: importing ? null : validate,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('Validar estrutura'),
                        ),
                        FilledButton.icon(
                          onPressed: importing ? null : importFile,
                          icon: const Icon(
                            Icons.playlist_add_check_circle_outlined,
                          ),
                          label: Text(
                            importing ? 'Importando...' : 'Importar agora',
                          ),
                        ),
                        TextButton(
                          onPressed: importing
                              ? null
                              : () => Navigator.of(sheetContext).pop(),
                          child: const Text('Fechar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  _TaxGroupImportValidation _validateImportFile(PlatformFile file) {
    final parsed = TabularSpreadsheetService.parseFile(file);
    if (!parsed.ok) {
      return _TaxGroupImportValidation(
        ok: false,
        message: parsed.message,
        rows: const <Map<String, String>>[],
      );
    }

    final headers = parsed.headers;
    final hasName =
        headers.contains('nome') ||
        headers.contains('name') ||
        headers.contains('grupo');
    if (!hasName) {
      return const _TaxGroupImportValidation(
        ok: false,
        message: 'Cabeçalho inválido. Campo obrigatório: nome.',
        rows: <Map<String, String>>[],
      );
    }

    if (parsed.rows.isEmpty) {
      return const _TaxGroupImportValidation(
        ok: false,
        message: 'Planilha sem linhas válidas para importação.',
        rows: <Map<String, String>>[],
      );
    }

    return _TaxGroupImportValidation(
      ok: true,
      message: 'Arquivo válido com ${parsed.rows.length} linha(s).',
      rows: parsed.rows,
    );
  }

  Future<_TaxGroupImportResult> _importRows(
    List<Map<String, String>> rows,
  ) async {
    final snapshot = await _collection
        .where('tenantId', isEqualTo: widget.activeTenant.tenantId)
        .get();
    final existing = <String, _TaxRuleGroupEntity>{};
    final existingByFingerprint = <String, _TaxRuleGroupEntity>{};
    for (final doc in snapshot.docs) {
      final parsed = _TaxRuleGroupEntity.fromDoc(doc.id, doc.data());
      if (parsed == null) {
        continue;
      }
      existing[parsed.id] = parsed;
      existingByFingerprint[_fingerprint(
            representedCompanyId: parsed.representedCompanyId,
            normalizedName: parsed.normalizedName,
          )] =
          parsed;
    }

    var imported = 0;
    var skipped = 0;
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final name = _readCell(row, const <String>['nome', 'name', 'grupo']);
      final normalizedName = name.trim().toLowerCase();
      if (normalizedName.isEmpty) {
        skipped++;
        continue;
      }

      final sourceId = _readCell(row, const <String>['id']);
      final scope = _readCell(row, const <String>['escopo', 'scope']);
      final representedCompanyId = _resolveRepresentedScope(scope);
      final doc = sourceId.trim().isEmpty ? null : existing[sourceId.trim()];
      final scopeFingerprint = _fingerprint(
        representedCompanyId: representedCompanyId,
        normalizedName: normalizedName,
      );
      final scopedExisting = existingByFingerprint[scopeFingerprint];

      final generatedId = FirebaseFirestore.instance
          .collection('tax_rule_groups')
          .doc()
          .id;
      final id =
          doc?.id ??
          scopedExisting?.id ??
          (sourceId.trim().isNotEmpty ? sourceId.trim() : generatedId);

      final status = _normalizeStatus(_readCell(row, const <String>['status']));
      final priorityRaw = _readCell(row, const <String>[
        'prioridade',
        'prioridadeordem',
        'priority',
      ]);
      final priority = int.tryParse(priorityRaw.trim()) ?? 0;

      final payload = <String, Object?>{
        'tenantId': widget.activeTenant.tenantId,
        'representedCompanyId': representedCompanyId,
        'name': name.trim(),
        'normalizedName': normalizedName,
        'description': _nullableString(
          _readCell(row, const <String>['descricao', 'description']),
        ),
        'status': status,
        'source': 'import',
        'externalCode': _nullableString(
          _readCell(row, const <String>['codigoexterno', 'externalcode']),
        ),
        'erpProvider': _nullableString(
          _readCell(row, const <String>['erpprovider', 'erp', 'provider']),
        ),
        'priority': priority,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final existingEntity = existing[id];
      if (existingEntity == null) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }

      await _collection.doc(id).set(payload, SetOptions(merge: true));
      imported++;
    }

    return _TaxGroupImportResult(imported: imported, skipped: skipped);
  }

  String _readCell(Map<String, String> row, List<String> aliases) {
    for (final alias in aliases) {
      final key = TabularSpreadsheetService.normalizeHeader(alias);
      final value = row[key]?.trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _fingerprint({
    required String? representedCompanyId,
    required String normalizedName,
  }) {
    final scope = (representedCompanyId ?? '').trim();
    return '$scope|$normalizedName';
  }

  String? _resolveRepresentedScope(String scopeRaw) {
    final scope = scopeRaw.trim().toLowerCase();
    if (scope == 'global' || scope == 'tenant') {
      return null;
    }
    final selected = _selectedRepresentedCompanyId;
    if (selected.isEmpty) {
      return null;
    }
    return selected;
  }

  Future<void> _openGroupDialog({_TaxRuleGroupEntity? existing}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    final externalCodeController = TextEditingController(
      text: existing?.externalCode ?? '',
    );
    final erpProviderController = TextEditingController(
      text: existing?.erpProvider ?? '',
    );
    final priorityController = TextEditingController(
      text: existing?.priority.toString() ?? '0',
    );
    var active = existing?.isActive ?? true;
    var globalScope = (existing?.representedCompanyId ?? '').trim().isEmpty;

    final draft = await showDialog<_TaxRuleGroupDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                existing == null
                    ? 'Novo grupo tributário'
                    : 'Editar grupo tributário',
              ),
              content: SizedBox(
                width: 580,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nome do grupo *',
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Nome obrigatório';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Descrição',
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: externalCodeController,
                                decoration: const InputDecoration(
                                  labelText: 'Código externo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: erpProviderController,
                                decoration: const InputDecoration(
                                  labelText: 'ERP provider',
                                  hintText: 'sankhya, totvs, sap...',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: priorityController,
                          decoration: const InputDecoration(
                            labelText: 'Prioridade (inteiro)',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9-]'),
                            ),
                          ],
                        ),
                        if (_hasRepresentedScope()) ...[
                          const SizedBox(height: 8),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: globalScope,
                            onChanged: (value) {
                              setDialogState(() {
                                globalScope = value;
                              });
                            },
                            title: const Text('Escopo global do tenant'),
                            subtitle: const Text(
                              'Quando desligado, o grupo fica vinculado à representada ativa.',
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: active,
                          onChanged: (value) {
                            setDialogState(() {
                              active = value;
                            });
                          },
                          title: const Text('Grupo ativo'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!(formKey.currentState?.validate() ?? true)) {
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _TaxRuleGroupDraft(
                        name: nameController.text.trim(),
                        description: descriptionController.text,
                        externalCode: externalCodeController.text,
                        erpProvider: erpProviderController.text,
                        priority:
                            int.tryParse(priorityController.text.trim()) ?? 0,
                        active: active,
                        globalScope: globalScope,
                      ),
                    );
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (draft == null) {
      return;
    }

    setState(() {
      _working = true;
    });
    try {
      final id =
          existing?.id ??
          FirebaseFirestore.instance.collection('tax_rule_groups').doc().id;
      final representedCompanyId = draft.globalScope
          ? null
          : _resolveRepresentedScope('representada');

      final payload = <String, Object?>{
        'tenantId': widget.activeTenant.tenantId,
        'representedCompanyId': representedCompanyId,
        'name': draft.name,
        'normalizedName': draft.name.toLowerCase(),
        'description': _nullableString(draft.description),
        'status': draft.active ? 'active' : 'inactive',
        'source': existing?.source ?? 'manual',
        'externalCode': _nullableString(draft.externalCode),
        'erpProvider': _nullableString(draft.erpProvider),
        'priority': draft.priority,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (existing == null) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }

      await _collection.doc(id).set(payload, SetOptions(merge: true));
      _showMessage(
        existing == null
            ? 'Grupo tributário criado com sucesso.'
            : 'Grupo tributário atualizado com sucesso.',
      );
    } catch (error) {
      _showMessage(
        'Falha ao salvar grupo tributário: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _deleteGroup(_TaxRuleGroupEntity entity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir grupo tributário'),
          content: Text('Deseja excluir o grupo "${entity.name}"?'),
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

    if (confirmed != true) {
      return;
    }

    setState(() {
      _working = true;
    });
    try {
      await _collection.doc(entity.id).delete();
      _showMessage('Grupo tributário removido.');
    } catch (error) {
      _showMessage(
        'Falha ao remover grupo tributário: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  String _normalizeStatus(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'inactive' ||
        normalized == 'inativo' ||
        normalized == 'desativado') {
      return 'inactive';
    }
    return 'active';
  }

  String? _nullableString(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
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
}

class _TaxRuleGroupEntity {
  const _TaxRuleGroupEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.normalizedName,
    required this.status,
    required this.source,
    required this.priority,
    this.representedCompanyId,
    this.description,
    this.externalCode,
    this.erpProvider,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String? representedCompanyId;
  final String name;
  final String normalizedName;
  final String status;
  final String source;
  final String? description;
  final String? externalCode;
  final String? erpProvider;
  final int priority;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status.trim().toLowerCase() == 'active';

  String get scopeLabel {
    return (representedCompanyId ?? '').trim().isEmpty
        ? 'Escopo: Global'
        : 'Escopo: Representada';
  }

  String get sourceLabel {
    switch (source.trim().toLowerCase()) {
      case 'import':
        return 'Importação';
      case 'erp_sync':
        return 'Integração ERP';
      default:
        return 'Manual';
    }
  }

  static _TaxRuleGroupEntity? fromDoc(String id, Map<String, dynamic> raw) {
    final name = (raw['name'] ?? raw['nome'] ?? '').toString().trim();
    if (name.isEmpty) {
      return null;
    }

    return _TaxRuleGroupEntity(
      id: id,
      tenantId: (raw['tenantId'] ?? '').toString().trim(),
      representedCompanyId:
          (raw['representedCompanyId'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['representedCompanyId'] ?? '').toString().trim(),
      name: name,
      normalizedName: (raw['normalizedName'] ?? name.toLowerCase())
          .toString()
          .trim()
          .toLowerCase(),
      status: (raw['status'] ?? 'active').toString().trim().toLowerCase(),
      source: (raw['source'] ?? 'manual').toString().trim().toLowerCase(),
      description: (raw['description'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['description'] ?? '').toString().trim(),
      externalCode: (raw['externalCode'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['externalCode'] ?? '').toString().trim(),
      erpProvider: (raw['erpProvider'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['erpProvider'] ?? '').toString().trim(),
      priority: _readPriority(raw['priority']),
      createdAt: _readDateTime(raw['createdAt']),
      updatedAt: _readDateTime(raw['updatedAt']),
    );
  }

  static int _readPriority(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }
}

class _TaxRuleGroupDraft {
  const _TaxRuleGroupDraft({
    required this.name,
    required this.description,
    required this.externalCode,
    required this.erpProvider,
    required this.priority,
    required this.active,
    required this.globalScope,
  });

  final String name;
  final String description;
  final String externalCode;
  final String erpProvider;
  final int priority;
  final bool active;
  final bool globalScope;
}

class _TaxGroupImportValidation {
  const _TaxGroupImportValidation({
    required this.ok,
    required this.message,
    required this.rows,
  });

  final bool ok;
  final String message;
  final List<Map<String, String>> rows;
}

class _TaxGroupImportResult {
  const _TaxGroupImportResult({required this.imported, required this.skipped});

  final int imported;
  final int skipped;
}

class _TaxOperationProfilesSection extends StatefulWidget {
  const _TaxOperationProfilesSection({
    required this.activeTenant,
    this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_TaxOperationProfilesSection> createState() =>
      _TaxOperationProfilesSectionState();
}

class _TaxOperationProfilesSectionState extends State<_TaxOperationProfilesSection> {
  final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('tax_operation_profiles');

  bool _working = false;
  bool _seedRequested = false;

  static const List<_NativeOperationProfileTemplate> _defaultProfiles = <
    _NativeOperationProfileTemplate
  >[
    _NativeOperationProfileTemplate(
      key: 'revenda_same_uf',
      name: 'Revenda - operação estadual (mesma UF)',
      description: 'Fluxo de revenda com origem e destino na mesma UF.',
      defaultPriority: 100,
      calculateIcmsSt: true,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'revenda_interstate',
      name: 'Revenda - operação interestadual (UF diferente)',
      description: 'Fluxo de revenda interestadual padrão.',
      defaultPriority: 95,
      calculateIcmsSt: true,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'uso_consumo_contribuinte_same_uf',
      name: 'Uso/consumo - contribuinte - operação estadual (mesma UF)',
      description: 'Uso e consumo para cliente contribuinte na mesma UF.',
      defaultPriority: 90,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: true,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'uso_consumo_contribuinte_interstate',
      name: 'Uso/consumo - contribuinte - operação interestadual (UF diferente)',
      description: 'Uso e consumo contribuinte em operação interestadual.',
      defaultPriority: 85,
      calculateIcmsSt: false,
      calculateDifal: true,
      includeIpiInIcmsBase: true,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'uso_consumo_nao_contribuinte_same_uf',
      name: 'Uso/consumo - não contribuinte - operação estadual (mesma UF)',
      description: 'Uso e consumo para não contribuinte na mesma UF.',
      defaultPriority: 80,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: true,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'uso_consumo_nao_contribuinte_interstate',
      name:
          'Uso/consumo - não contribuinte - operação interestadual (UF diferente)',
      description: 'Uso e consumo não contribuinte em operação interestadual.',
      defaultPriority: 75,
      calculateIcmsSt: false,
      calculateDifal: true,
      includeIpiInIcmsBase: true,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'industrializacao_same_uf',
      name: 'Industrialização - operação estadual (mesma UF)',
      description: 'Industrialização com origem e destino na mesma UF.',
      defaultPriority: 70,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'industrializacao_interstate',
      name: 'Industrialização - operação interestadual (UF diferente)',
      description: 'Industrialização em operação interestadual.',
      defaultPriority: 65,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'zfm_industrializacao',
      name: 'ZFM/SUFRAMA - Industrialização',
      description: 'Cenário ZFM para industrialização.',
      defaultPriority: 60,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: false,
      reduceIcmsForZfm: true,
    ),
    _NativeOperationProfileTemplate(
      key: 'zfm_comercializacao_revenda',
      name: 'ZFM/SUFRAMA - Comercialização/Revenda',
      description: 'Cenário ZFM para comercialização e revenda.',
      defaultPriority: 55,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: false,
      reduceIcmsForZfm: true,
    ),
  ];

  String get _selectedRepresentedCompanyId {
    return (widget.selectedRepresentedCompanyId ?? '').trim();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seedRequested) {
      return;
    }
    _seedRequested = true;
    Future<void>.microtask(_ensureDefaults);
  }

  Future<void> _ensureDefaults() async {
    try {
      final tenantId = widget.activeTenant.tenantId;
      final representedCompanyId = _resolveDefaultScope();

      final snapshot = await _collection
          .where('tenantId', isEqualTo: tenantId)
          .get();
      final existingFingerprints = <String>{};
      for (final doc in snapshot.docs) {
        final parsed = _TaxOperationProfileEntity.fromDoc(doc.id, doc.data());
        if (parsed == null) {
          continue;
        }
        existingFingerprints.add(
          _profileFingerprint(
            representedCompanyId: parsed.representedCompanyId,
            profileKey: parsed.profileKey,
          ),
        );
      }

      for (final template in _defaultProfiles) {
        final fingerprint = _profileFingerprint(
          representedCompanyId: representedCompanyId,
          profileKey: template.key,
        );
        if (existingFingerprints.contains(fingerprint)) {
          continue;
        }

        final id = FirebaseFirestore.instance
          .collection('tax_operation_profiles')
            .doc()
            .id;
        await _collection.doc(id).set({
          'tenantId': tenantId,
          'representedCompanyId': representedCompanyId,
          'profileKey': template.key,
          'name': template.name,
          'description': template.description,
          'status': 'active',
          'source': 'native_seed',
          'priority': template.defaultPriority,
          'calculateIcmsSt': template.calculateIcmsSt,
          'calculateDifal': template.calculateDifal,
          'includeIpiInIcmsBase': template.includeIpiInIcmsBase,
          'addIpiToTotal': template.addIpiToTotal,
          'reduceIcmsForZfm': template.reduceIcmsForZfm,
          'erpProvider': 'sankhya',
          'externalOperationCode': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(
        'Não foi possível pré-carregar os perfis nativos: ${_extractErrorMessage(error)}',
      );
    }
  }

  String? _resolveDefaultScope() {
    final selected = _selectedRepresentedCompanyId;
    if (selected.isEmpty) {
      return null;
    }
    return selected;
  }

  String _profileFingerprint({
    required String? representedCompanyId,
    required String profileKey,
  }) {
    final scope = (representedCompanyId ?? '').trim();
    return '$scope|$profileKey';
  }

  bool _matchesSelectedScope(_TaxOperationProfileEntity profile) {
    final selected = _selectedRepresentedCompanyId;
    if (selected.isEmpty) {
      return true;
    }
    final scope = (profile.representedCompanyId ?? '').trim();
    return scope.isEmpty || scope == selected;
  }

  List<_TaxOperationProfileEntity> _sortForDisplay(
    List<_TaxOperationProfileEntity> profiles,
  ) {
    final selected = _selectedRepresentedCompanyId;
    final sorted = List<_TaxOperationProfileEntity>.from(profiles);
    sorted.sort((a, b) {
      final aScope = (a.representedCompanyId ?? '').trim();
      final bScope = (b.representedCompanyId ?? '').trim();
      final aIsSelected = selected.isNotEmpty && aScope == selected;
      final bIsSelected = selected.isNotEmpty && bScope == selected;
      if (aIsSelected != bIsSelected) {
        return aIsSelected ? -1 : 1;
      }
      final priorityCompare = b.priority.compareTo(a.priority);
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  Stream<List<_TaxOperationProfileEntity>> _watchProfiles() {
    return _collection
        .where('tenantId', isEqualTo: widget.activeTenant.tenantId)
        .snapshots()
        .map((snapshot) {
          final profiles = <_TaxOperationProfileEntity>[];
          for (final doc in snapshot.docs) {
            final parsed = _TaxOperationProfileEntity.fromDoc(doc.id, doc.data());
            if (parsed == null) {
              continue;
            }
            profiles.add(parsed);
          }

          final scoped = profiles
              .where(_matchesSelectedScope)
              .toList(growable: false);
          return _sortForDisplay(scoped);
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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Perfis de operação',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Use os 10 tipos nativos pré-configurados para $scopeLabel e mapeie códigos externos por ERP quando necessário.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: canEditSettings && !_working
                      ? _reseedCurrentScopeDefaults
                      : null,
                  icon: const Icon(Icons.restart_alt_outlined),
                  label: const Text('Reaplicar 10 perfis'),
                ),
              ],
            ),
            if (!canEditSettings) ...[
              const SizedBox(height: 10),
              _ownerOnlyReadOnlyNotice(
                context,
                message:
                    'Perfis de operação ficam em modo somente leitura para este perfil. Apenas o owner pode alterar.',
              ),
            ],
            const SizedBox(height: 14),
            StreamBuilder<List<_TaxOperationProfileEntity>>(
              stream: _watchProfiles(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Falha ao carregar perfis de operação: ${_extractErrorMessage(snapshot.error!)}',
                  );
                }

                final profiles = snapshot.data ??
                    const <_TaxOperationProfileEntity>[];

                if (snapshot.connectionState == ConnectionState.waiting &&
                    profiles.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (profiles.isEmpty) {
                  return const Text(
                    'Nenhum perfil de operação encontrado. Clique em "Reaplicar 10 perfis" para pré-carregar os tipos nativos.',
                  );
                }

                final activeCount = profiles.where((item) => item.isActive).length;
                final withMappingCount = profiles
                    .where((item) => item.externalOperationCode.trim().isNotEmpty)
                    .length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statusChip(context, 'Total: ${profiles.length}'),
                        _statusChip(context, 'Ativos: $activeCount'),
                        _statusChip(context, 'Mapeados ERP: $withMappingCount'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: profiles.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final profile = profiles[index];
                        final switches = <String>[
                          if (profile.calculateIcmsSt) 'ST',
                          if (profile.calculateDifal) 'DIFAL',
                          if (profile.includeIpiInIcmsBase) 'IPI na base ICMS',
                          if (profile.addIpiToTotal) 'IPI no total',
                          if (profile.reduceIcmsForZfm) 'Desconto ICMS ZFM',
                        ];

                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              14,
                              10,
                              8,
                              10,
                            ),
                            title: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _statusChip(context, profile.name),
                                _statusChip(context, profile.profileKey),
                                _statusChip(
                                  context,
                                  profile.isActive ? 'Ativo' : 'Inativo',
                                ),
                                _statusChip(context, profile.scopeLabel),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                [
                                  if (profile.description.trim().isNotEmpty)
                                    profile.description.trim(),
                                  'Switches: ${switches.isEmpty ? 'Nenhum' : switches.join(', ')}',
                                  'Prioridade: ${profile.priority} | ERP: ${profile.erpProviderLabel} | Código externo: ${profile.externalOperationCodeLabel}',
                                ].join('\n'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Editar perfil',
                              onPressed: canEditSettings && !_working
                                  ? () => _openProfileDialog(profile)
                                  : null,
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ),
                        );
                      },
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

  Widget _statusChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.6),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }

  Future<void> _reseedCurrentScopeDefaults() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _working = true;
    });
    try {
      await _ensureDefaults();
      _showMessage('Perfis nativos verificados/reaplicados com sucesso.');
    } catch (error) {
      _showMessage(
        'Falha ao reaplicar perfis nativos: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _openProfileDialog(_TaxOperationProfileEntity profile) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: profile.name);
    final descriptionController = TextEditingController(
      text: profile.description,
    );
    final erpProviderController = TextEditingController(
      text: profile.erpProvider,
    );
    final externalCodeController = TextEditingController(
      text: profile.externalOperationCode,
    );
    final priorityController = TextEditingController(
      text: profile.priority.toString(),
    );
    var active = profile.isActive;
    var calculateIcmsSt = profile.calculateIcmsSt;
    var calculateDifal = profile.calculateDifal;
    var includeIpiInIcmsBase = profile.includeIpiInIcmsBase;
    var addIpiToTotal = profile.addIpiToTotal;
    var reduceIcmsForZfm = profile.reduceIcmsForZfm;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Editar perfil nativo: ${profile.profileKey}'),
              content: SizedBox(
                width: 620,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nome do perfil *',
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Nome obrigatório';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Descrição',
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: erpProviderController,
                                decoration: const InputDecoration(
                                  labelText: 'ERP provider',
                                  hintText: 'sankhya, totvs, sap...',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: externalCodeController,
                                decoration: const InputDecoration(
                                  labelText: 'Código externo',
                                  hintText: 'TOP/código no ERP',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: priorityController,
                          decoration: const InputDecoration(
                            labelText: 'Prioridade (inteiro)',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: active,
                          onChanged: (value) {
                            setDialogState(() {
                              active = value;
                            });
                          },
                          title: const Text('Perfil ativo'),
                        ),
                        const Divider(height: 18),
                        Text(
                          'Switches de cálculo fiscal',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: calculateIcmsSt,
                          onChanged: (value) {
                            setDialogState(() {
                              calculateIcmsSt = value;
                            });
                          },
                          title: const Text('Calcular ICMS-ST'),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: calculateDifal,
                          onChanged: (value) {
                            setDialogState(() {
                              calculateDifal = value;
                            });
                          },
                          title: const Text('Calcular DIFAL'),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: includeIpiInIcmsBase,
                          onChanged: (value) {
                            setDialogState(() {
                              includeIpiInIcmsBase = value;
                            });
                          },
                          title: const Text('IPI entra na base do ICMS'),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: addIpiToTotal,
                          onChanged: (value) {
                            setDialogState(() {
                              addIpiToTotal = value;
                            });
                          },
                          title: const Text('Somar IPI no total'),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: reduceIcmsForZfm,
                          onChanged: (value) {
                            setDialogState(() {
                              reduceIcmsForZfm = value;
                            });
                          },
                          title: const Text('Aplicar desconto ICMS para ZFM'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? true)) {
                      return;
                    }

                    try {
                      await _collection.doc(profile.id).set({
                        'name': nameController.text.trim(),
                        'description': descriptionController.text.trim(),
                        'status': active ? 'active' : 'inactive',
                        'priority': int.tryParse(priorityController.text.trim()) ??
                            profile.priority,
                        'erpProvider': erpProviderController.text.trim(),
                        'externalOperationCode':
                            externalCodeController.text.trim(),
                        'calculateIcmsSt': calculateIcmsSt,
                        'calculateDifal': calculateDifal,
                        'includeIpiInIcmsBase': includeIpiInIcmsBase,
                        'addIpiToTotal': addIpiToTotal,
                        'reduceIcmsForZfm': reduceIcmsForZfm,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));

                      if (!dialogContext.mounted) {
                        return;
                      }
                      Navigator.of(dialogContext).pop(true);
                    } catch (error) {
                      if (!dialogContext.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Falha ao salvar perfil: ${_extractErrorMessage(error)}',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true) {
      _showMessage('Perfil de operação atualizado com sucesso.');
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
}

class _NativeOperationProfileTemplate {
  const _NativeOperationProfileTemplate({
    required this.key,
    required this.name,
    required this.description,
    required this.defaultPriority,
    required this.calculateIcmsSt,
    required this.calculateDifal,
    required this.includeIpiInIcmsBase,
    required this.addIpiToTotal,
    required this.reduceIcmsForZfm,
  });

  final String key;
  final String name;
  final String description;
  final int defaultPriority;
  final bool calculateIcmsSt;
  final bool calculateDifal;
  final bool includeIpiInIcmsBase;
  final bool addIpiToTotal;
  final bool reduceIcmsForZfm;
}

class _TaxOperationProfileEntity {
  const _TaxOperationProfileEntity({
    required this.id,
    required this.tenantId,
    required this.profileKey,
    required this.name,
    required this.description,
    required this.status,
    required this.source,
    required this.priority,
    required this.calculateIcmsSt,
    required this.calculateDifal,
    required this.includeIpiInIcmsBase,
    required this.addIpiToTotal,
    required this.reduceIcmsForZfm,
    required this.erpProvider,
    required this.externalOperationCode,
    this.representedCompanyId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String? representedCompanyId;
  final String profileKey;
  final String name;
  final String description;
  final String status;
  final String source;
  final int priority;
  final bool calculateIcmsSt;
  final bool calculateDifal;
  final bool includeIpiInIcmsBase;
  final bool addIpiToTotal;
  final bool reduceIcmsForZfm;
  final String erpProvider;
  final String externalOperationCode;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status.trim().toLowerCase() == 'active';

  String get scopeLabel {
    return (representedCompanyId ?? '').trim().isEmpty
        ? 'Escopo: Global'
        : 'Escopo: Representada';
  }

  String get erpProviderLabel {
    final normalized = erpProvider.trim();
    if (normalized.isEmpty) {
      return 'Não informado';
    }
    return normalized;
  }

  String get externalOperationCodeLabel {
    final normalized = externalOperationCode.trim();
    if (normalized.isEmpty) {
      return 'Não mapeado';
    }
    return normalized;
  }

  static _TaxOperationProfileEntity? fromDoc(
    String id,
    Map<String, dynamic> raw,
  ) {
    final profileKey = (raw['profileKey'] ?? '').toString().trim();
    final name = (raw['name'] ?? '').toString().trim();
    if (profileKey.isEmpty || name.isEmpty) {
      return null;
    }

    return _TaxOperationProfileEntity(
      id: id,
      tenantId: (raw['tenantId'] ?? '').toString().trim(),
      representedCompanyId:
          (raw['representedCompanyId'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['representedCompanyId'] ?? '').toString().trim(),
      profileKey: profileKey,
      name: name,
      description: (raw['description'] ?? '').toString(),
      status: (raw['status'] ?? 'active').toString().trim().toLowerCase(),
      source: (raw['source'] ?? 'manual').toString().trim().toLowerCase(),
      priority: _readInt(raw['priority']),
      calculateIcmsSt: raw['calculateIcmsSt'] == true,
      calculateDifal: raw['calculateDifal'] == true,
      includeIpiInIcmsBase: raw['includeIpiInIcmsBase'] == true,
      addIpiToTotal: raw['addIpiToTotal'] == true,
      reduceIcmsForZfm: raw['reduceIcmsForZfm'] == true,
      erpProvider: (raw['erpProvider'] ?? '').toString(),
      externalOperationCode: (raw['externalOperationCode'] ?? '').toString(),
      createdAt: _readDateTime(raw['createdAt']),
      updatedAt: _readDateTime(raw['updatedAt']),
    );
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }
}
