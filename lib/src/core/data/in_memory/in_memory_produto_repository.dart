import '../../models/produto.dart';
import '../../repositories/produto_paging_repository.dart';
import '../../repositories/produto_repository.dart';
import 'in_memory_tenant_scoped_repository.dart';

class InMemoryProdutoRepository extends InMemoryTenantScopedRepository<Produto>
    implements ProdutoRepository, ProdutoPagingRepository {
  InMemoryProdutoRepository({super.seedItems = const []});

  @override
  Future<ProdutoPageChunk> fetchPageChunk({
    required String tenantId,
    required int limit,
    String? startAfterDocumentId,
  }) async {
    final safeLimit = limit <= 0 ? 50 : limit;
    final normalizedCursor = (startAfterDocumentId ?? '').trim();

    final all = await fetchAll(tenantId: tenantId);
    final sorted = List<Produto>.from(
      all.where((produto) => produto.deletedAt == null),
    )..sort((a, b) => a.id.compareTo(b.id));

    var startIndex = 0;
    if (normalizedCursor.isNotEmpty) {
      startIndex = sorted.indexWhere((produto) => produto.id == normalizedCursor);
      if (startIndex >= 0) {
        startIndex += 1;
      } else {
        startIndex = sorted.indexWhere((produto) => produto.id.compareTo(normalizedCursor) > 0);
        if (startIndex < 0) {
          startIndex = sorted.length;
        }
      }
    }

    if (startIndex >= sorted.length) {
      return const ProdutoPageChunk(
        items: <Produto>[],
        lastDocumentId: null,
        hasMore: false,
      );
    }

    final endIndex = (startIndex + safeLimit).clamp(0, sorted.length);
    final pageItems = sorted.sublist(startIndex, endIndex);

    return ProdutoPageChunk(
      items: pageItems,
      lastDocumentId: pageItems.isEmpty ? null : pageItems.last.id,
      hasMore: endIndex < sorted.length,
    );
  }
}