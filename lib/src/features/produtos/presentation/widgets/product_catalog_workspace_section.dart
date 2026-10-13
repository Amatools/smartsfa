import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/produto.dart';
import '../services/product_catalog_brand_filter_sync_coordinator.dart';
import '../services/product_catalog_content_projection_coordinator.dart';
import '../services/product_catalog_content_payload.dart';
import '../services/product_catalog_policy.dart';
import '../services/product_catalog_workspace_payload.dart';
import 'product_catalog_content_view.dart';

class ProductCatalogWorkspaceSection extends StatelessWidget {
  const ProductCatalogWorkspaceSection({
    super.key,
    required this.payload,
    this.brandFilterSyncCoordinator =
        const ProductCatalogBrandFilterSyncCoordinator(),
    this.projectionCoordinator =
        const ProductCatalogContentProjectionCoordinator(),
  });

  final ProductCatalogWorkspacePayload payload;
  final ProductCatalogBrandFilterSyncCoordinator brandFilterSyncCoordinator;
  final ProductCatalogContentProjectionCoordinator projectionCoordinator;

  List<Produto> _filterByRepresentedScope(List<Produto> produtos) {
    final selectedRepresentedCompanyId = (payload.representedCompanyId ?? '')
        .trim();
    if (selectedRepresentedCompanyId.isEmpty) {
      return const <Produto>[];
    }

    return produtos
        .where((produto) {
          final productScope = (produto.representedCompanyId ?? '').trim();
          return productScope == selectedRepresentedCompanyId;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _tenantStream(),
      builder: (context, tenantSnapshot) {
        final policy = ProductCatalogPolicy.fromContext(
          tenantData: tenantSnapshot.data,
          role: payload.identity.role,
          isPersonalWorkspace: payload.identity.isPersonalWorkspace,
          isWebPlatform: kIsWeb,
        );

        return StreamBuilder<List<Produto>>(
          stream: payload.repository.watchAll(
            tenantId: payload.identity.tenantId,
          ),
          initialData: const [],
          builder: (context, productsSnapshot) {
            final scopedProdutos = _filterByRepresentedScope(
              productsSnapshot.data ?? const <Produto>[],
            );
            final projection = projectionCoordinator.resolve(
              produtos: scopedProdutos,
              selectedBrandFilter: payload.selectedBrandFilter,
              editorOpen: payload.editorOpen,
              editingProduct: payload.editingProduct,
            );
            brandFilterSyncCoordinator.syncAfterFrameIfNeeded(
              currentBrandFilter: payload.selectedBrandFilter,
              effectiveBrandFilter: projection.effectiveBrandFilter,
              widgetsBinding: WidgetsBinding.instance,
              isMounted: payload.isMounted,
              onSync: payload.onBrandFilterChanged,
            );

            final contentPayload = ProductCatalogContentPayload(
              identity: payload.identity,
              repository: payload.repository,
              priceTableRepository: payload.priceTableRepository,
              basePriceRepository: payload.basePriceRepository,
              ensureDefaultPriceTable: payload.ensureDefaultPriceTable,
              representedCompanyName: payload.representedCompanyName,
              representedCompanyId: payload.representedCompanyId,
              projection: projection,
              policy: policy,
              produtos: scopedProdutos,
              updatingStatusProductIds: payload.updatingStatusProductIds,
              onImportExcel: payload.onImportExcel,
              onDownloadExcelModel: payload.onDownloadExcelModel,
              onCreateProduct: payload.onCreateProduct,
              onBrandFilterChanged: payload.onBrandFilterChanged,
              onErpSyncChanged: payload.onErpSyncChanged,
              onToggleStatus: payload.onToggleStatus,
              onOpenProduct: payload.onOpenProduct,
              priceFormatter: payload.priceFormatter,
              onCloseEditor: payload.onCloseEditor,
              onSaved: payload.onSavedHandlerBuilder(
                isNew: projection.editorViewState.savingCreatesNewProduct,
              ),
              onDeleted: payload.onDeleted,
              erpSyncChangeEnabled: payload.erpSyncChangeEnabled,
            );

            return ProductCatalogContentView(payload: contentPayload);
          },
        );
      },
    );
  }

  Stream<Map<String, dynamic>?> _tenantStream() {
    if (payload.identity.isMock) {
      return Stream<Map<String, dynamic>?>.value(null);
    }
    return payload.workspaceService.watchWorkspace(payload.identity.tenantId);
  }
}
