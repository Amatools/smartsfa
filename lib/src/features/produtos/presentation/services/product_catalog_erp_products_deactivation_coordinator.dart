import '../../../../core/models/domain_types.dart';
import '../../../../core/repositories/produto_repository.dart';

class ProductCatalogErpProductsDeactivationResult {
  const ProductCatalogErpProductsDeactivationResult({
    required this.updatedCount,
  });

  final int updatedCount;
}

class ProductCatalogErpProductsDeactivationCoordinator {
  const ProductCatalogErpProductsDeactivationCoordinator();

  Future<ProductCatalogErpProductsDeactivationResult> execute({
    required ProdutoRepository repository,
    required String tenantId,
  }) async {
    final produtos = await repository.fetchAll(tenantId: tenantId);
    var updatedCount = 0;

    for (final produto in produtos) {
      if (produto.origemCadastro != ProductSource.erp) {
        continue;
      }
      if (produto.status == ProductStatus.inactive) {
        continue;
      }

      await repository.save(
        produto.copyWith(
          status: ProductStatus.inactive,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      updatedCount++;
    }

    return ProductCatalogErpProductsDeactivationResult(updatedCount: updatedCount);
  }
}
