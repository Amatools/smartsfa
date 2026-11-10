import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/product_base_price_repository.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';
import '../../../auth/services/workspace_profile_service.dart';
import 'product_catalog_source_filter.dart';

class ProductCatalogWorkspacePayload {
  const ProductCatalogWorkspacePayload({
    required this.identity,
    required this.repository,
    required this.workspaceService,
    required this.selectedBrandFilter,
    required this.selectedSourceFilter,
    required this.editorOpen,
    required this.editingProduct,
    required this.priceTableRepository,
    required this.basePriceRepository,
    required this.ensureDefaultPriceTable,
    required this.representedCompanyName,
    required this.representedCompanyId,
    required this.updatingStatusProductIds,
    required this.onImportExcel,
    required this.onDownloadExcelModel,
    required this.onCreateProduct,
    required this.onBrandFilterChanged,
    required this.onSourceFilterChanged,
    required this.onToggleStatus,
    required this.onOpenProduct,
    required this.priceFormatter,
    required this.onCloseEditor,
    required this.onSavedHandlerBuilder,
    required this.onDeleted,
    required this.isMounted,
  });

  final AppIdentity identity;
  final ProdutoRepository repository;
  final WorkspaceProfileService workspaceService;
  final String selectedBrandFilter;
  final ProductCatalogSourceFilter selectedSourceFilter;
  final bool editorOpen;
  final Produto? editingProduct;
  final TabelaPrecoRepository? priceTableRepository;
  final ProductBasePriceRepository? basePriceRepository;
  final Future<void> Function() ensureDefaultPriceTable;
  final String? representedCompanyName;
  final String? representedCompanyId;
  final Set<String> updatingStatusProductIds;
  final VoidCallback onImportExcel;
  final VoidCallback onDownloadExcelModel;
  final VoidCallback onCreateProduct;
  final ValueChanged<String> onBrandFilterChanged;
  final ValueChanged<ProductCatalogSourceFilter> onSourceFilterChanged;
  final ValueChanged<Produto> onToggleStatus;
  final ValueChanged<Produto> onOpenProduct;
  final String Function(Produto produto) priceFormatter;
  final VoidCallback onCloseEditor;
  final ValueChanged<Produto> Function({required bool isNew})
  onSavedHandlerBuilder;
  final VoidCallback onDeleted;
  final bool Function() isMounted;
}
