import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/product_base_price_repository.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../services/product_catalog_brand_filter_sync_coordinator.dart';
import '../services/product_catalog_content_projection_coordinator.dart';
import '../services/product_catalog_policy.dart';
import 'product_catalog_content_view.dart';

class ProductCatalogWorkspaceSection extends StatelessWidget {
  const ProductCatalogWorkspaceSection({
    super.key,
    required this.identity,
    required this.repository,
    required this.workspaceService,
    required this.selectedBrandFilter,
    required this.editorOpen,
    required this.editingProduct,
    required this.priceTableRepository,
    required this.basePriceRepository,
    required this.ensureDefaultPriceTable,
    required this.representedCompanyName,
    required this.representedCompanyId,
    required this.updatingStatusProductIds,
    required this.onImportExcel,
    required this.onCreateProduct,
    required this.onBrandFilterChanged,
    required this.onErpSyncChanged,
    required this.onToggleStatus,
    required this.onOpenProduct,
    required this.priceFormatter,
    required this.onCloseEditor,
    required this.onSavedHandlerBuilder,
    required this.onDeleted,
    required this.erpSyncChangeEnabled,
    required this.isMounted,
    this.brandFilterSyncCoordinator =
        const ProductCatalogBrandFilterSyncCoordinator(),
    this.projectionCoordinator =
        const ProductCatalogContentProjectionCoordinator(),
  });

  final AppIdentity identity;
  final ProdutoRepository repository;
  final WorkspaceProfileService workspaceService;
  final String selectedBrandFilter;
  final bool editorOpen;
  final Produto? editingProduct;
  final TabelaPrecoRepository? priceTableRepository;
  final ProductBasePriceRepository? basePriceRepository;
  final Future<void> Function() ensureDefaultPriceTable;
  final String? representedCompanyName;
  final String? representedCompanyId;
  final Set<String> updatingStatusProductIds;
  final VoidCallback onImportExcel;
  final VoidCallback onCreateProduct;
  final ValueChanged<String> onBrandFilterChanged;
  final ValueChanged<bool> onErpSyncChanged;
  final ValueChanged<Produto> onToggleStatus;
  final ValueChanged<Produto> onOpenProduct;
  final String Function(Produto produto) priceFormatter;
  final VoidCallback onCloseEditor;
  final ValueChanged<Produto> Function({required bool isNew})
  onSavedHandlerBuilder;
  final VoidCallback onDeleted;
  final bool erpSyncChangeEnabled;
  final bool Function() isMounted;
  final ProductCatalogBrandFilterSyncCoordinator brandFilterSyncCoordinator;
  final ProductCatalogContentProjectionCoordinator projectionCoordinator;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _tenantStream(),
      builder: (context, tenantSnapshot) {
        final policy = ProductCatalogPolicy.fromContext(
          tenantData: tenantSnapshot.data,
          role: identity.role,
          isPersonalWorkspace: identity.isPersonalWorkspace,
        );

        return StreamBuilder<List<Produto>>(
          stream: repository.watchAll(tenantId: identity.tenantId),
          initialData: const [],
          builder: (context, productsSnapshot) {
            final produtos = productsSnapshot.data ?? const [];
            final projection = projectionCoordinator.resolve(
              produtos: produtos,
              selectedBrandFilter: selectedBrandFilter,
              editorOpen: editorOpen,
              editingProduct: editingProduct,
            );
            brandFilterSyncCoordinator.syncAfterFrameIfNeeded(
              currentBrandFilter: selectedBrandFilter,
              effectiveBrandFilter: projection.effectiveBrandFilter,
              widgetsBinding: WidgetsBinding.instance,
              isMounted: isMounted,
              onSync: onBrandFilterChanged,
            );

            return ProductCatalogContentView(
              identity: identity,
              repository: repository,
              priceTableRepository: priceTableRepository,
              basePriceRepository: basePriceRepository,
              ensureDefaultPriceTable: ensureDefaultPriceTable,
              representedCompanyName: representedCompanyName,
              representedCompanyId: representedCompanyId,
              projection: projection,
              policy: policy,
              produtos: produtos,
              updatingStatusProductIds: updatingStatusProductIds,
              onImportExcel: onImportExcel,
              onCreateProduct: onCreateProduct,
              onBrandFilterChanged: onBrandFilterChanged,
              onErpSyncChanged: onErpSyncChanged,
              onToggleStatus: onToggleStatus,
              onOpenProduct: onOpenProduct,
              priceFormatter: priceFormatter,
              onCloseEditor: onCloseEditor,
              onSaved: onSavedHandlerBuilder(
                isNew: projection.editorViewState.savingCreatesNewProduct,
              ),
              onDeleted: onDeleted,
              erpSyncChangeEnabled: erpSyncChangeEnabled,
            );
          },
        );
      },
    );
  }

  Stream<Map<String, dynamic>?> _tenantStream() {
    if (identity.isMock) {
      return Stream<Map<String, dynamic>?>.value(null);
    }
    return workspaceService.watchWorkspace(identity.tenantId);
  }
}
