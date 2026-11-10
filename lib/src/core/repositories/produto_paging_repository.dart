import '../models/produto.dart';

class ProdutoPageChunk {
  const ProdutoPageChunk({
    required this.items,
    required this.lastDocumentId,
    required this.hasMore,
  });

  final List<Produto> items;
  final String? lastDocumentId;
  final bool hasMore;
}

abstract class ProdutoPagingRepository {
  Future<ProdutoPageChunk> fetchPageChunk({
    required String tenantId,
    required int limit,
    String? startAfterDocumentId,
  });
}
