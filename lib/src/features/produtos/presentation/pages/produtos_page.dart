import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../auth/services/workspace_profile_service.dart';

const List<String> _productBitolaUnits = <String>['mm', 'cm', 'm'];

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({
    super.key,
    required this.identity,
    required this.repository,
    this.activeRepresentedCompanyName,
  });

  final AppIdentity identity;
  final ProdutoRepository repository;
  final String? activeRepresentedCompanyName;

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

class _ProdutosPageState extends State<ProdutosPage> {
  final WorkspaceProfileService _workspaceService = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );

  bool _updatingErpSync = false;
  String _brandFilter = 'todas';

  Future<bool> _openDisableErpSyncDialog() async {
    var selected = _DisableErpSyncAction.keepCurrent;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Desativar sincronizacao ERP'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Escolha como tratar os produtos de origem ERP apos desligar a sincronizacao.',
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<_DisableErpSyncAction>(
                    segments: const [
                      ButtonSegment<_DisableErpSyncAction>(
                        value: _DisableErpSyncAction.keepCurrent,
                        label: Text('Manter'),
                        icon: Icon(Icons.lock_open_outlined),
                      ),
                      ButtonSegment<_DisableErpSyncAction>(
                        value: _DisableErpSyncAction.deactivateErpProducts,
                        label: Text('Inativar ERP'),
                        icon: Icon(Icons.cancel_outlined),
                      ),
                    ],
                    selected: <_DisableErpSyncAction>{selected},
                    onSelectionChanged: (value) {
                      setDialogState(() {
                        selected = value.first;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    selected == _DisableErpSyncAction.keepCurrent
                        ? 'Acao selecionada: manter produtos ERP como estao e apenas liberar cadastro manual.'
                        : 'Acao selecionada: inativar produtos ERP, mantendo historico e IDs de integracao.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      return false;
    }

    if (selected == _DisableErpSyncAction.deactivateErpProducts) {
      await _deactivateErpProducts();
    }

    return true;
  }

  Future<void> _deactivateErpProducts() async {
    final produtos = await widget.repository.fetchAll(tenantId: widget.identity.tenantId);
    var updated = 0;
    for (final produto in produtos) {
      if (produto.origemCadastro != ProductSource.erp) {
        continue;
      }
      if (produto.status == ProductStatus.inactive) {
        continue;
      }

      await widget.repository.save(
        produto.copyWith(
          status: ProductStatus.inactive,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      updated++;
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$updated produto(s) ERP inativado(s).')),
    );
  }

  Future<void> _setErpSyncEnabled(bool enabled) async {
    if (!enabled) {
      final proceed = await _openDisableErpSyncDialog();
      if (!proceed) {
        return;
      }
    }

    setState(() {
      _updatingErpSync = true;
    });

    try {
      await _workspaceService.setProductSyncFromErpEnabled(
        tenantId: widget.identity.tenantId,
        enabled: enabled,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Sincronizacao de produtos via ERP ativada.'
                : 'Sincronizacao de produtos via ERP desativada.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar integracao de produtos: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingErpSync = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantStream = widget.identity.isMock
        ? Stream<Map<String, dynamic>?>.value(null)
        : _workspaceService.watchWorkspace(widget.identity.tenantId);

    return StreamBuilder<Map<String, dynamic>?>(
      stream: tenantStream,
      builder: (context, tenantSnapshot) {
        final policy = _ProductCatalogPolicy.fromContext(
          tenantData: tenantSnapshot.data,
          role: widget.identity.role,
          isPersonalWorkspace: widget.identity.isPersonalWorkspace,
        );

        return StreamBuilder<List<Produto>>(
          stream: widget.repository.watchAll(tenantId: widget.identity.tenantId),
          initialData: const [],
          builder: (context, snapshot) {
            final produtos = snapshot.data ?? const [];
            final availableBrands = _collectAvailableBrands(produtos);
            final effectiveBrandFilter =
                (_brandFilter == 'todas' || availableBrands.contains(_brandFilter))
                ? _brandFilter
                : 'todas';
            if (_brandFilter != effectiveBrandFilter) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _brandFilter = effectiveBrandFilter;
                });
              });
            }
            final filteredProducts = effectiveBrandFilter == 'todas'
                ? produtos
                : produtos
                    .where((produto) => (produto.marca ?? '').trim().toLowerCase() == effectiveBrandFilter.toLowerCase())
                    .toList(growable: false);

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeaderCard(
                      title: 'Produtos',
                      subtitle:
                          'Cadastro de atributos fisicos e fiscais do produto. Precos e politicas comerciais ficam em modulos dedicados.',
                      actions: [
                        if (policy.canCreateOrImportProducts) ...[
                          OutlinedButton.icon(
                            onPressed: () => _openProductImportSheet(
                              context,
                              identity: widget.identity,
                              repository: widget.repository,
                            ),
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Importar Excel'),
                          ),
                          FilledButton.icon(
                            onPressed: () => _openProductSheet(
                              context,
                              identity: widget.identity,
                              repository: widget.repository,
                              isEnterprise: policy.isEnterprise,
                              representedCompanyName: widget.activeRepresentedCompanyName,
                              existingProducts: produtos,
                              availableBrands: availableBrands,
                              allowManualActions: policy.canCreateOrImportProducts,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Novo produto'),
                          ),
                        ],
                      ],
                    ),
                    if (availableBrands.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.filter_alt_outlined),
                              const SizedBox(width: 12),
                              const Text('Marca'),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: effectiveBrandFilter,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  items: <String>['todas', ...availableBrands]
                                      .map(
                                        (brand) => DropdownMenuItem<String>(
                                          value: brand,
                                          child: Text(brand == 'todas' ? 'Todas as marcas' : brand),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setState(() {
                                      _brandFilter = value;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (policy.showEnterpriseSyncSwitchCard) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: SwitchListTile(
                          title: const Text('Sincronizar produtos do ERP'),
                          subtitle: const Text(
                            'Quando ativado, o ERP vira fonte da verdade e o cadastro manual/importacao de produtos fica bloqueado.',
                          ),
                          value: policy.erpSyncEnabled,
                          onChanged: _updatingErpSync ? null : _setErpSyncEnabled,
                        ),
                      ),
                    ],
                    if (policy.showErpManagedInfoCard) ...[
                      const SizedBox(height: 12),
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.sync_lock_outlined),
                          title: Text('Produtos gerenciados pela integração ERP'),
                          subtitle: Text(
                            'Neste contexto, a criação manual e a importação por arquivo ficam ocultas para preservar o ERP como fonte única.',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (filteredProducts.isEmpty)
                      const _EmptyState(
                        title: 'Nenhum produto carregado',
                        subtitle:
                            'A base de produtos vai aparecer aqui quando a carga inicial entrar.',
                      )
                    else
                      ...filteredProducts.map(
                        (produto) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ProdutoSummaryCard(
                            produto: produto,
                            onTap: () => _openProductSheet(
                              context,
                              produto: produto,
                              identity: widget.identity,
                              repository: widget.repository,
                              isEnterprise: policy.isEnterprise,
                              representedCompanyName: widget.activeRepresentedCompanyName,
                              existingProducts: produtos,
                              availableBrands: availableBrands,
                              allowManualActions: policy.canCreateOrImportProducts,
                            ),
                          ),
                        ),
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
}

class _ProductCatalogPolicy {
  const _ProductCatalogPolicy({
    required this.workspaceType,
    required this.role,
    required this.erpSyncEnabled,
  });

  final String workspaceType;
  final String role;
  final bool erpSyncEnabled;

  static _ProductCatalogPolicy fromContext({
    required Map<String, dynamic>? tenantData,
    required String role,
    required bool isPersonalWorkspace,
  }) {
    final normalizedRole = role.trim().toLowerCase();
    final workspaceType = isPersonalWorkspace
        ? 'seller_solo_workspace'
        : (tenantData?['workspaceType'] ?? '').toString().trim();
    final erpSyncEnabled = workspaceType == 'brand_owner_workspace' &&
        tenantData?['productSyncFromErpEnabled'] == true;

    return _ProductCatalogPolicy(
      workspaceType: workspaceType,
      role: normalizedRole,
      erpSyncEnabled: erpSyncEnabled,
    );
  }

  bool get isEnterprise => workspaceType == 'brand_owner_workspace';

  bool get isOwnerOrPlatformAdmin => role == 'owner' || role == 'platform_admin';

  bool get showEnterpriseSyncSwitchCard => isEnterprise && isOwnerOrPlatformAdmin;

  bool get showErpManagedInfoCard => isEnterprise && erpSyncEnabled;

  bool get canCreateOrImportProducts {
    if (erpSyncEnabled) {
      return false;
    }

    if (workspaceType == 'brand_owner_workspace') {
      return isOwnerOrPlatformAdmin;
    }

    if (workspaceType == 'rep_workspace') {
      return role == 'owner' ||
          role == 'gerente' ||
          role == 'representante' ||
          role == 'vendedor' ||
          role == 'platform_admin';
    }

    if (workspaceType == 'seller_solo_workspace') {
      return role == 'vendedor' || role == 'platform_admin';
    }

    return false;
  }
}

Future<void> _openProductSheet(
  BuildContext context, {
  Produto? produto,
  required AppIdentity identity,
  required ProdutoRepository repository,
  required bool isEnterprise,
  String? representedCompanyName,
  required List<Produto> existingProducts,
  required List<String> availableBrands,
  required bool allowManualActions,
}) async {
  final saved = await showModalBottomSheet<Produto>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return _ProductEditorSheet(
        identity: identity,
        repository: repository,
        isEnterprise: isEnterprise,
        representedCompanyName: representedCompanyName,
        existingProducts: existingProducts,
        availableBrands: availableBrands,
        produto: produto,
        allowManualActions: allowManualActions,
      );
    },
  );

  if (!context.mounted || saved == null) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        produto == null
            ? 'Produto cadastrado com sucesso.'
            : 'Produto atualizado com sucesso.',
      ),
    ),
  );
}

Produto _emptyDraft() {
  return const Produto(
    id: 'draft',
    tenantId: 'draft',
    codigoInterno: '',
    descricao: '',
    origemCadastro: ProductSource.manual,
    status: ProductStatus.active,
    descricaoResumida: '',
    sku: '',
    ean: '',
    marca: '',
    categoria: '',
    subcategoria: '',
    unidade: 'UN',
    bitolaUnidade: 'mm',
    multiploVenda: 1,
    quantidadeMinima: 1,
    ncm: '0000.00.00',
    cfop: '5102',
    aliquotaIcms: 0,
    aliquotaPis: 0,
    aliquotaCofins: 0,
    pesoKg: 0,
    erpProductId: '',
    erpSyncId: '',
    tabelaPrecoVersao: 'rascunho',
    estoqueVersao: 'rascunho',
  );
}

List<String> _collectAvailableBrands(List<Produto> produtos) {
  final map = <String, String>{};
  for (final produto in produtos) {
    final raw = (produto.marca ?? '').trim();
    if (raw.isEmpty) {
      continue;
    }
    final key = raw.toLowerCase();
    map.putIfAbsent(key, () => raw);
  }

  final values = map.values.toList(growable: false)
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return values;
}

String _normalizeBrand({
  required String rawBrand,
  required List<String> availableBrands,
}) {
  final normalized = rawBrand.trim();
  if (normalized.isEmpty) {
    return '';
  }

  for (final brand in availableBrands) {
    if (brand.trim().toLowerCase() == normalized.toLowerCase()) {
      return brand;
    }
  }

  return normalized;
}

String _buildNextProductCode(List<Produto> existingProducts) {
  var maxSequence = 0;
  final pattern = RegExp(r'(\d+)');

  for (final produto in existingProducts) {
    final codigo = produto.codigoInterno.trim();
    int? parsed;
    for (final match in pattern.allMatches(codigo)) {
      parsed = int.tryParse(match.group(1) ?? '') ?? parsed;
    }
    if (parsed != null && parsed > maxSequence) {
      maxSequence = parsed;
    }
  }

  final next = maxSequence + 1;
  return 'PRD-${next.toString().padLeft(6, '0')}';
}

class _ProductEditorSheet extends StatefulWidget {
  const _ProductEditorSheet({
    required this.identity,
    required this.repository,
    required this.isEnterprise,
    required this.existingProducts,
    required this.availableBrands,
    required this.allowManualActions,
    this.representedCompanyName,
    this.produto,
  });

  final AppIdentity identity;
  final ProdutoRepository repository;
  final bool isEnterprise;
  final List<Produto> existingProducts;
  final List<String> availableBrands;
  final bool allowManualActions;
  final String? representedCompanyName;
  final Produto? produto;

  @override
  State<_ProductEditorSheet> createState() => _ProductEditorSheetState();
}

class _ProductEditorSheetState extends State<_ProductEditorSheet> {
  late final TextEditingController _codigoController;
  late final TextEditingController _codigoFabricanteController;
  late final TextEditingController _eanController;
  late final TextEditingController _descricaoController;
  late final TextEditingController _descricaoLongaController;
  late final TextEditingController _marcaController;
  late final TextEditingController _categoriaController;
  late final TextEditingController _subcategoriaController;
  late final TextEditingController _bitolaController;
  late final TextEditingController _unidadeController;
  late final TextEditingController _ncmController;
  late final TextEditingController _cfopController;
  late final TextEditingController _icmsController;
  late final TextEditingController _pisController;
  late final TextEditingController _cofinsController;
  late final TextEditingController _pesoController;
  late final TextEditingController _comprimentoMmController;
  late final TextEditingController _larguraMmController;
  late final TextEditingController _alturaMmController;
  late final TextEditingController _quantidadeMinimaController;
  late final TextEditingController _multiploVendaController;
  late final TextEditingController _fotoUrlController;
  late final TextEditingController _erpProductIdController;
  late final TextEditingController _erpSyncIdController;
  late final TextEditingController _tabelaVersaoController;
  late final TextEditingController _estoqueVersaoController;

  late ProductStatus _status;
  late String _bitolaUnit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final produto = widget.produto ?? _emptyDraft().copyWith(
      codigoInterno: _buildNextProductCode(widget.existingProducts),
    );
    _codigoController = TextEditingController(text: produto.codigoInterno);
    _codigoFabricanteController = TextEditingController(text: produto.codigoFabricante ?? '');
    _eanController = TextEditingController(text: produto.ean ?? '');
    _descricaoController = TextEditingController(text: produto.descricao);
    _descricaoLongaController = TextEditingController(
      text: produto.descricaoLonga ?? produto.descricaoResumida ?? '',
    );
    _marcaController = TextEditingController(text: produto.marca ?? '');
    _categoriaController = TextEditingController(text: produto.categoria ?? '');
    _subcategoriaController = TextEditingController(text: produto.subcategoria ?? '');
    _bitolaController = TextEditingController(text: produto.bitola ?? '');
    _unidadeController = TextEditingController(text: produto.unidade ?? 'UN');
    _ncmController = TextEditingController(text: produto.ncm ?? '');
    _cfopController = TextEditingController(text: produto.cfop ?? '');
    _icmsController = TextEditingController(text: _toText(produto.aliquotaIcms));
    _pisController = TextEditingController(text: _toText(produto.aliquotaPis));
    _cofinsController = TextEditingController(text: _toText(produto.aliquotaCofins));
    _pesoController = TextEditingController(text: _toText(produto.pesoKg));
    _comprimentoMmController = TextEditingController(text: _toText(produto.comprimentoMm));
    _larguraMmController = TextEditingController(text: _toText(produto.larguraMm));
    _alturaMmController = TextEditingController(text: _toText(produto.alturaMm));
    _quantidadeMinimaController = TextEditingController(text: _toText(produto.quantidadeMinima));
    _multiploVendaController = TextEditingController(text: _toText(produto.multiploVenda));
    _fotoUrlController = TextEditingController(text: produto.fotoUrl ?? '');
    _erpProductIdController = TextEditingController(text: produto.erpProductId ?? '');
    _erpSyncIdController = TextEditingController(text: produto.erpSyncId ?? '');
    _tabelaVersaoController = TextEditingController(text: produto.tabelaPrecoVersao ?? 'manual-v1');
    _estoqueVersaoController = TextEditingController(text: produto.estoqueVersao ?? 'manual-v1');
    _status = produto.status;
    final incomingUnit = (produto.bitolaUnidade ?? 'mm').trim().toLowerCase();
    _bitolaUnit = _productBitolaUnits.contains(incomingUnit) ? incomingUnit : 'mm';
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _codigoFabricanteController.dispose();
    _eanController.dispose();
    _descricaoController.dispose();
    _descricaoLongaController.dispose();
    _marcaController.dispose();
    _categoriaController.dispose();
    _subcategoriaController.dispose();
    _bitolaController.dispose();
    _unidadeController.dispose();
    _ncmController.dispose();
    _cfopController.dispose();
    _icmsController.dispose();
    _pisController.dispose();
    _cofinsController.dispose();
    _pesoController.dispose();
    _comprimentoMmController.dispose();
    _larguraMmController.dispose();
    _alturaMmController.dispose();
    _quantidadeMinimaController.dispose();
    _multiploVendaController.dispose();
    _fotoUrlController.dispose();
    _erpProductIdController.dispose();
    _erpSyncIdController.dispose();
    _tabelaVersaoController.dispose();
    _estoqueVersaoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = !widget.allowManualActions;

    return DefaultTabController(
      length: 3,
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
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
                          _buildEditorTitle(),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TabBar(
                tabs: [
                  const Tab(icon: Icon(Icons.info_outline), text: 'Geral'),
                  const Tab(icon: Icon(Icons.account_balance_outlined), text: 'Fiscal'),
                  Tab(
                    icon: const Icon(Icons.inventory_2_outlined),
                    text: widget.isEnterprise ? 'Estoque e integração' : 'Estoque',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildGeneralTab(readOnly),
                    _buildFiscalTab(readOnly),
                    _buildStockIntegrationTab(readOnly),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (readOnly)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('Cadastro manual bloqueado neste contexto'),
                    subtitle: Text(
                      'Quando a integração ERP é a fonte de verdade, este formulário fica somente para consulta.',
                    ),
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Salvando...' : 'Salvar produto'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralTab(bool readOnly) {
    return ListView(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _editorField(
                _codigoController,
                'Codigo interno',
                readOnly: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<ProductStatus>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: ProductStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(status.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: readOnly
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _status = value;
                        });
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _editorField(
          _codigoFabricanteController,
          'Codigo do fabricante',
          readOnly: readOnly,
        ),
        const SizedBox(height: 10),
        _editorField(_descricaoController, 'Nome do produto *', readOnly: readOnly),
        const SizedBox(height: 10),
        _editorField(_eanController, 'EAN/GTIN', readOnly: readOnly),
        const SizedBox(height: 10),
        _editorField(
          _descricaoLongaController,
          'Descricao longa',
          readOnly: readOnly,
          maxLines: 3,
        ),
        const SizedBox(height: 10),
        _editorField(
          _marcaController,
          'Marca',
          readOnly: readOnly,
        ),
        const SizedBox(height: 8),
        if (widget.availableBrands.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.availableBrands
                .where((item) => item.toLowerCase() != _marcaController.text.trim().toLowerCase())
                .take(12)
                .map(
                  (brand) => ActionChip(
                    label: Text(brand),
                    onPressed: readOnly
                        ? null
                        : () {
                            setState(() {
                              _marcaController.text = brand;
                            });
                          },
                  ),
                )
                .toList(growable: false),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _editorField(
                _bitolaController,
                'Bitola / medida',
                readOnly: readOnly,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _bitolaUnit,
                decoration: const InputDecoration(
                  labelText: 'Unidade da bitola',
                  border: OutlineInputBorder(),
                ),
                items: _productBitolaUnits
                    .map(
                      (unit) => DropdownMenuItem<String>(
                        value: unit,
                        child: Text(unit.toUpperCase()),
                      ),
                    )
                    .toList(growable: false),
                onChanged: readOnly
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _bitolaUnit = value;
                        });
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _editorField(_categoriaController, 'Categoria', readOnly: readOnly)),
            const SizedBox(width: 10),
            Expanded(
              child: _editorField(
                _subcategoriaController,
                'Subcategoria',
                readOnly: readOnly,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _editorField(_unidadeController, 'Unidade de venda', readOnly: readOnly),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _editorField(
                _pesoController,
                'Peso (kg)',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dimensoes', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _editorField(
                      _comprimentoMmController,
                      'Comprimento (mm)',
                      readOnly: readOnly,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _editorField(
                      _larguraMmController,
                      'Largura (mm)',
                      readOnly: readOnly,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _editorField(
                      _alturaMmController,
                      'Altura (mm)',
                      readOnly: readOnly,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFiscalTab(bool readOnly) {
    return ListView(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _editorField(_ncmController, 'NCM', readOnly: readOnly)),
            const SizedBox(width: 10),
            Expanded(child: _editorField(_cfopController, 'CFOP', readOnly: readOnly)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _editorField(
                _icmsController,
                'ICMS (%)',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _editorField(
                _pisController,
                'PIS (%)',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _editorField(
                _cofinsController,
                'COFINS (%)',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStockIntegrationTab(bool readOnly) {
    final isEnterprise = widget.isEnterprise;

    return ListView(
      children: [
        const SizedBox(height: 8),
        _editorField(_fotoUrlController, 'URL da imagem', readOnly: readOnly),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _editorField(
                _tabelaVersaoController,
                'Versao de estoque',
                readOnly: readOnly,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _editorField(
                _quantidadeMinimaController,
                'Quantidade minima',
                readOnly: readOnly,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _editorField(
          _multiploVendaController,
          'Multiplo de venda',
          readOnly: readOnly,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 10),
        _editorField(
          _estoqueVersaoController,
          'Referencia de controle manual',
          readOnly: readOnly,
        ),
        if (isEnterprise) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _editorField(
                  _erpProductIdController,
                  'ID do produto no ERP',
                  readOnly: readOnly,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _editorField(
                  _erpSyncIdController,
                  'ID de sincronizacao ERP',
                  readOnly: readOnly,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _editorField(
    TextEditingController controller,
    String label, {
    required bool readOnly,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Future<void> _save() async {
    final codigo = _codigoController.text.trim();
    final descricao = _descricaoController.text.trim();
    if (descricao.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha o campo obrigatorio: descricao resumida.')),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final existing = widget.produto;
      final now = DateTime.now().toUtc();
      final normalizedBrand = _normalizeBrand(
        rawBrand: _marcaController.text,
        availableBrands: widget.availableBrands,
      );
      final entity = Produto(
        id: existing?.id ?? 'prd_${now.microsecondsSinceEpoch}',
        tenantId: widget.identity.tenantId,
        codigoInterno: codigo,
        descricao: descricao,
        origemCadastro: existing?.origemCadastro ?? ProductSource.manual,
        status: _status,
        descricaoLonga: _nullable(_descricaoLongaController.text),
        descricaoResumida: existing?.descricaoResumida,
        codigoFabricante: _nullable(_codigoFabricanteController.text),
        sku: existing?.sku,
        ean: _nullable(_eanController.text),
        marca: normalizedBrand,
        categoria: _nullable(_categoriaController.text),
        subcategoria: _nullable(_subcategoriaController.text),
        bitola: _nullable(_bitolaController.text),
        bitolaUnidade: _nullable(_bitolaUnit) ?? 'mm',
        comprimentoMm: _toDouble(_comprimentoMmController.text),
        larguraMm: _toDouble(_larguraMmController.text),
        alturaMm: _toDouble(_alturaMmController.text),
        valorBruto: existing?.valorBruto,
        precoMinimo: existing?.precoMinimo,
        percentualComissao: existing?.percentualComissao,
        unidade: _nullable(_unidadeController.text) ?? 'UN',
        multiploVenda: _toDouble(_multiploVendaController.text),
        quantidadeMinima: _toDouble(_quantidadeMinimaController.text),
        ncm: _nullable(_ncmController.text),
        cfop: _nullable(_cfopController.text),
        aliquotaIcms: _toDouble(_icmsController.text),
        aliquotaPis: _toDouble(_pisController.text),
        aliquotaCofins: _toDouble(_cofinsController.text),
        pesoKg: _toDouble(_pesoController.text),
        fotoUrl: _nullable(_fotoUrlController.text),
        erpProductId: widget.isEnterprise ? _nullable(_erpProductIdController.text) : null,
        erpSyncId: widget.isEnterprise ? _nullable(_erpSyncIdController.text) : null,
        tabelaPrecoVersao: _nullable(_tabelaVersaoController.text),
        estoqueVersao: _nullable(_estoqueVersaoController.text),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );

      await widget.repository.save(entity);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(entity);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar produto: $error')),
      );
      setState(() {
        _saving = false;
      });
    }
  }

  String _toText(double? value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  double? _toDouble(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized.replaceAll('.', '').replaceAll(',', '.')) ??
        double.tryParse(normalized.replaceAll(',', '.'));
  }

  String? _nullable(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _buildEditorTitle() {
    final companyName = (widget.representedCompanyName ?? '').trim();
    final tenantName = widget.identity.tenantName.trim();
    final targetName = companyName.isNotEmpty ? companyName : tenantName;
    final base = widget.produto == null ? 'Novo Produto' : 'Editar Produto';
    return targetName.isEmpty ? base : '$base - $targetName';
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(subtitle),
                    ],
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProdutoSummaryCard extends StatelessWidget {
  const _ProdutoSummaryCard({
    required this.produto,
    required this.onTap,
  });

  final Produto produto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductThumbnail(produto: produto),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${produto.codigoInterno} - ${produto.descricao}',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      produto.descricaoLonga ??
                        produto.descricaoResumida ??
                        'Cadastro com dados fisicos, fiscais e operacionais.',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(label: produto.origemCadastro.label),
                        _InfoChip(label: produto.status.label),
                        if ((produto.marca ?? '').isNotEmpty)
                          _InfoChip(label: 'Marca ${produto.marca}'),
                        if ((produto.categoria ?? '').isNotEmpty)
                          _InfoChip(label: 'Cat. ${produto.categoria}'),
                        if ((produto.bitola ?? '').isNotEmpty)
                          _InfoChip(
                            label: 'Bitola ${produto.bitola} ${(produto.bitolaUnidade ?? 'mm').toUpperCase()}',
                          ),
                        _InfoChip(label: produto.unidade ?? '-'),
                        _InfoChip(label: 'NCM ${produto.ncm ?? '-'}'),
                        _InfoChip(label: 'CFOP ${produto.cfop ?? '-'}'),
                        _InfoChip(label: 'Estoque ${produto.estoqueVersao ?? '-'}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({required this.produto});

  final Produto produto;

  @override
  Widget build(BuildContext context) {
    final photoUrl = produto.fotoUrl?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 84,
        height: 84,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: photoUrl == null || photoUrl.isEmpty
            ? Center(
                child: Text(
                  produto.descricao.isNotEmpty ? produto.descricao[0].toUpperCase() : '?',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              )
            : Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Text(
                    produto.descricao.isNotEmpty ? produto.descricao[0].toUpperCase() : '?',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
      ),
    );
  }
}

enum _DisableErpSyncAction {
  keepCurrent,
  deactivateErpProducts,
}

Future<void> _openProductImportSheet(
  BuildContext context, {
  required AppIdentity identity,
  required ProdutoRepository repository,
}) async {
  PlatformFile? selectedFile;
  _ProductImportValidation? validation;
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
              allowedExtensions: const ['csv'],
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
            });
          }

          void validate() {
            final file = selectedFile;
            if (file == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selecione um CSV primeiro.')),
              );
              return;
            }
            setSheetState(() {
              validation = _validateProductSheet(file);
            });
          }

          Future<void> importProducts() async {
            final file = selectedFile;
            if (file == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selecione um CSV para importar.')),
              );
              return;
            }

            final report = validation ?? _validateProductSheet(file);
            if (!report.ok) {
              setSheetState(() {
                validation = report;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(report.message)),
              );
              return;
            }

            setSheetState(() {
              importing = true;
            });

            try {
              var imported = 0;
              for (final row in report.rows) {
                final now = DateTime.now().toUtc();
                final descricao = _readRowValue(row, const ['descricao', 'nome']);
                if (descricao.isEmpty) {
                  continue;
                }

                final status = ProductStatus.fromValue(
                  _readRowValue(row, const ['status']),
                );
                final produto = Produto(
                  id: 'prd_${now.microsecondsSinceEpoch}_$imported',
                  tenantId: identity.tenantId,
                  codigoInterno: 'AUTO',
                  descricao: descricao,
                  origemCadastro: ProductSource.excel,
                  status: status,
                  descricaoResumida: _readRowValue(row, const ['descricaoresumida', 'descricao_resumida']),
                  descricaoLonga: _readRowValue(row, const ['descricaolonga', 'descricao_longa']),
                  codigoFabricante: _readRowValue(row, const ['codigofabricante', 'codigo_fabricante']),
                  sku: _readRowValue(row, const ['sku', 'skucomercial', 'sku_comercial']),
                  ean: _readRowValue(row, const ['ean', 'gtin']),
                  marca: _readRowValue(row, const ['marca']),
                  categoria: _readRowValue(row, const ['categoria']),
                  subcategoria: _readRowValue(row, const ['subcategoria', 'sub_categoria']),
                  bitola: _readRowValue(row, const ['bitola', 'medida']),
                  bitolaUnidade: _readRowValue(row, const ['bitolaunidade', 'bitola_unidade', 'unidadebitola', 'unidade_bitola']),
                  unidade: _readRowValue(row, const ['unidade']),
                  multiploVenda: _readDoubleFromRow(row, const ['multiplovenda', 'multiplo_venda']),
                  quantidadeMinima: _readDoubleFromRow(row, const ['quantidademinima', 'quantidade_minima']),
                  ncm: _readRowValue(row, const ['ncm']),
                  cfop: _readRowValue(row, const ['cfop']),
                  aliquotaIcms: _readDoubleFromRow(row, const ['aliquotaicms', 'aliquota_icms']),
                  aliquotaPis: _readDoubleFromRow(row, const ['aliquotapis', 'aliquota_pis']),
                  aliquotaCofins: _readDoubleFromRow(row, const ['aliquotacofins', 'aliquota_cofins']),
                  pesoKg: _readDoubleFromRow(row, const ['pesokg', 'peso_kg']),
                  comprimentoMm: _readDoubleFromRow(row, const ['comprimentomm', 'comprimento_mm']),
                  larguraMm: _readDoubleFromRow(row, const ['larguramm', 'largura_mm']),
                  alturaMm: _readDoubleFromRow(row, const ['alturamm', 'altura_mm']),
                  erpProductId: _readRowValue(row, const ['erpproductid', 'erp_product_id']),
                  erpSyncId: _readRowValue(row, const ['erpsyncid', 'erp_sync_id']),
                  tabelaPrecoVersao: _readRowValue(row, const ['tabelaprecoversao', 'tabela_preco_versao']),
                  estoqueVersao: _readRowValue(row, const ['estoqueversao', 'estoque_versao']),
                  createdAt: now,
                  updatedAt: now,
                );

                await repository.save(produto);
                imported++;
              }

              if (!context.mounted) {
                return;
              }

              Navigator.of(sheetContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$imported produto(s) importado(s) com sucesso.')),
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
                    'Importar produtos por CSV',
                    style: Theme.of(sheetContext).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cabecalho obrigatorio: descricao. O codigo interno e gerado automaticamente.',
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
                        label: const Text('Selecionar CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: importing ? null : validate,
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Validar estrutura'),
                      ),
                      FilledButton.icon(
                        onPressed: importing ? null : importProducts,
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

class _ProductImportValidation {
  const _ProductImportValidation({
    required this.ok,
    required this.message,
    required this.rows,
  });

  final bool ok;
  final String message;
  final List<Map<String, String>> rows;
}

_ProductImportValidation _validateProductSheet(PlatformFile file) {
  final fileName = file.name.trim().toLowerCase();
  if (!fileName.endsWith('.csv')) {
    return const _ProductImportValidation(
      ok: false,
      message: 'Somente CSV e suportado neste momento para produtos.',
      rows: [],
    );
  }

  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    return const _ProductImportValidation(
      ok: false,
      message: 'Arquivo CSV sem conteudo.',
      rows: [],
    );
  }

  final text = _decodeImportFile(bytes);
  final lines = const LineSplitter()
      .convert(text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);

  if (lines.length < 2) {
    return const _ProductImportValidation(
      ok: false,
      message: 'CSV precisa de cabecalho e ao menos uma linha de dados.',
      rows: [],
    );
  }

  final separator = _detectCsvSeparator(lines.first);
  final headers = _splitCsvLine(lines.first, separator)
      .map(_normalizeHeader)
      .toList(growable: false);

  final hasDescricao = headers.contains('descricao') || headers.contains('nome');

  if (!hasDescricao) {
    return const _ProductImportValidation(
      ok: false,
      message: 'Cabecalho invalido. Obrigatorio: descricao.',
      rows: [],
    );
  }

  final parsedRows = <Map<String, String>>[];
  for (final line in lines.skip(1)) {
    final values = _splitCsvLine(line, separator);
    if (values.every((item) => item.trim().isEmpty)) {
      continue;
    }

    final row = <String, String>{};
    for (var index = 0; index < headers.length; index++) {
      row[headers[index]] = index < values.length ? values[index].trim() : '';
    }
    parsedRows.add(row);
  }

  if (parsedRows.isEmpty) {
    return const _ProductImportValidation(
      ok: false,
      message: 'CSV sem linhas validas para importar.',
      rows: [],
    );
  }

  return _ProductImportValidation(
    ok: true,
    message: 'CSV valido com ${parsedRows.length} linha(s) para importacao.',
    rows: parsedRows,
  );
}

String _decodeImportFile(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}

String _normalizeHeader(String value) {
  return value.trim().toLowerCase().replaceAll(' ', '').replaceAll('-', '_');
}

String _detectCsvSeparator(String headerLine) {
  final semicolon = ';'.allMatches(headerLine).length;
  final comma = ','.allMatches(headerLine).length;
  return semicolon > comma ? ';' : ',';
}

List<String> _splitCsvLine(String line, String separator) {
  final result = <String>[];
  final separatorCode = separator.codeUnitAt(0);
  final buffer = StringBuffer();
  var insideQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final charCode = line.codeUnitAt(i);
    final char = line[i];

    if (char == '"') {
      if (insideQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
        continue;
      }
      insideQuotes = !insideQuotes;
      continue;
    }

    if (!insideQuotes && charCode == separatorCode) {
      result.add(buffer.toString());
      buffer.clear();
      continue;
    }

    buffer.writeCharCode(charCode);
  }

  result.add(buffer.toString());
  return result;
}

String _readRowValue(Map<String, String> row, List<String> aliases) {
  for (final alias in aliases) {
    final normalizedAlias = _normalizeHeader(alias);
    final value = row[normalizedAlias]?.trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

double? _readDoubleFromRow(Map<String, String> row, List<String> aliases) {
  final value = _readRowValue(row, aliases);
  if (value.isEmpty) {
    return null;
  }
  return double.tryParse(value.replaceAll('.', '').replaceAll(',', '.')) ??
      double.tryParse(value.replaceAll(',', '.'));
}
