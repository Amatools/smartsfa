import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/product_base_price_repository.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';
import 'product_catalog_content_projection_coordinator.dart';
import 'product_catalog_policy.dart';

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
}
