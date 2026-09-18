import '../../../../core/models/produto.dart';

class ProductCatalogBrandOptionsResolver {
  const ProductCatalogBrandOptionsResolver();

  List<String> resolve(List<Produto> produtos) {
    final map = <String, String>{};
    for (final produto in produtos) {
      final raw = (produto.marca ?? '').trim();
      if (raw.isEmpty) {
        continue;
      }
      final key = raw.toLowerCase();
      map.putIfAbsent(key, () => raw);
    }

    final values = map.values.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }
}
