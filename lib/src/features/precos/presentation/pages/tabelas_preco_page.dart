import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/product_base_price.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/models/tabela_preco.dart';
import '../../../../core/models/tenant_entry_decision.dart';
import '../../../../core/repositories/product_base_price_repository.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';
import '../../../../shared/services/tabular_spreadsheet_service.dart';
import '../../../../shared/utils/file_download.dart';
import '../services/default_price_table_guard.dart';

class TabelasPrecoPage extends StatefulWidget {
  const TabelasPrecoPage({
    super.key,
    required this.identity,
    required this.activeTenant,
    required this.repository,
    required this.productRepository,
    required this.basePriceRepository,
    this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final AppIdentity identity;
  final TenantEntryOption activeTenant;
  final TabelaPrecoRepository repository;
  final ProdutoRepository productRepository;
  final ProductBasePriceRepository basePriceRepository;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<TabelasPrecoPage> createState() => _TabelasPrecoPageState();
}

class _TabelasPrecoPageState extends State<TabelasPrecoPage> {
  final Set<String> _defaultEnsureQueuedScopes = <String>{};
  late Stream<List<TabelaPreco>> _tablesStream;
  late Stream<List<ProductBasePrice>> _basePricesStream;
  late Stream<List<Produto>> _productsStream;

  String _scopeKeyFor({
    required String workspaceType,
    required String? representedCompanyId,
    required String? representedCompanyName,
  }) {
    final normalizedWorkspaceType = workspaceType.trim().toLowerCase();
    final representedId = (representedCompanyId ?? '').trim();
    final representedName = (representedCompanyName ?? '').trim();
    final representedContext =
        normalizedWorkspaceType == 'rep_workspace' || representedName.isNotEmpty;
    final shouldUseRepresentedScope =
        representedContext && representedId.isNotEmpty;

    if (shouldUseRepresentedScope) {
      return DefaultPriceTableGuard.normalizeDefaultPricingScopeKey(representedId);
    }
    return 'tenant_default';
  }

  @override
  void initState() {
    super.initState();
    _bindStreams();
  }

  void _bindStreams() {
    final tenantId = widget.identity.tenantId;
    _tablesStream = widget.repository.watchAll(tenantId: tenantId);
    _basePricesStream = widget.basePriceRepository.watchAll(tenantId: tenantId);
    _productsStream = widget.productRepository.watchAll(tenantId: tenantId);
  }

  String _currentDefaultScopeKey() {
    return _scopeKeyFor(
      workspaceType: widget.activeTenant.workspaceType,
      representedCompanyId: widget.selectedRepresentedCompanyId,
      representedCompanyName: widget.activeRepresentedCompanyName,
    );
  }

  @override
  void didUpdateWidget(covariant TabelasPrecoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.tenantId != widget.identity.tenantId) {
      _bindStreams();
      _defaultEnsureQueuedScopes.clear();
      return;
    }

    if (oldWidget.activeTenant.tenantId != widget.activeTenant.tenantId) {
      _defaultEnsureQueuedScopes.clear();
      return;
    }

    final previousScopeKey = _scopeKeyFor(
      workspaceType: oldWidget.activeTenant.workspaceType,
      representedCompanyId: oldWidget.selectedRepresentedCompanyId,
      representedCompanyName: oldWidget.activeRepresentedCompanyName,
    );
    final nextScopeKey = _scopeKeyFor(
      workspaceType: widget.activeTenant.workspaceType,
      representedCompanyId: widget.selectedRepresentedCompanyId,
      representedCompanyName: widget.activeRepresentedCompanyName,
    );
    if (previousScopeKey != nextScopeKey) {
      _defaultEnsureQueuedScopes.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = _PriceTablePolicy.fromContext(
      workspaceType: widget.activeTenant.workspaceType,
      role: widget.identity.role,
    );
    final representedName = widget.activeRepresentedCompanyName?.trim() ?? '';
    final representedLabel = representedName.isEmpty
        ? 'sem representada selecionada'
        : 'representada $representedName';

    return StreamBuilder<List<TabelaPreco>>(
      stream: _tablesStream,
      initialData: const [],
      builder: (context, snapshot) {
        final tabelas = snapshot.data ?? const [];
        final scopeKey = _currentDefaultScopeKey();
        final streamReady = snapshot.connectionState != ConnectionState.waiting;
        if (streamReady && !_defaultEnsureQueuedScopes.contains(scopeKey)) {
          _defaultEnsureQueuedScopes.add(scopeKey);
          DefaultPriceTableGuard.queueEnsureDefaultPriceTableIfMissing(
            identity: widget.identity,
            activeTenant: widget.activeTenant,
            repository: widget.repository,
            allTables: tabelas,
            selectedRepresentedCompanyId: widget.selectedRepresentedCompanyId,
            activeRepresentedCompanyName: widget.activeRepresentedCompanyName,
          );
        }

        final workspaceType = widget.activeTenant.workspaceType.trim().toLowerCase();
        final hasRepresentedContext = representedName.isNotEmpty;
        final selectedRepresented = (widget.selectedRepresentedCompanyId ?? '').trim();
        final scopedTables = (workspaceType == 'rep_workspace' || hasRepresentedContext)
            ? tabelas
                .where(
                  (tabela) {
                    final isSystemDefault =
                        tabela.origem.trim().toLowerCase() == 'system' &&
                        tabela.nome.trim().toLowerCase() ==
                            reservedSystemDefaultPriceTableName;
                    if (!isSystemDefault) {
                      return true;
                    }
                    final linked = (tabela.linkedEntityId ?? '').trim();
                    final isTenantScoped = linked.isEmpty;
                    if (isTenantScoped) {
                      return false;
                    }
                    if (selectedRepresented.isEmpty) {
                      return true;
                    }
                    return linked == selectedRepresented;
                  },
                )
                .toList(growable: false)
            : tabelas;
        final visibleTabelas = DefaultPriceTableGuard.dedupeSystemDefaultTables(
          scopedTables,
          collapseRepresentedDefaults: hasRepresentedContext,
        );
        return StreamBuilder<List<ProductBasePrice>>(
          stream: _basePricesStream,
          initialData: const [],
          builder: (context, basePricesSnapshot) {
            final allBasePrices =
                basePricesSnapshot.data ?? const <ProductBasePrice>[];
            return StreamBuilder<List<Produto>>(
              stream: _productsStream,
              initialData: const [],
              builder: (context, productsSnapshot) {
                final allProducts = productsSnapshot.data ?? const <Produto>[];
                final activeProductIds = <String>{
                  for (final product in allProducts)
                    if (product.status == ProductStatus.active) product.id.trim(),
                };

                final uniqueItemCountByTableId = _buildUniqueItemCountByTableId(
                  allBasePrices,
                  activeProductIds: activeProductIds,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tabelas de preco', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Cadastro de tabelas por tenant para $representedLabel.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'As tabelas sao separadas do modulo de produtos e a vinculacao por cliente/regiao sera feita em tela dedicada.',
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: policy.canManage
                                      ? () => _downloadPriceTableTemplate(
                                            context,
                                            identity: widget.identity,
                                            productRepository: widget.productRepository,
                                          )
                                      : null,
                                  icon: const Icon(Icons.download_outlined),
                                  label: const Text('Baixar modelo XLSX'),
                                ),
                                FilledButton.icon(
                                  onPressed: policy.canManage
                                      ? () => _openImportSheet(
                                            context,
                                            identity: widget.identity,
                                            repository: widget.repository,
                                            productRepository: widget.productRepository,
                                            basePriceRepository: widget.basePriceRepository,
                                          )
                                      : null,
                                  icon: const Icon(Icons.upload_file_outlined),
                                  label: const Text('Importar planilha'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: policy.canManage
                                      ? () => _openCreateTableDialog(
                                            context,
                                            identity: widget.identity,
                                            repository: widget.repository,
                                          )
                                      : null,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Nova tabela'),
                                ),
                              ],
                            ),
                            if (!policy.canManage) ...[
                              const SizedBox(height: 12),
                              const ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.info_outline),
                                title: Text('Somente owner/gerente podem alterar tabelas no workspace enterprise.'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (visibleTabelas.isEmpty)
                      const Card(
                        child: ListTile(
                          title: Text('Nenhuma tabela cadastrada'),
                          subtitle: Text('Use importacao de planilha ou cadastro manual para iniciar.'),
                        ),
                      )
                    else
                      ...visibleTabelas.map(
                        (tabela) => _PriceTableCard(
                          tabela: tabela,
                          displayItemCount: _resolveDisplayItemCount(
                            tabela: tabela,
                            uniqueItemCountByTableId: uniqueItemCountByTableId,
                          ),
                          canManage: policy.canManage,
                          onDelete: () => _deleteTable(
                            context,
                            identity: widget.identity,
                            repository: widget.repository,
                            tabela: tabela,
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

Map<String, int> _buildUniqueItemCountByTableId(
  List<ProductBasePrice> prices,
  {Set<String>? activeProductIds,}
) {
  final byTable = <String, Set<String>>{};
  final activeIds = activeProductIds;
  for (final item in prices) {
    if (!item.isActive) {
      continue;
    }
    final tableId = item.priceTableId.trim();
    final productId = item.productId.trim();
    if (tableId.isEmpty || productId.isEmpty) {
      continue;
    }
    if (activeIds != null && activeIds.isNotEmpty && !activeIds.contains(productId)) {
      continue;
    }
    (byTable[tableId] ??= <String>{}).add(productId);
  }

  final counts = <String, int>{};
  for (final entry in byTable.entries) {
    counts[entry.key] = entry.value.length;
  }
  return counts;
}

int? _resolveDisplayItemCount({
  required TabelaPreco tabela,
  required Map<String, int> uniqueItemCountByTableId,
}) {
  final fromBasePrices = uniqueItemCountByTableId[tabela.id];
  if (fromBasePrices != null) {
    return fromBasePrices;
  }
  return tabela.rowCount;
}

class _PriceTablePolicy {
  const _PriceTablePolicy({required this.workspaceType, required this.role});

  final String workspaceType;
  final String role;

  static _PriceTablePolicy fromContext({
    required String workspaceType,
    required String role,
  }) {
    return _PriceTablePolicy(
      workspaceType: workspaceType.trim(),
      role: role.trim().toLowerCase(),
    );
  }

  bool get canManage {
    if (role == 'platform_admin') {
      return true;
    }

    if (workspaceType == 'brand_owner_workspace') {
      return role == 'owner' || role == 'gerente';
    }

    if (workspaceType == 'rep_workspace') {
      return role == 'owner' ||
          role == 'gerente' ||
          role == 'representante' ||
          role == 'vendedor';
    }

    if (workspaceType == 'seller_solo_workspace') {
      return role == 'vendedor';
    }

    return false;
  }
}

class _PriceTableCard extends StatelessWidget {
  const _PriceTableCard({
    required this.tabela,
    required this.displayItemCount,
    required this.canManage,
    required this.onDelete,
  });

  final TabelaPreco tabela;
  final int? displayItemCount;
  final bool canManage;
  final Future<void> Function() onDelete;

  bool get _isSystemDefault {
    return tabela.origem.trim().toLowerCase() == 'system' &&
        tabela.nome.trim().toLowerCase() == reservedSystemDefaultPriceTableName;
  }

  @override
  Widget build(BuildContext context) {
    final deleteEnabled = canManage && !_isSystemDefault;
    final itemCount = displayItemCount;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.price_change_outlined),
          title: Text(tabela.nome),
          subtitle: Text(
            'Origem: ${tabela.origem} · Status: ${tabela.status}'
            '${itemCount != null ? ' · Itens: $itemCount' : ''}',
          ),
          trailing: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(_formatDate(tabela.updatedAt)),
              if (deleteEnabled)
                IconButton(
                  tooltip: 'Excluir tabela',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _deleteTable(
  BuildContext context, {
  required AppIdentity identity,
  required TabelaPrecoRepository repository,
  required TabelaPreco tabela,
}) async {
  final isSystemDefault =
      tabela.origem.trim().toLowerCase() == 'system' &&
      tabela.nome.trim().toLowerCase() == reservedSystemDefaultPriceTableName;
  if (isSystemDefault) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('A tabela padrao do sistema nao pode ser excluida.'),
      ),
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Excluir tabela'),
      content: Text('Deseja excluir a tabela "${tabela.nome}"?'),
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
    ),
  );

  if (confirmed != true) {
    return;
  }

  try {
    await repository.delete(tenantId: identity.tenantId, id: tabela.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tabela excluida com sucesso.')),
    );
  } on StateError catch (error) {
    if (!context.mounted) {
      return;
    }
    final message = error.message.toString().trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message.isEmpty ? 'Nao foi possivel excluir a tabela.' : message,
        ),
      ),
    );
  }
}

Future<void> _openCreateTableDialog(
  BuildContext context, {
  required AppIdentity identity,
  required TabelaPrecoRepository repository,
}) async {
  final nameController = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            final name = nameController.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Informe um nome para a tabela.')),
              );
              return;
            }
            if (name.toLowerCase() == reservedSystemDefaultPriceTableName) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '"Tabela padrao" e um nome reservado para a tabela automatica do sistema.',
                  ),
                ),
              );
              return;
            }

            final now = DateTime.now().toUtc();
            final id = 'pt_${now.microsecondsSinceEpoch}';
            final tabela = TabelaPreco(
              id: id,
              tenantId: identity.tenantId,
              nome: name,
              scopeType: 'general',
              scopeLabel: '',
              scopeIndex: const ['general'],
              origem: 'manual',
              status: 'ativo',
              linkedEntityId: null,
              createdAt: now,
              updatedAt: now,
            );

            await repository.save(tabela);
            if (!context.mounted) {
              return;
            }
            Navigator.of(dialogContext).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tabela criada com sucesso.')),
            );
          }

          return AlertDialog(
            title: const Text('Nova tabela de preco'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome da tabela',
                      hintText: 'Ex.: Tabela Sul 2026',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: save,
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _openImportSheet(
  BuildContext context, {
  required AppIdentity identity,
  required TabelaPrecoRepository repository,
  required ProdutoRepository productRepository,
  required ProductBasePriceRepository basePriceRepository,
}) async {
  PlatformFile? selectedFile;
  _PriceImportValidation? validation;
  var importing = false;
  final tableNameController = TextEditingController();

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
              allowedExtensions: const ['xlsx', 'xls', 'csv'],
              allowMultiple: false,
              withData: true,
            );

            final file = result?.files.isNotEmpty == true ? result!.files.first : null;
            if (file == null) {
              return;
            }

            setSheetState(() {
              selectedFile = file;
              validation = null;
              tableNameController.text = _buildImportedName(file.name);
            });
          }

          Future<void> validate() async {
            final file = selectedFile;
            if (file == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selecione uma planilha primeiro.')),
              );
              return;
            }

            final report = _validatePriceSheet(file);
            setSheetState(() {
              validation = report;
            });
          }

          Future<void> importFile() async {
            final file = selectedFile;
            if (file == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selecione uma planilha para importar.')),
              );
              return;
            }

            final report = validation ?? _validatePriceSheet(file);
            if (!report.ok) {
              setSheetState(() {
                validation = report;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(report.message)),
              );
              return;
            }

            final importedName = tableNameController.text.trim();
            if (importedName.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Informe um nome para a nova tabela.'),
                ),
              );
              return;
            }

            if (importedName.toLowerCase() == reservedSystemDefaultPriceTableName) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '"Tabela padrao" e reservado. Defina outro nome.',
                  ),
                ),
              );
              return;
            }

            setSheetState(() {
              importing = true;
            });

            try {
              final now = DateTime.now().toUtc();
              final products = await productRepository.fetchAll(
                tenantId: identity.tenantId,
              );
              final productsByCode = <String, Produto>{};
              for (final product in products) {
                final code = product.codigoInterno.trim().toLowerCase();
                if (code.isEmpty) {
                  continue;
                }
                productsByCode[code] = product;
              }

              final rowsToImport = <_ImportedPriceRow>[];
              final unknownCodes = <String>{};
              for (final row in report.rows) {
                final code = _readPriceCell(
                  row,
                  const [
                    'codigointerno',
                    'codigo_interno',
                    'codigo',
                    'sku',
                  ],
                );
                if (code.isEmpty) {
                  continue;
                }

                final product = productsByCode[code.toLowerCase()];
                if (product == null) {
                  unknownCodes.add(code);
                  continue;
                }

                final rawPrice = _readPriceCell(
                  row,
                  const ['preco', 'valor', 'valor_bruto', 'baseprice'],
                );
                final basePrice = TabularSpreadsheetService.parseDecimal(
                  rawPrice,
                );
                if (basePrice == null) {
                  continue;
                }

                final regionId = _readPriceCell(
                  row,
                  const ['regiao', 'region', 'regionid'],
                );
                final statusRaw = _readPriceCell(
                  row,
                  const ['status'],
                );
                final validFrom = TabularSpreadsheetService.parseDate(
                  _readPriceCell(row, const ['validfrom', 'vigenciainicial']),
                );
                final validUntil = TabularSpreadsheetService.parseDate(
                  _readPriceCell(row, const ['validuntil', 'vigenciafinal']),
                );

                rowsToImport.add(
                  _ImportedPriceRow(
                    productId: product.id,
                    basePrice: basePrice,
                    regionId: regionId.isEmpty ? 'ALL' : regionId,
                    status: _normalizePriceStatus(statusRaw),
                    validFrom: validFrom,
                    validUntil: validUntil,
                  ),
                );
              }

              if (unknownCodes.isNotEmpty) {
                if (!sheetContext.mounted) {
                  return;
                }
                final sample = unknownCodes.take(10).join(', ');
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Codigos nao encontrados no cadastro de produtos: $sample${unknownCodes.length > 10 ? ' ...' : ''}.',
                    ),
                  ),
                );
                return;
              }

              if (rowsToImport.isEmpty) {
                if (!sheetContext.mounted) {
                  return;
                }
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Nenhum preco valido encontrado para importacao.',
                    ),
                  ),
                );
                return;
              }

              final tabela = TabelaPreco(
                id: 'pt_${now.microsecondsSinceEpoch}',
                tenantId: identity.tenantId,
                nome: importedName,
                scopeType: 'general',
                scopeLabel: '',
                scopeIndex: const ['general'],
                origem: 'excel',
                status: 'ativo',
                linkedEntityId: null,
                fileName: file.name,
                rowCount: rowsToImport.length,
                createdAt: now,
                updatedAt: now,
              );

              await repository.save(tabela);

              for (var index = 0; index < rowsToImport.length; index++) {
                final row = rowsToImport[index];
                await basePriceRepository.save(
                  ProductBasePrice(
                    id: 'pbp_${now.microsecondsSinceEpoch}_$index',
                    tenantId: identity.tenantId,
                    productId: row.productId,
                    priceTableId: tabela.id,
                    regionId: row.regionId,
                    basePrice: row.basePrice,
                    status: row.status,
                    currencyCode: 'BRL',
                    validFrom: row.validFrom,
                    validUntil: row.validUntil,
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
              }

              if (!context.mounted) {
                return;
              }

              Navigator.of(sheetContext).pop();
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(
                  content: Text(
                    'Tabela importada: ${tabela.nome} (${rowsToImport.length} preco(s)).',
                  ),
                ),
              );
            } finally {
              if (context.mounted) {
                setSheetState(() {
                  importing = false;
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
                    'Importar tabela de preco',
                    style: Theme.of(sheetContext).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Importe XLSX/CSV com colunas codigoInterno e preco. Somente produtos existentes sao aceitos.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tableNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome da nova tabela',
                      hintText: 'Ex.: Tabela Julho 2026',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (selectedFile != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(selectedFile!.name),
                      subtitle: Text('${(selectedFile!.size / 1024).toStringAsFixed(1)} KB'),
                    ),
                  if (validation != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        validation!.ok ? Icons.verified_outlined : Icons.error_outline,
                        color: validation!.ok ? Colors.green : Colors.red,
                      ),
                      title: Text(validation!.ok ? 'Validacao concluida' : 'Validacao com erro'),
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
                        icon: const Icon(Icons.playlist_add_check_circle_outlined),
                        label: Text(importing ? 'Importando...' : 'Importar agora'),
                      ),
                      TextButton(
                        onPressed: importing ? null : () => Navigator.of(sheetContext).pop(),
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

class _PriceImportValidation {
  const _PriceImportValidation({
    required this.ok,
    required this.message,
    required this.rows,
  });

  final bool ok;
  final String message;
  final List<Map<String, String>> rows;
}

_PriceImportValidation _validatePriceSheet(PlatformFile file) {
  final parsed = TabularSpreadsheetService.parseFile(file);
  if (!parsed.ok) {
    return _PriceImportValidation(
      ok: false,
      message: parsed.message,
      rows: const <Map<String, String>>[],
    );
  }

  final header = parsed.headers;

  final hasCodigo = header.contains('codigointerno') ||
      header.contains('codigo_interno') ||
      header.contains('codigo') ||
      header.contains('sku');
  final hasPreco = header.contains('preco') ||
      header.contains('valor') ||
      header.contains('valor_bruto');

  if (!hasCodigo || !hasPreco) {
    return const _PriceImportValidation(
      ok: false,
      message: 'Cabecalho invalido. Campos obrigatorios: codigoInterno e preco.',
      rows: <Map<String, String>>[],
    );
  }

  final missingCodeLines = <int>[];
  final invalidPriceLines = <int>[];
  for (var index = 0; index < parsed.rows.length; index++) {
    final row = parsed.rows[index];
    final code = _readPriceCell(
      row,
      const <String>['codigointerno', 'codigo_interno', 'codigo', 'sku'],
    );
    final rawPrice = _readPriceCell(
      row,
      const <String>['preco', 'valor', 'valor_bruto', 'baseprice'],
    );
    final parsedPrice = TabularSpreadsheetService.parseDecimal(rawPrice);

    if (code.isEmpty) {
      missingCodeLines.add(index + 2);
    }
    if (parsedPrice == null) {
      invalidPriceLines.add(index + 2);
    }
  }

  if (missingCodeLines.isNotEmpty || invalidPriceLines.isNotEmpty) {
    final parts = <String>[];
    if (missingCodeLines.isNotEmpty) {
      final sample = missingCodeLines.take(10).join(', ');
      parts.add(
        'linhas sem codigoInterno: $sample${missingCodeLines.length > 10 ? ' ...' : ''}',
      );
    }
    if (invalidPriceLines.isNotEmpty) {
      final sample = invalidPriceLines.take(10).join(', ');
      parts.add(
        'linhas com preco invalido: $sample${invalidPriceLines.length > 10 ? ' ...' : ''}',
      );
    }

    return _PriceImportValidation(
      ok: false,
      message: 'Inconsistencias na planilha (${parts.join(' | ')}).',
      rows: parsed.rows,
    );
  }

  return _PriceImportValidation(
    ok: true,
    message: 'Arquivo valido com ${parsed.rows.length} linha(s).',
    rows: parsed.rows,
  );
}

Future<void> _downloadPriceTableTemplate(
  BuildContext context, {
  required AppIdentity identity,
  required ProdutoRepository productRepository,
}) async {
  try {
    final products = await productRepository.fetchAll(tenantId: identity.tenantId);
    if (products.isEmpty) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cadastre produtos antes de gerar o modelo de tabela.'),
        ),
      );
      return;
    }

    final sorted = List<Produto>.from(products)
      ..sort(
        (a, b) => a.codigoInterno.toLowerCase().compareTo(
          b.codigoInterno.toLowerCase(),
        ),
      );

    final rows = sorted
        .map(
          (item) => <String>[
            item.codigoInterno,
            item.descricao,
            '',
            'ALL',
            'active',
            '',
            '',
          ],
        )
        .toList(growable: false);

    final bytes = TabularSpreadsheetService.buildXlsx(
      sheetName: 'TabelaPreco',
      headers: const <String>[
        'codigoInterno',
        'descricao',
        'preco',
        'regiao',
        'status',
        'validFrom',
        'validUntil',
      ],
      rows: rows,
    );

    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await downloadFileBytes(
      bytes: bytes,
      fileName: 'modelo_tabela_preco_$stamp.xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Falha ao baixar modelo da tabela de preco: $error'),
      ),
    );
  }
}

String _buildImportedName(String fileName) {
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  final normalized = fileName.trim();
  final dot = normalized.lastIndexOf('.');
  final baseName = dot > 0 ? normalized.substring(0, dot) : normalized;
  final clean = baseName.trim().isEmpty ? 'Tabela importada' : baseName.trim();
  return 'Import $stamp - $clean';
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return '-';
  }

  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/$year $hour:$minute';
}

String _readPriceCell(Map<String, String> row, List<String> aliases) {
  for (final alias in aliases) {
    final value = row[TabularSpreadsheetService.normalizeHeader(alias)]?.trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _normalizePriceStatus(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized == 'inactive' ||
      normalized == 'inativo' ||
      normalized == 'desativado') {
    return 'inactive';
  }
  return 'active';
}

class _ImportedPriceRow {
  const _ImportedPriceRow({
    required this.productId,
    required this.basePrice,
    required this.regionId,
    required this.status,
    required this.validFrom,
    required this.validUntil,
  });

  final String productId;
  final double basePrice;
  final String regionId;
  final String status;
  final DateTime? validFrom;
  final DateTime? validUntil;
}