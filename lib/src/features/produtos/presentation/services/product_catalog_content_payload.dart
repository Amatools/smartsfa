import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/product_base_price_repository.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';
import 'product_catalog_content_projection_coordinator.dart';
import 'product_catalog_policy.dart';
import 'product_catalog_source_filter.dart';

class ProductCatalogContentPayload {
  const ProductCatalogContentPayload({
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
    required this.onDownloadExcelModel,
    required this.onCreateProduct,
    required this.onBrandFilterChanged,
    required this.selectedSourceFilter,
    required this.onSourceFilterChanged,
    required this.onToggleStatus,
    required this.onOpenProduct,
    required this.currentProductsPage,
    required this.hasPreviousProductsPage,
    required this.hasNextProductsPage,
    required this.productsPageSize,
    required this.loadingProductsPage,
    required this.onPreviousProductsPage,
    required this.onNextProductsPage,
    required this.priceFormatter,
    required this.onCloseEditor,
    required this.onSaved,
    required this.onDeleted,
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
  final VoidCallback onDownloadExcelModel;
  final VoidCallback onCreateProduct;
  final ValueChanged<String> onBrandFilterChanged;
  final ProductCatalogSourceFilter selectedSourceFilter;
  final ValueChanged<ProductCatalogSourceFilter> onSourceFilterChanged;
  final ValueChanged<Produto> onToggleStatus;
  final ValueChanged<Produto> onOpenProduct;
  final int currentProductsPage;
  final bool hasPreviousProductsPage;
  final bool hasNextProductsPage;
  final int productsPageSize;
  final bool loadingProductsPage;
  final VoidCallback onPreviousProductsPage;
  final VoidCallback onNextProductsPage;
  final String Function(Produto produto) priceFormatter;
  final VoidCallback onCloseEditor;
  final ValueChanged<Produto> onSaved;
  final VoidCallback onDeleted;
}
