import 'package:flutter/material.dart';

import '../services/product_catalog_content_payload.dart';
import '../services/product_catalog_source_filter.dart';
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
                _buildSourceFilterSection(context),
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
      onImportExcel: payload.onImportExcel,
      onDownloadExcelModel: payload.onDownloadExcelModel,
      onCreateProduct: payload.onCreateProduct,
    );
  }

  Widget _buildBrandFilterSection() {
    final selectedBrand = payload.projection.effectiveBrandFilter;
    final availableBrands = List<String>.from(payload.projection.availableBrands);
    if (selectedBrand != 'todas' &&
        selectedBrand.trim().isNotEmpty &&
        !availableBrands.contains(selectedBrand)) {
      availableBrands.insert(0, selectedBrand);
    }

    if (availableBrands.isEmpty && selectedBrand == 'todas') {
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
                initialValue: selectedBrand,
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

  Widget _buildSourceFilterSection(BuildContext context) {
    final projection = payload.projection;
    final sourceOptions = <ProductCatalogSourceFilter, String>{
      ProductCatalogSourceFilter.catalogo: 'Catalogo',
      ProductCatalogSourceFilter.promocoes:
          'Promocoes (${projection.promotionVisibleCount})',
      ProductCatalogSourceFilter.destaques:
          'Destaques (${projection.highlightVisibleCount})',
    };
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useCompactSelector = screenWidth < 720;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_offer_outlined),
                const SizedBox(width: 12),
                const Text('Origem comercial'),
              ],
            ),
            const SizedBox(height: 10),
            if (useCompactSelector)
              DropdownButtonFormField<ProductCatalogSourceFilter>(
                initialValue: payload.selectedSourceFilter,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: sourceOptions.entries
                    .map(
                      (entry) => DropdownMenuItem<ProductCatalogSourceFilter>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  payload.onSourceFilterChanged(value);
                },
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(
                      sourceOptions[ProductCatalogSourceFilter.catalogo]!,
                    ),
                    selected:
                        payload.selectedSourceFilter ==
                        ProductCatalogSourceFilter.catalogo,
                    onSelected: (_) {
                      payload.onSourceFilterChanged(
                        ProductCatalogSourceFilter.catalogo,
                      );
                    },
                  ),
                  ChoiceChip(
                    label: Text(
                      sourceOptions[ProductCatalogSourceFilter.promocoes]!,
                    ),
                    selected:
                        payload.selectedSourceFilter ==
                        ProductCatalogSourceFilter.promocoes,
                    onSelected: (_) {
                      payload.onSourceFilterChanged(
                        ProductCatalogSourceFilter.promocoes,
                      );
                    },
                  ),
                  ChoiceChip(
                    label: Text(
                      sourceOptions[ProductCatalogSourceFilter.destaques]!,
                    ),
                    selected:
                        payload.selectedSourceFilter ==
                        ProductCatalogSourceFilter.destaques,
                    onSelected: (_) {
                      payload.onSourceFilterChanged(
                        ProductCatalogSourceFilter.destaques,
                      );
                    },
                  ),
                ],
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
      currentPage: payload.currentProductsPage,
      hasPreviousPage: payload.hasPreviousProductsPage,
      hasNextPage: payload.hasNextProductsPage,
      loadingPage: payload.loadingProductsPage,
      pageSize: payload.productsPageSize,
      onPreviousPage: payload.onPreviousProductsPage,
      onNextPage: payload.onNextProductsPage,
      priceFormatter: payload.priceFormatter,
    );
  }
}
