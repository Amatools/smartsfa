import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_paging_repository.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../services/product_catalog_brand_filter_sync_coordinator.dart';
import '../services/product_catalog_content_projection_coordinator.dart';
import '../services/product_catalog_content_payload.dart';
import '../services/product_catalog_policy.dart';
import '../services/product_catalog_workspace_payload.dart';
import 'product_catalog_content_view.dart';

class ProductCatalogWorkspaceSection extends StatefulWidget {
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

  @override
  State<ProductCatalogWorkspaceSection> createState() =>
      _ProductCatalogWorkspaceSectionState();
}

class _ProductCatalogWorkspaceSectionState
    extends State<ProductCatalogWorkspaceSection> {
  static const int _productsPageSize = 50;

  final Map<int, List<Produto>> _pageCache = <int, List<Produto>>{};
  final Map<int, String?> _pageLastDocByPage = <int, String?>{};
  final Map<int, bool> _pageHasMoreByPage = <int, bool>{};

  int _currentPage = 0;
  bool _loadingProductsPage = false;
  Object? _productsLoadError;

  ProductCatalogWorkspacePayload get payload => widget.payload;

  @override
  void initState() {
    super.initState();
    _loadPage(0, reset: true);
  }

  @override
  void didUpdateWidget(covariant ProductCatalogWorkspaceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldTenantId = oldWidget.payload.identity.tenantId.trim();
    final newTenantId = payload.identity.tenantId.trim();
    final oldRepresented = (oldWidget.payload.representedCompanyId ?? '').trim();
    final newRepresented = (payload.representedCompanyId ?? '').trim();
    if (oldTenantId != newTenantId || oldRepresented != newRepresented) {
      _loadPage(0, reset: true);
    }
  }

  void _resetPagingState() {
    _pageCache.clear();
    _pageLastDocByPage.clear();
    _pageHasMoreByPage.clear();
    _currentPage = 0;
    _productsLoadError = null;
  }

  Future<void> _loadPage(int page, {bool reset = false}) async {
    if (_loadingProductsPage) {
      return;
    }

    final pagingRepository = payload.repository is ProdutoPagingRepository
        ? payload.repository as ProdutoPagingRepository
        : null;
    if (pagingRepository == null) {
      setState(() {
        _productsLoadError = StateError(
          'Repositorio de produtos sem suporte a paginacao.',
        );
      });
      return;
    }

    if (reset) {
      setState(() {
        _resetPagingState();
        _loadingProductsPage = true;
      });
    } else {
      setState(() {
        _loadingProductsPage = true;
        _productsLoadError = null;
      });
    }

    try {
      final requestedPage = page < 0 ? 0 : page;
      if (_pageCache.containsKey(requestedPage)) {
        setState(() {
          _currentPage = requestedPage;
        });
        return;
      }

      var startAfterDocumentId = '';
      if (requestedPage > 0) {
        final previousLastDoc = _pageLastDocByPage[requestedPage - 1];
        startAfterDocumentId = (previousLastDoc ?? '').trim();
      }

      final chunk = await pagingRepository.fetchPageChunk(
        tenantId: payload.identity.tenantId,
        limit: _productsPageSize,
        startAfterDocumentId: startAfterDocumentId.isEmpty
            ? null
            : startAfterDocumentId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _pageCache[requestedPage] = chunk.items;
        _pageLastDocByPage[requestedPage] = chunk.lastDocumentId;
        _pageHasMoreByPage[requestedPage] = chunk.hasMore;
        _currentPage = requestedPage;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _productsLoadError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingProductsPage = false;
        });
      }
    }
  }

  Future<void> _goToPreviousPage() async {
    if (_currentPage <= 0) {
      return;
    }
    await _loadPage(_currentPage - 1);
  }

  Future<void> _goToNextPage() async {
    final hasMore = _pageHasMoreByPage[_currentPage] ?? false;
    if (!hasMore) {
      return;
    }
    await _loadPage(_currentPage + 1);
  }

  List<Produto> _filterByRepresentedScope(List<Produto> produtos) {
    final selectedRepresentedCompanyId = (payload.representedCompanyId ?? '')
        .trim();
    if (selectedRepresentedCompanyId.isEmpty) {
      return produtos;
    }

    return produtos
        .where((produto) {
          final productScope = (produto.representedCompanyId ?? '').trim();
          if (productScope.isEmpty) {
            return true;
          }
          return productScope == selectedRepresentedCompanyId;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
        final pageProducts = _pageCache[_currentPage] ?? const <Produto>[];

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _tenantStream(),
      builder: (context, tenantSnapshot) {
        final policy = ProductCatalogPolicy.fromContext(
          tenantData: tenantSnapshot.data,
          role: payload.identity.role,
          isPersonalWorkspace: payload.identity.isPersonalWorkspace,
          isWebPlatform: kIsWeb,
        );

        if (_productsLoadError != null) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Falha ao carregar produtos paginados: $_productsLoadError',
              ),
            ),
          );
        }

        return StreamBuilder<List<CampaignProductList>>(
          stream: _campaignListsStream(
            sourceType: OrderItemSourceType.promotion,
          ),
          initialData: const <CampaignProductList>[],
          builder: (context, promotionListsSnapshot) {
            return StreamBuilder<List<CampaignProductList>>(
              stream: _campaignListsStream(
                sourceType: OrderItemSourceType.highlight,
              ),
              initialData: const <CampaignProductList>[],
              builder: (context, highlightListsSnapshot) {
                final scopedProdutos = _filterByRepresentedScope(pageProducts);
                final promotionProductIds = _resolveActiveCampaignProductIds(
                  promotionListsSnapshot.data ?? const <CampaignProductList>[],
                );
                final highlightProductIds = _resolveActiveCampaignProductIds(
                  highlightListsSnapshot.data ?? const <CampaignProductList>[],
                );

                final projection = widget.projectionCoordinator.resolve(
                  produtos: scopedProdutos,
                  selectedBrandFilter: payload.selectedBrandFilter,
                  selectedSourceFilter: payload.selectedSourceFilter,
                  promotionProductIds: promotionProductIds,
                  highlightProductIds: highlightProductIds,
                  editorOpen: payload.editorOpen,
                  editingProduct: payload.editingProduct,
                );
                widget.brandFilterSyncCoordinator.syncAfterFrameIfNeeded(
                  currentBrandFilter: payload.selectedBrandFilter,
                  effectiveBrandFilter: projection.effectiveBrandFilter,
                  widgetsBinding: WidgetsBinding.instance,
                  isMounted: payload.isMounted,
                  onSync: payload.onBrandFilterChanged,
                );

                final hasPrevious = _currentPage > 0;
                final hasNext = _pageHasMoreByPage[_currentPage] ?? false;

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
                  selectedSourceFilter: payload.selectedSourceFilter,
                  onSourceFilterChanged: payload.onSourceFilterChanged,
                  onToggleStatus: payload.onToggleStatus,
                  onOpenProduct: payload.onOpenProduct,
                  currentProductsPage: _currentPage,
                  hasPreviousProductsPage: hasPrevious,
                  hasNextProductsPage: hasNext,
                  productsPageSize: _productsPageSize,
                  loadingProductsPage: _loadingProductsPage,
                  onPreviousProductsPage: _goToPreviousPage,
                  onNextProductsPage: _goToNextPage,
                  priceFormatter: payload.priceFormatter,
                  onCloseEditor: payload.onCloseEditor,
                  onSaved: payload.onSavedHandlerBuilder(
                    isNew: projection.editorViewState.savingCreatesNewProduct,
                  ),
                  onDeleted: payload.onDeleted,
                );

                if (_loadingProductsPage && scopedProdutos.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ProductCatalogContentView(payload: contentPayload);
              },
            );
          },
        );
      },
    );
  }

  Stream<List<CampaignProductList>> _campaignListsStream({
    required OrderItemSourceType sourceType,
  }) {
    final tenantId = payload.identity.tenantId.trim();
    if (payload.identity.isMock || tenantId.isEmpty) {
      return Stream<List<CampaignProductList>>.value(
        const <CampaignProductList>[],
      );
    }

    return payload.workspaceService.watchCampaignProductLists(
      tenantId: tenantId,
      representedCompanyId: payload.representedCompanyId,
      sourceType: sourceType,
    );
  }

  Set<String> _resolveActiveCampaignProductIds(List<CampaignProductList> lists) {
    if (lists.isEmpty) {
      return const <String>{};
    }

    final ids = <String>{};
    for (final list in lists) {
      if (!list.active) {
        continue;
      }
      for (final productId in list.productIds) {
        final normalizedProductId = productId.trim();
        if (normalizedProductId.isEmpty) {
          continue;
        }
        ids.add(normalizedProductId);
      }
    }
    return ids;
  }

  Stream<Map<String, dynamic>?> _tenantStream() {
    if (payload.identity.isMock) {
      return Stream<Map<String, dynamic>?>.value(null);
    }
    return payload.workspaceService.watchWorkspace(payload.identity.tenantId);
  }
}
