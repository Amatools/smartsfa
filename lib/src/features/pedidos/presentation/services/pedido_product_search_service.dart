import '../../../../core/models/produto.dart';
import 'pedido_format_utils.dart';

/// Scores and filters products for the pedido item search/autocomplete.
/// Extracted from `pedidos_page.dart` (SRP) so the matching/scoring
/// algorithm can evolve and be tested independently from widget state.
class PedidoProductSearchService {
  const PedidoProductSearchService._();

  static int scoreProductMatch(
    Produto product,
    String normalizedQuery,
    List<String> tokens,
  ) {
    final name = PedidoFormatUtils.normalizeSearch(product.descricao);
    final code = PedidoFormatUtils.normalizeSearch(product.codigoInterno);
    final makerCode = PedidoFormatUtils.normalizeSearch(
      product.codigoFabricante ?? '',
    );
    final sku = PedidoFormatUtils.normalizeSearch(product.sku ?? '');
    final ean = PedidoFormatUtils.normalizeSearch(product.ean ?? '');
    final brand = PedidoFormatUtils.normalizeSearch(product.marca ?? '');
    final ncm = PedidoFormatUtils.normalizeSearch(product.ncm ?? '');
    final haystack = '$code $makerCode $sku $ean $name $brand $ncm'.trim();
    if (haystack.isEmpty) {
      return -1;
    }

    var score = 0;
    if (normalizedQuery.isNotEmpty && haystack.contains(normalizedQuery)) {
      score += 260;
      final index = haystack.indexOf(normalizedQuery);
      if (index >= 0) {
        score += 40 - (index ~/ 4);
      }
    }

    for (final token in tokens) {
      if (token.isEmpty) {
        continue;
      }

      if (code.startsWith(token)) {
        score += 130;
      } else if (code.contains(token)) {
        score += 110;
      } else if (name.startsWith(token)) {
        score += 120;
      } else if (name.contains(token)) {
        score += 95;
      } else if (brand.contains(token) || ncm.contains(token)) {
        score += 55;
      } else if (PedidoFormatUtils.isSubsequence(token, name) ||
          PedidoFormatUtils.isSubsequence(token, haystack)) {
        score += 25;
      } else {
        return -1;
      }
    }

    if (score <= 0) {
      return -1;
    }
    return score;
  }

  static List<Produto> buildProductResultsForQuery(
    List<Produto> products,
    String query,
  ) {
    final normalizedQuery = PedidoFormatUtils.normalizeSearch(query);
    if (products.isEmpty || normalizedQuery.isEmpty) {
      return const [];
    }

    final tokens = normalizedQuery
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();
    final scored = <({Produto product, int score})>[];
    for (final product in products) {
      final score = scoreProductMatch(product, normalizedQuery, tokens);
      if (score > 0) {
        scored.add((product: product, score: score));
      }
    }

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.product.descricao.toLowerCase().compareTo(
        b.product.descricao.toLowerCase(),
      );
    });

    return scored.map((entry) => entry.product).toList();
  }
}
