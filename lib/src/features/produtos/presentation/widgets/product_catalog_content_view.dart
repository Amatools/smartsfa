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
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1260),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopSection(),
                const SizedBox(height: 14),
                _buildBrandFilterSection(),
                const SizedBox(height: 12),
                _buildMainSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    return ProductCatalogTopSection(
      creatingNewProduct: payload.projection.creatingNewProduct,
      canCreateOrImportProducts: payload.policy.canCreateOrImportProducts,
      representedCompanyName: payload.representedCompanyName,
      showEnterpriseSyncSwitchCard: payload.policy.showEnterpriseSyncSwitchCard,
      erpSyncEnabled: payload.policy.erpSyncEnabled,
      erpSyncChangeEnabled: payload.erpSyncChangeEnabled,
      onImportExcel: payload.onImportExcel,
      onDownloadExcelModel: payload.onDownloadExcelModel,
      onCreateProduct: payload.onCreateProduct,
      onErpSyncChanged: payload.onErpSyncChanged,
    );
  }

  Widget _buildBrandFilterSection() {
    final availableBrands = payload.projection.availableBrands;
    if (availableBrands.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
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
                initialValue: payload.projection.effectiveBrandFilter,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: <String>['todas', ...availableBrands]
                    .map(
                      (brand) => DropdownMenuItem<String>(
                        value: brand,
                        child: Text(
                          brand == 'todas' ? 'Todas as marcas' : brand,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  payload.onBrandFilterChanged(value);
                },
              ),
            ),
          ],
        ),
      ),
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
