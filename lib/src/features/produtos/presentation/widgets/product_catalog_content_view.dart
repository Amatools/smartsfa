import 'package:flutter/material.dart';

import '../services/product_catalog_content_payload.dart';
import 'product_catalog_table_section.dart';
import 'product_catalog_top_section.dart';
import 'product_editor_sheet.dart';

class ProductCatalogContentView extends StatelessWidget {
  const ProductCatalogContentView({super.key, required this.payload});

  final ProductCatalogContentPayload payload;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopSection(),
            const SizedBox(height: 16),
            _buildMainSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    return ProductCatalogTopSection(
      creatingNewProduct: payload.projection.creatingNewProduct,
      canCreateOrImportProducts: payload.policy.canCreateOrImportProducts,
      availableBrands: payload.projection.availableBrands,
      effectiveBrandFilter: payload.projection.effectiveBrandFilter,
      showEnterpriseSyncSwitchCard: payload.policy.showEnterpriseSyncSwitchCard,
      erpSyncEnabled: payload.policy.erpSyncEnabled,
      erpSyncChangeEnabled: payload.erpSyncChangeEnabled,
      showErpManagedInfoCard: payload.policy.showErpManagedInfoCard,
      onImportExcel: payload.onImportExcel,
      onCreateProduct: payload.onCreateProduct,
      onBrandFilterChanged: payload.onBrandFilterChanged,
      onErpSyncChanged: payload.onErpSyncChanged,
    );
  }

  Widget _buildMainSection() {
    final editorViewState = payload.projection.editorViewState;
    if (editorViewState.editorOpen) {
      return ProductEditorSheet(
        identity: payload.identity,
        repository: payload.repository,
        priceTableRepository: payload.priceTableRepository,
        basePriceRepository: payload.basePriceRepository,
        ensureDefaultTable: payload.ensureDefaultPriceTable,
        isEnterprise: payload.policy.isEnterprise,
        representedCompanyName: payload.representedCompanyName,
        representedCompanyId: payload.representedCompanyId,
        existingProducts: payload.produtos,
        availableBrands: payload.projection.availableBrands,
        produto: editorViewState.editingProduct,
        allowManualActions: payload.policy.canCreateOrImportProducts,
        onClose: payload.onCloseEditor,
        onSaved: payload.onSaved,
        onDeleted: payload.onDeleted,
      );
    }

    return ProductCatalogTableSection(
      visibleProducts: payload.projection.visibleProducts,
      updatingStatusProductIds: payload.updatingStatusProductIds,
      onToggleStatus: payload.onToggleStatus,
      onOpen: payload.onOpenProduct,
      priceFormatter: payload.priceFormatter,
    );
  }
}
