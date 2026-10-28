/// Politica central de arredondamento do motor de tributacao.
///
/// Regra (ver docs/tributacao_motor_especificacao_tecnica.md, secao 6):
/// - Arredondar apenas o valor final de cada tributo, nunca bases
///   intermediarias (base ST, base ICMS, etc. mantem precisao total).
/// - Arredondamento "meio para cima" (round half up), compativel com a
///   convencao usada pela generalidade dos ERPs fiscais brasileiros,
///   em vez do "round half to even" (bankers rounding) padrao do Dart.
class TaxRoundingPolicy {
  const TaxRoundingPolicy._();

  /// Arredonda [value] para [decimals] casas decimais usando a regra
  /// "meio para cima". Default: 2 casas decimais (moeda).
  static double round(double value, {int decimals = 2}) {
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    final factor = _pow10(decimals);
    // Pequeno epsilon para compensar erros de representacao binaria de
    // ponto flutuante (ex.: 2.675 representado internamente como
    // 2.67499999999...), evitando arredondar para baixo por erro de
    // precisao em vez da regra de negocio "meio para cima".
    const epsilon = 1e-9;
    final shifted = value * factor;
    final rounded = value >= 0
        ? (shifted + 0.5 + epsilon).floorToDouble()
        : -((-shifted) + 0.5 + epsilon).floorToDouble();
    return rounded / factor;
  }

  /// Atalho para arredondamento monetario (2 casas decimais).
  static double roundCurrency(double value) => round(value, decimals: 2);

  static double _pow10(int decimals) {
    var factor = 1.0;
    for (var i = 0; i < decimals; i++) {
      factor *= 10;
    }
    return factor;
  }
}
