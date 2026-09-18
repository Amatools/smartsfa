import '../../../../core/models/produto.dart';

class ProductInternalCodeGenerator {
  const ProductInternalCodeGenerator();

  String buildNextProductCode(List<Produto> existingProducts) {
    var maxSequence = 0;
    final pattern = RegExp(r'(\d+)');

    for (final produto in existingProducts) {
      final codigo = produto.codigoInterno.trim();
      int? parsed;
      for (final match in pattern.allMatches(codigo)) {
        parsed = int.tryParse(match.group(1) ?? '') ?? parsed;
      }
      if (parsed != null && parsed > maxSequence) {
        maxSequence = parsed;
      }
    }

    final next = maxSequence + 1;
    return 'PRD-${next.toString().padLeft(6, '0')}';
  }
}
