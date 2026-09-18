import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/product_base_price_repository.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';
import '../services/product_catalog_content_projection_coordinator.dart';
import '../services/product_catalog_policy.dart';
import 'product_catalog_table_section.dart';
import 'product_catalog_top_section.dart';
import 'product_editor_sheet.dart';

class ProductCatalogContentView extends StatelessWidget {
  const ProductCatalogContentView({
    super.key,
    required this.identity,
    required this.repository,
    required this.priceTableRepository,
    required this.basePriceRepository,
    required this.ensureDefaultPriceTable,
    required this.representedCompanyName,
    required this.representedCompanyId,
    required this.projection,
    required this.policy,
    required this.produtos,
    required this.updatingStatusProductIds,
    required this.onImportExcel,
    required this.onCreateProduct,
    required this.onBrandFilterChanged,
    required this.onErpSyncChanged,
    required this.onToggleStatus,
    required this.onOpenProduct,
    required this.priceFormatter,
    required this.onCloseEditor,
    required this.onSaved,
    required this.onDeleted,
    required this.erpSyncChangeEnabled,
  });

  final AppIdentity identity;
  final ProdutoRepository repository;
  final TabelaPrecoRepository? priceTableRepository;
  final ProductBasePriceRepository? basePriceRepository;
  final Future<void> Function() ensureDefaultPriceTable;
  final String? representedCompanyName;
  final String? representedCompanyId;
  final ProductCatalogContentProjection projection;
  final ProductCatalogPolicy policy;
  final List<Produto> produtos;
  final Set<String> updatingStatusProductIds;
  final VoidCallback onImportExcel;
  final VoidCallback onCreateProduct;
  final ValueChanged<String> onBrandFilterChanged;
  final ValueChanged<bool> onErpSyncChanged;
  final ValueChanged<Produto> onToggleStatus;
  final ValueChanged<Produto> onOpenProduct;
  final String Function(Produto produto) priceFormatter;
  final VoidCallback onCloseEditor;
  final ValueChanged<Produto> onSaved;
  final VoidCallback onDeleted;
  final bool erpSyncChangeEnabled;

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
      creatingNewProduct: projection.creatingNewProduct,
      canCreateOrImportProducts: policy.canCreateOrImportProducts,
      availableBrands: projection.availableBrands,
      effectiveBrandFilter: projection.effectiveBrandFilter,
      showEnterpriseSyncSwitchCard: policy.showEnterpriseSyncSwitchCard,
      erpSyncEnabled: policy.erpSyncEnabled,
      erpSyncChangeEnabled: erpSyncChangeEnabled,
      showErpManagedInfoCard: policy.showErpManagedInfoCard,
      onImportExcel: onImportExcel,
      onCreateProduct: onCreateProduct,
      onBrandFilterChanged: onBrandFilterChanged,
      onErpSyncChanged: onErpSyncChanged,
    );
  }

  Widget _buildMainSection() {
    final editorViewState = projection.editorViewState;
    if (editorViewState.editorOpen) {
      return ProductEditorSheet(
        identity: identity,
        repository: repository,
        priceTableRepository: priceTableRepository,
        basePriceRepository: basePriceRepository,
        ensureDefaultTable: ensureDefaultPriceTable,
        isEnterprise: policy.isEnterprise,
        representedCompanyName: representedCompanyName,
        representedCompanyId: representedCompanyId,
        existingProducts: produtos,
        availableBrands: projection.availableBrands,
        produto: editorViewState.editingProduct,
        allowManualActions: policy.canCreateOrImportProducts,
        onClose: onCloseEditor,
        onSaved: onSaved,
        onDeleted: onDeleted,
      );
    }

    return ProductCatalogTableSection(
      visibleProducts: projection.visibleProducts,
      updatingStatusProductIds: updatingStatusProductIds,
      onToggleStatus: onToggleStatus,
      onOpen: onOpenProduct,
      priceFormatter: priceFormatter,
    );
  }
}
